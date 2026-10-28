import pytest
from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect

from app import create_app

OWNER_TOKEN = "owner-token-for-screen-share-tests-123456"


def _new_pair(client):
    pairing = client.post("/screen-share/pairings", headers={"Authorization": f"Bearer {OWNER_TOKEN}"})
    assert pairing.status_code == 200
    data = pairing.json()
    redeemed = client.post("/screen-share/pairings/redeem", json={
        "pairing_id": data["pairing_id"],
        "pairing_code": data["pairing_code"],
        "sender_label": "MYRA Android",
    })
    assert redeemed.status_code == 200
    return data, redeemed.json()


def test_pairing_is_owner_started_authenticated_and_one_use(tmp_path):
    app = create_app(tmp_path / "screen-share.sqlite", token=OWNER_TOKEN)
    with TestClient(app) as client:
        assert client.post("/screen-share/pairings").status_code == 401
        assert client.get("/screen-share/pairings").status_code == 401

        created = client.post("/screen-share/pairings", headers={"Authorization": f"Bearer {OWNER_TOKEN}"})
        assert created.status_code == 200
        pairing = created.json()
        assert len(pairing["pairing_code"]) >= 32
        assert pairing["expires_in_seconds"] == 300

        payload = {"pairing_id": pairing["pairing_id"], "pairing_code": pairing["pairing_code"], "sender_label": "MYRA Android"}
        wrong = {**payload, "pairing_code": "x" * len(pairing["pairing_code"])}
        assert client.post("/screen-share/pairings/redeem", json=wrong).status_code == 404
        redeemed = client.post("/screen-share/pairings/redeem", json=payload)
        assert redeemed.status_code == 200
        sender_token = redeemed.json()["sender_token"]
        assert len(sender_token) >= 40
        assert client.post("/screen-share/pairings/redeem", json=payload).status_code == 409

        listed = client.get("/screen-share/pairings", headers={"Authorization": f"Bearer {OWNER_TOKEN}"}).json()
        assert listed[0]["state"] == "paired"
        assert listed[0]["sender_label"] == "MYRA Android"
        assert "pairing_code" not in listed[0] and "sender_token" not in listed[0]


def test_pairing_redeem_rejects_browser_origins_and_rate_limits(tmp_path):
    app = create_app(tmp_path / "screen-share-origin.sqlite", token=OWNER_TOKEN)
    with TestClient(app) as client:
        pairing = client.post("/screen-share/pairings", headers={"Authorization": f"Bearer {OWNER_TOKEN}"}).json()
        body = {"pairing_id": pairing["pairing_id"], "pairing_code": pairing["pairing_code"], "sender_label": "MYRA"}
        assert client.post("/screen-share/pairings/redeem", json=body, headers={"Origin": "https://untrusted.example"}).status_code == 403
        assert client.post("/screen-share/pairings/redeem", json=body).status_code == 200


def test_session_requires_sender_auth_and_receiver_approval(tmp_path):
    app = create_app(tmp_path / "screen-share-approval.sqlite", token=OWNER_TOKEN)
    with TestClient(app) as client:
        pairing, sender = _new_pair(client)
        route = "/screen-share/sessions"
        request_body = {"pairing_id": pairing["pairing_id"]}
        assert client.post(route, json=request_body).status_code == 401
        assert client.post(route, json=request_body, headers={"Authorization": f"Bearer {OWNER_TOKEN}"}).status_code == 401

        auth = {"Authorization": f"Bearer {sender['sender_token']}"}
        created = client.post(route, json=request_body, headers=auth)
        assert created.status_code == 200
        session_id = created.json()["session_id"]
        assert created.json()["state"] == "awaiting_receiver_approval"
        assert client.get(f"/screen-share/sessions/{session_id}/status", headers=auth).json()["state"] == "awaiting_receiver_approval"
        assert client.get(f"/screen-share/sessions/{session_id}/frame", headers={"Authorization": f"Bearer {OWNER_TOKEN}"}).status_code == 409

        assert client.post(f"/screen-share/sessions/{session_id}/approve").status_code == 401
        approved = client.post(f"/screen-share/sessions/{session_id}/approve", headers={"Authorization": f"Bearer {OWNER_TOKEN}"})
        assert approved.status_code == 200 and approved.json()["state"] == "approved"
        assert client.get(f"/screen-share/sessions/{session_id}/status", headers=auth).json()["state"] == "approved"


