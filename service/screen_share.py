"""Short-lived, paired receiver for explicit Android screen-share sessions.

All stream state and the single latest JPEG stay in memory. This is not a capture API:
the sender must first obtain Android MediaProjection consent itself.
"""
from __future__ import annotations

import asyncio
import hashlib
import json
import secrets
import time
from collections import defaultdict, deque
from dataclasses import dataclass, field

from fastapi import HTTPException, Request, WebSocket
from pydantic import BaseModel, ConfigDict, Field

PAIRING_TTL_SECONDS = 5 * 60
SENDER_TOKEN_TTL_SECONDS = 30 * 24 * 60 * 60
MAX_PAIRINGS = 5
MAX_SESSIONS = 2
MAX_PAIRING_FAILURES = 5
MAX_FRAME_BYTES = 1_500_000
MAX_FRAME_FPS = 5
FRAME_STALE_SECONDS = 10
MAX_STREAM_SECONDS = 60 * 60
SESSION_APPROVAL_TTL_SECONDS = 5 * 60


class StrictShareRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


class PairingRedeemRequest(StrictShareRequest):
    pairing_id: str = Field(pattern=r"^[a-f0-9]{32}$")
    pairing_code: str = Field(min_length=32, max_length=64)
    sender_label: str = Field(min_length=1, max_length=48)


class CreateShareSessionRequest(StrictShareRequest):
    pairing_id: str = Field(pattern=r"^[a-f0-9]{32}$")


def _digest(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _bearer(value: str | None) -> str:
    if not value or not value.startswith("Bearer "):
        return ""
    return value[7:]


@dataclass
class Pairing:
    id: str
    code_hash: str
    created_at: float
    expires_at: float
    state: str = "waiting_for_sender"
    failed_attempts: int = 0
    sender_label: str | None = None
    sender_token_hash: str | None = None
    sender_token_expires_at: float | None = None


@dataclass
class ShareSession:
    id: str
    pairing_id: str
    state: str = "awaiting_receiver_approval"
    created_at: float = field(default_factory=time.time)
    approved_at: float | None = None
    last_sequence: int = 0
    last_frame: bytes | None = None
    last_frame_at: float | None = None
    last_frame_mono: float | None = None
    sender_socket: WebSocket | None = None
    last_error: str | None = None
    stream_started_mono: float | None = None
    stream_started_at: float | None = None


class ScreenShareRegistry:
    """In-process registry; a service restart safely invalidates pairings/sessions."""

    def __init__(self) -> None:
        self._lock = asyncio.Lock()
        self._pairings: dict[str, Pairing] = {}
        self._sessions: dict[str, ShareSession] = {}
        self._redeem_calls: dict[str, deque[float]] = defaultdict(deque)

    @staticmethod
    def _clean_pairing(pairing: Pairing, now: float) -> None:
        if pairing.state == "waiting_for_sender" and pairing.expires_at <= now:
            pairing.state = "expired"
        if (pairing.state == "paired" and pairing.sender_token_expires_at is not None
                and pairing.sender_token_expires_at <= now):
            pairing.state = "expired"

    async def create_pairing(self) -> dict:
        now = time.time()
        async with self._lock:
            for pairing in self._pairings.values():
                self._clean_pairing(pairing, now)
            pending = [p for p in self._pairings.values() if p.state == "waiting_for_sender"]
            if len(pending) >= MAX_PAIRINGS:
                raise HTTPException(429, "Too many active pairing codes; revoke or wait for one to expire")
            code = secrets.token_urlsafe(24)
            pairing = Pairing(
                id=secrets.token_hex(16),
                code_hash=_digest(code),
                created_at=now,
                expires_at=now + PAIRING_TTL_SECONDS,
            )
            self._pairings[pairing.id] = pairing
            return {
                "pairing_id": pairing.id,
                "pairing_code": code,
                "expires_in_seconds": PAIRING_TTL_SECONDS,
                "state": pairing.state,
            }

    async def allow_redeem_attempt(self, source: str) -> None:
        now = time.monotonic()
        async with self._lock:
            if source not in self._redeem_calls and len(self._redeem_calls) >= 512:
                self._redeem_calls.pop(next(iter(self._redeem_calls)))
            attempts = self._redeem_calls[source]
            while attempts and attempts[0] <= now - 60:
                attempts.popleft()
            if len(attempts) >= 10:
                raise HTTPException(429, "Pairing attempt limit reached; wait one minute")
            attempts.append(now)

    async def redeem_pairing(self, pairing_id: str, code: str, sender_label: str) -> dict:
        now = time.time()
        async with self._lock:
            pairing = self._pairings.get(pairing_id)
            if pairing is None:
                raise HTTPException(404, "Pairing code is invalid or expired")
            self._clean_pairing(pairing, now)
            if pairing.state != "waiting_for_sender":
                raise HTTPException(409, "Pairing code is invalid, expired or already used")
            if not secrets.compare_digest(pairing.code_hash, _digest(code)):
                pairing.failed_attempts += 1
                if pairing.failed_attempts >= MAX_PAIRING_FAILURES:
                    pairing.state = "revoked"
                raise HTTPException(404, "Pairing code is invalid or expired")
            token = secrets.token_urlsafe(32)
            pairing.code_hash = ""
            pairing.state = "paired"
            pairing.sender_label = sender_label
            pairing.sender_token_hash = _digest(token)
            pairing.sender_token_expires_at = now + SENDER_TOKEN_TTL_SECONDS
            return {
                "pairing_id": pairing.id,
                "sender_token": token,
                "sender_token_expires_in_seconds": SENDER_TOKEN_TTL_SECONDS,
                "state": "paired_waiting_for_receiver_approval",
            }

    async def authenticate_sender(self, pairing_id: str, authorization: str | None) -> Pairing:
        supplied = _bearer(authorization)
        if not supplied:
            raise HTTPException(401, "Paired sender authentication required")
        now = time.time()
        async with self._lock:
            pairing = self._pairings.get(pairing_id)
            if pairing is None:
                raise HTTPException(404, "Paired sender not found")
            self._clean_pairing(pairing, now)
            if (pairing.state != "paired" or not pairing.sender_token_hash
                    or pairing.sender_token_expires_at is None
                    or pairing.sender_token_expires_at <= now
                    or not secrets.compare_digest(pairing.sender_token_hash, _digest(supplied))):
                raise HTTPException(401, "Paired sender authentication required")
            return pairing

    async def pairings(self) -> list[dict]:
        now = time.time()
        async with self._lock:
            for pairing in self._pairings.values():
                self._clean_pairing(pairing, now)
            return [
                {
                    "pairing_id": p.id,
                    "state": p.state,
                    "sender_label": p.sender_label,
                    "created_at": p.created_at,
                    "expires_at": p.expires_at if p.state == "waiting_for_sender" else None,
                    "sender_token_expires_at": p.sender_token_expires_at if p.state == "paired" else None,
                }
                for p in sorted(self._pairings.values(), key=lambda item: item.created_at, reverse=True)
                if p.state != "revoked"
            ]

    async def create_session(self, pairing_id: str) -> dict:
        async with self._lock:
            now = time.time()
            for session in self._sessions.values():
                self._clean_session(session, now)
            pairing = self._pairings.get(pairing_id)
            if pairing is None:
                raise HTTPException(404, "Paired sender not found")
            self._clean_pairing(pairing, now)
            if pairing.state != "paired":
                raise HTTPException(409, "Pair this sender again before requesting a share")
            existing = [s for s in self._sessions.values() if s.pairing_id == pairing_id
                        and s.state in {"awaiting_receiver_approval", "approved", "active"}]
            if existing:
                raise HTTPException(409, "A share request is already pending or active")
            active = sum(s.state in {"awaiting_receiver_approval", "approved", "active"} for s in self._sessions.values())
            if active >= MAX_SESSIONS:
                raise HTTPException(429, "Too many pending or active screen-share sessions")
            session = ShareSession(id=secrets.token_hex(16), pairing_id=pairing_id)
            self._sessions[session.id] = session
            return self._session_summary(session)

    @staticmethod
    def _clean_session(session: ShareSession, now: float) -> None:
        if (session.state in {"awaiting_receiver_approval", "approved"}
                and now - session.created_at > SESSION_APPROVAL_TTL_SECONDS):
            ScreenShareRegistry._stop_locked(session)
            session.state = "expired"

    @staticmethod
    def _session_summary(session: ShareSession) -> dict:
        return {
            "session_id": session.id,
            "pairing_id": session.pairing_id,
            "state": session.state,
            "created_at": session.created_at,
            "approved_at": session.approved_at,
            "last_sequence": session.last_sequence,
            "last_frame_at": session.last_frame_at,
            "last_error": session.last_error,
        }

    async def sessions(self) -> list[dict]:
        async with self._lock:
            now = time.time()
            for session in self._sessions.values():
                self._clean_session(session, now)
            return [self._session_summary(s) for s in sorted(
                self._sessions.values(), key=lambda item: item.created_at, reverse=True
            )]

    async def approve_session(self, session_id: str) -> dict:
        async with self._lock:
            session = self._sessions.get(session_id)
            if session is None:
                raise HTTPException(404, "Share session not found")
            self._clean_session(session, time.time())
            pairing = self._pairings.get(session.pairing_id)
            self._clean_pairing(pairing, time.time()) if pairing else None
            if pairing is None or pairing.state != "paired":
                session.state = "stopped"
                raise HTTPException(409, "Paired sender expired or was revoked")
            if session.state != "awaiting_receiver_approval":
                raise HTTPException(409, "Share request is no longer awaiting approval")
            session.state = "approved"
            session.approved_at = time.time()
            return self._session_summary(session)

    async def sender_for_session(self, session_id: str, authorization: str | None) -> tuple[ShareSession, Pairing]:
        supplied = _bearer(authorization)
        if not supplied:
            raise HTTPException(401, "Paired sender authentication required")
        async with self._lock:
            session = self._sessions.get(session_id)
            if session is None:
                raise HTTPException(404, "Share session not found")
            now = time.time()
            self._clean_session(session, now)
            pairing = self._pairings.get(session.pairing_id)
            if pairing:
                self._clean_pairing(pairing, now)
            if (pairing is None or pairing.state != "paired" or not pairing.sender_token_hash
                    or pairing.sender_token_expires_at is None
                    or pairing.sender_token_expires_at <= now
                    or not secrets.compare_digest(pairing.sender_token_hash, _digest(supplied))):
                raise HTTPException(401, "Paired sender authentication required")
            if session.state != "approved":
                raise HTTPException(409, "Receiver approval is required before streaming")
            return session, pairing

    async def sender_session_status(self, session_id: str, authorization: str | None) -> dict:
        supplied = _bearer(authorization)
        if not supplied:
            raise HTTPException(401, "Paired sender authentication required")
        async with self._lock:
            session = self._sessions.get(session_id)
            if session is None:
                raise HTTPException(404, "Share session not found")
            self._clean_session(session, time.time())
            pairing = self._pairings.get(session.pairing_id)
            now = time.time()
            if pairing:
                self._clean_pairing(pairing, now)
            if (pairing is None or pairing.state != "paired" or not pairing.sender_token_hash
                    or pairing.sender_token_expires_at is None
                    or pairing.sender_token_expires_at <= now
                    or not secrets.compare_digest(pairing.sender_token_hash, _digest(supplied))):
                raise HTTPException(401, "Paired sender authentication required")
            return self._session_summary(session)

    async def start_stream(self, session_id: str, pairing_id: str, ws: WebSocket) -> bool:
        async with self._lock:
            session = self._sessions.get(session_id)
            if session is None or session.pairing_id != pairing_id:
                return False
            now = time.time()
            self._clean_session(session, now)
            pairing = self._pairings.get(pairing_id)
            if pairing is not None:
                self._clean_pairing(pairing, now)
            if (session.state != "approved" or session.sender_socket is not None
                    or pairing is None or pairing.state != "paired"
                    or pairing.sender_token_hash is None
                    or pairing.sender_token_expires_at is None
                    or pairing.sender_token_expires_at <= now):
                return False
            session.state = "active"
            session.sender_socket = ws
            session.last_error = None
            session.stream_started_mono = time.monotonic()
            session.stream_started_at = time.time()
            return True

    async def publish_frame(self, session_id: str, ws: WebSocket, frame: bytes) -> int | None:
        if len(frame) > MAX_FRAME_BYTES or len(frame) < 4 or not frame.startswith(b"\xff\xd8") or not frame.endswith(b"\xff\xd9"):
            return None
        now_mono = time.monotonic()
        async with self._lock:
            session = self._sessions.get(session_id)
            if not session or session.state != "active" or session.sender_socket is not ws:
                return None
            pairing = self._pairings.get(session.pairing_id)
            if (pairing is None or pairing.state != "paired"
                    or pairing.sender_token_expires_at is None
                    or pairing.sender_token_expires_at <= time.time()):
                self._stop_locked(session)
                return None
            if (session.stream_started_mono is not None
                    and now_mono - session.stream_started_mono > MAX_STREAM_SECONDS):
                self._stop_locked(session)
                return None
            if session.last_frame_mono is not None and now_mono - session.last_frame_mono < 1 / MAX_FRAME_FPS:
                return -1
            session.last_sequence += 1
            session.last_frame = bytes(frame)
            session.last_frame_at = time.time()
            session.last_frame_mono = now_mono
            return session.last_sequence

    async def frame(self, session_id: str, after_sequence: int) -> tuple[bytes, int] | None:
        now_mono = time.monotonic()
        async with self._lock:
            session = self._sessions.get(session_id)
            if session is None:
                raise HTTPException(404, "Share session not found")
            if session.state != "active":
                raise HTTPException(409, "Screen-share session is not active")
            if (session.last_frame is None or session.last_sequence <= after_sequence
                    or session.last_frame_mono is None
                    or now_mono - session.last_frame_mono > FRAME_STALE_SECONDS):
                return None
            return session.last_frame, session.last_sequence

    async def stop_session(self, session_id: str) -> tuple[dict, WebSocket | None]:
        async with self._lock:
            session = self._sessions.get(session_id)
            if session is None:
                raise HTTPException(404, "Share session not found")
            socket = session.sender_socket
            self._stop_locked(session)
            return self._session_summary(session), socket

    async def stop_session_as_sender(self, session_id: str, authorization: str | None) -> tuple[dict, WebSocket | None]:
        supplied = _bearer(authorization)
        if not supplied:
            raise HTTPException(401, "Paired sender authentication required")
        async with self._lock:
            session = self._sessions.get(session_id)
            if session is None:
                raise HTTPException(404, "Share session not found")
            now = time.time()
            self._clean_session(session, now)
            pairing = self._pairings.get(session.pairing_id)
            if pairing:
                self._clean_pairing(pairing, now)
            if (pairing is None or pairing.state != "paired" or not pairing.sender_token_hash
                    or pairing.sender_token_expires_at is None
                    or pairing.sender_token_expires_at <= now
                    or not secrets.compare_digest(pairing.sender_token_hash, _digest(supplied))):
                raise HTTPException(401, "Paired sender authentication required")
            socket = session.sender_socket
            self._stop_locked(session)
            return self._session_summary(session), socket

    @staticmethod
    def _stop_locked(session: ShareSession) -> None:
        session.state = "stopped"
        session.last_frame = None
        session.last_frame_at = None
        session.last_frame_mono = None
        session.sender_socket = None
        session.stream_started_mono = None
        session.stream_started_at = None
        session.last_error = None

    async def revoke_pairing(self, pairing_id: str) -> tuple[dict, WebSocket | None]:
        async with self._lock:
            pairing = self._pairings.get(pairing_id)
            if pairing is None:
                raise HTTPException(404, "Paired sender not found")
            pairing.state = "revoked"
            pairing.code_hash = ""
            pairing.sender_token_hash = None
            pairing.sender_token_expires_at = None
            socket = None
            for session in self._sessions.values():
                if session.pairing_id == pairing_id and session.state in {"awaiting_receiver_approval", "approved", "active"}:
                    socket = socket or session.sender_socket
                    self._stop_locked(session)
            return {"pairing_id": pairing.id, "state": "revoked"}, socket


async def close_socket(socket: WebSocket | None) -> None:
    if socket is not None:
        try:
            await socket.close(code=1000, reason="Screen sharing stopped by the receiver")
        except Exception:
            pass


async def authenticate_stream(ws: WebSocket, registry: ScreenShareRegistry, session_id: str) -> tuple[ShareSession, Pairing] | None:
    if ws.headers.get("origin"):
        await ws.close(code=1008, reason="Browser-origin screen sharing is not enabled")
        return None
    try:
        return await registry.sender_for_session(session_id, ws.headers.get("authorization"))
    except HTTPException as exc:
        await ws.close(code=1008, reason=exc.detail)
        return None


async def run_sender_stream(ws: WebSocket, registry: ScreenShareRegistry, session: ShareSession, pairing: Pairing) -> None:
    await ws.accept()
    try:
        hello_text = await asyncio.wait_for(ws.receive_text(), timeout=8)
        if len(hello_text) > 1024:
            await ws.close(code=1008, reason="Start message is too large")
            return
        try:
            hello = json.loads(hello_text)
        except (ValueError, RecursionError):
            await ws.close(code=1008, reason="Invalid start message")
            return
        if not isinstance(hello, dict) or set(hello) != {
            "type", "media_projection_consent", "foreground_service", "width", "height", "fps"
        } or hello.get("type") != "start" or hello.get("media_projection_consent") is not True or hello.get("foreground_service") is not True:
            await ws.close(code=1008, reason="Start only after Android MediaProjection consent and foreground service")
            return
        width, height, fps = hello.get("width"), hello.get("height"), hello.get("fps")
        if (type(width) is not int or type(height) is not int or type(fps) is not int
                or not 1 <= width <= 4096 or not 1 <= height <= 4096
                or width * height > 8_294_400 or not 1 <= fps <= MAX_FRAME_FPS):
            await ws.close(code=1008, reason="Unsupported stream dimensions or frame rate")
            return
        if not await registry.start_stream(session.id, pairing.id, ws):
            await ws.close(code=1008, reason="Session stopped or already streaming")
            return
        await ws.send_json({"type": "ready", "session_id": session.id, "max_fps": MAX_FRAME_FPS, "max_frame_bytes": MAX_FRAME_BYTES, "max_duration_seconds": MAX_STREAM_SECONDS})
        deadline = time.monotonic() + MAX_STREAM_SECONDS
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                await ws.close(code=1000, reason="Screen-share duration limit reached")
                break
            try:
                event = await asyncio.wait_for(ws.receive(), timeout=min(FRAME_STALE_SECONDS, remaining))
            except asyncio.TimeoutError:
                await ws.close(code=1000, reason="No screen-share frames received")
                break
            if event.get("type") == "websocket.disconnect":
                break
            frame = event.get("bytes")
            if frame is None:
                await ws.close(code=1003, reason="Only JPEG binary frames are accepted after start")
                break
            seq = await registry.publish_frame(session.id, ws, frame)
            if seq == -1:
                await ws.close(code=1008, reason="Frame rate exceeds the session limit")
                break
            if seq is None:
                await ws.close(code=1008, reason="Invalid or oversized JPEG frame")
                break
    except asyncio.TimeoutError:
        try:
            await ws.close(code=1008, reason="Timed out waiting for explicit stream start")
        except Exception:
            pass
    except Exception:
        # Do not log frame contents, pairing codes, tokens, or network payloads.
        try:
            await ws.close(code=1011, reason="Screen-share stream ended")
        except Exception:
            pass
    finally:
        async with registry._lock:
            current = registry._sessions.get(session.id)
            if current is not None and current.sender_socket is ws:
                registry._stop_locked(current)


__all__ = [
    "ScreenShareRegistry", "authenticate_stream", "close_socket", "run_sender_stream",
    "PAIRING_TTL_SECONDS", "SENDER_TOKEN_TTL_SECONDS", "MAX_FRAME_BYTES", "MAX_FRAME_FPS",
    "PairingRedeemRequest", "CreateShareSessionRequest",
    "SESSION_APPROVAL_TTL_SECONDS", "MAX_STREAM_SECONDS",
]