def test_authenticated_stream_requires_media_projection_claim_and_exposes_only_latest_frame(tmp_path):
    app = create_app(tmp_path / "screen-share-stream.sqlite", token=OWNER_TOKEN)
    with TestClient(app) as client:
        pairing, sender = _new_pair(client)
        sender_auth = {"Authorization": f"Bearer {sender['sender_token']}"}
        session = client.post("/screen-share/sessions", json={"pairing_id": pairing["pairing_id"]}, headers=sender_auth).json()
        session_id = session["session_id"]
        client.post(f"/screen-share/sessions/{session_id}/approve", headers={"Authorization": f"Bearer {OWNER_TOKEN}"})
        websocket_url = f"/screen-share/sessions/{session_id}/stream"

        with pytest.raises(WebSocketDisconnect):
            with client.websocket_connect(websocket_url):
                pass
        with client.websocket_connect(websocket_url, headers=sender_auth) as ws:
            ws.send_json({
                "type": "start", "media_projection_consent": False,
                "foreground_service": True, "width": 1080, "height": 2400, "fps": 5,
            })
            with pytest.raises(WebSocketDisconnect):
                ws.receive_json()
        assert client.get(f"/screen-share/sessions/{session_id}/frame", headers={"Authorization": f"Bearer {OWNER_TOKEN}"}).status_code == 409

        with client.websocket_connect(websocket_url, headers=sender_auth) as ws:
            ws.send_json({
                "type": "start", "media_projection_consent": True,
                "foreground_service": True, "width": 1080, "height": 2400, "fps": 5,
            })
            assert ws.receive_json()["type"] == "ready"
            frame = b"\xff\xd8synthetic-jpeg\xff\xd9"
            ws.send_bytes(frame)
            headers = {"Authorization": f"Bearer {OWNER_TOKEN}"}
            received = client.get(f"/screen-share/sessions/{session_id}/frame", headers=headers)
            assert received.status_code == 200
            assert received.content == frame
            assert received.headers["content-type"] == "image/jpeg"
            assert received.headers["cache-control"] == "no-store"
            sequence = int(received.headers["x-frame-sequence"])
            assert sequence == 1
            assert client.get(f"/screen-share/sessions/{session_id}/frame?after_sequence={sequence}", headers=headers).status_code == 204
            assert client.get(f"/screen-share/sessions/{session_id}/frame").status_code == 401
            assert client.post(f"/screen-share/sessions/{session_id}/stop", headers=headers).json()["state"] == "stopped"
            assert client.get(f"/screen-share/sessions/{session_id}/frame", headers=headers).status_code == 409


def test_pairing_revocation_stops_pending_session_and_sender_cannot_resume(tmp_path):
    app = create_app(tmp_path / "screen-share-revoke.sqlite", token=OWNER_TOKEN)
    with TestClient(app) as client:
        pairing, sender = _new_pair(client)
        auth = {"Authorization": f"Bearer {sender['sender_token']}"}
        session = client.post("/screen-share/sessions", json={"pairing_id": pairing["pairing_id"]}, headers=auth).json()
        revoked = client.post(f"/screen-share/pairings/{pairing['pairing_id']}/revoke", headers={"Authorization": f"Bearer {OWNER_TOKEN}"})
        assert revoked.json()["state"] == "revoked"
        assert client.get(f"/screen-share/sessions/{session['session_id']}/status", headers=auth).status_code == 401
        assert client.post("/screen-share/sessions", json={"pairing_id": pairing["pairing_id"]}, headers=auth).status_code == 401
