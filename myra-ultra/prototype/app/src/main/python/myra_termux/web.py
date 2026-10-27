# -*- coding: utf-8 -*-
"""
MYRA Phone UI — Termux par chhota local web server (sirf standard library).

    myra-termux web           # phir phone ke browser mein khulta hai (http://localhost:8765/?t=...)

Safety:
  * sirf 127.0.0.1 par sunta hai (network se koi nahi pahunch sakta)
  * har API call par random token (URL mein) zaroori — phone ke browser mein khuli koi dusri website
    localhost par SMS/call jaise tools nahi chala sakti
  * Host header check (DNS-rebinding se bachav)
  * SMS/call ke liye UI mein Allow/Deny card — bina permission ke nahi jaata
"""
import json
import os
import secrets
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

from . import __version__, config, gemini, lang, tools
from .ui_html import HTML


class Session:
    def __init__(self):
        self.lock = threading.Lock()
        self.cond = threading.Condition(self.lock)
        self.events = []                 # {"n": int, "type": ..., ...}
        self.history = []
        self.busy = False
        self.pending = {}                # confirm id -> {"event": Event, "ok": bool}
        self.seq = 0

    def emit(self, type_, **kw):
        with self.cond:
            self.seq += 1
            self.events.append({"n": self.seq, "type": type_, **kw})
            self.events = self.events[-300:]
            self.cond.notify_all()

    def since(self, after, wait=0.0):
        with self.cond:
            if wait and not any(e["n"] > after for e in self.events):
                self.cond.wait(wait)
            return [e for e in self.events if e["n"] > after]

    def confirm(self, text):
        cid = secrets.token_hex(4)
        ev = threading.Event()
        self.pending[cid] = {"event": ev, "ok": False}
        self.emit("confirm", id=cid, text=text)
        ev.wait(90)
        ok = self.pending.pop(cid, {}).get("ok", False)
        return ok

    def answer(self, cid, ok):
        p = self.pending.get(cid)
        if p:
            p["ok"] = bool(ok)
            p["event"].set()
            return True
        return False


SESSION = Session()
ASSETS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets")
LIVE_MODELS = ["gemini-3.1-flash-live-preview", "gemini-2.5-flash-native-audio-latest"]


def _check_key(key):
    """Key sahi hai ya nahi — models list se (muft call). (ok, message)"""
    try:
        req = urllib.request.Request("https://generativelanguage.googleapis.com/v1beta/models?pageSize=1", headers={"x-goog-api-key": key})
        with urllib.request.urlopen(req, timeout=12) as r:
            return r.status == 200, "ok"
    except urllib.error.HTTPError as e:
        try:
            return False, json.loads(e.read().decode("utf-8"))["error"]["message"][:160]
        except Exception:
            return False, f"HTTP {e.code}"
    except Exception as e:
        return None, f"Internet check nahi ho paya: {e}"                # None = pata nahi (key rakh lo)


def _run_tool(name, args):
    out = tools.dispatch(name, args)
    SESSION.emit("tool", name=name, args=args or {}, result=(out or "")[:400], ok=not str(out or "").startswith("❌"))
    return out


def _state():
    cfg = config.load()
    return {
        "version": __version__, "backend": tools.BACKEND, "model": config.model(),
        "has_key": bool(config.api_key()), "name": cfg.get("user_name", ""), "language": cfg.get("language", "auto"),
        "busy": SESSION.busy,
        "languages": [{"code": c, "name": e, "native": n} for c, e, n in lang.LANGUAGES],
    }


def _run_chat(text):
    from . import cli
    SESSION.busy = True
    try:
        def on_tool(name, args, out):
            SESSION.emit("tool", name=name, args=args or {}, result=(out or "")[:400], ok=not str(out or "").startswith("❌"))
        reply = cli.ask(SESSION.history, text, on_tool=on_tool)
        SESSION.emit("reply", text=reply, language=config.get("language", "auto"))
    except gemini.GeminiError as e:
        SESSION.emit("error", text=str(e))
    except Exception as e:                                           # server kabhi na gire
        SESSION.emit("error", text=f"{type(e).__name__}: {e}")
    finally:
        SESSION.busy = False
        SESSION.emit("done")


class Handler(BaseHTTPRequestHandler):
    server_version = "MyraPhone/" + __version__
    token = ""
    port = 0

    def log_message(self, *a):                                       # terminal saaf rakho
        pass

    # ── helpers ──
    def _host_ok(self):
        h = (self.headers.get("Host") or "").lower()
        return h in (f"localhost:{self.port}", f"127.0.0.1:{self.port}")

    def _send(self, code, body, ctype="application/json; charset=utf-8"):
        data = body if isinstance(body, bytes) else body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Content-Security-Policy", "default-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self' wss://generativelanguage.googleapis.com")
        self.end_headers()
        self.wfile.write(data)

    def _json(self, code, obj):
        self._send(code, json.dumps(obj, ensure_ascii=False))

    def _authed(self):
        return secrets.compare_digest(self.headers.get("X-Myra-Token", ""), self.token)

    def _body(self):
        try:
            n = int(self.headers.get("Content-Length") or 0)
            return json.loads(self.rfile.read(min(n, 1_000_000)).decode("utf-8") or "{}")
        except Exception:
            return {}

    # ── routes ──
    def do_GET(self):
        try:
            self._get()
        except Exception as e:
            self._json(500, {"error": f"{type(e).__name__}: {e}"})

    def do_POST(self):
        try:
            self._post()
        except Exception as e:
            self._json(500, {"error": f"{type(e).__name__}: {e}"})

    def _get(self):
        if not self._host_ok():
            return self._send(403, "forbidden", "text/plain")
        u = urlparse(self.path)
        if u.path == "/":
            if not secrets.compare_digest((parse_qs(u.query).get("t") or [""])[0], self.token):
                return self._send(403, "Token chahiye — terminal mein dikhaya gaya poora link kholo.", "text/plain; charset=utf-8")
            return self._send(200, HTML, "text/html; charset=utf-8")
        if u.path == "/a/myra.jpg":
            if not secrets.compare_digest((parse_qs(u.query).get("t") or [""])[0], self.token):
                return self._send(403, "forbidden", "text/plain")
            with open(os.path.join(ASSETS, "myra.jpg"), "rb") as f:
                return self._send(200, f.read(), "image/jpeg")
        if not self._authed():
            return self._json(401, {"error": "token"})
        if u.path == "/api/live":
            from . import cli
            return self._json(200, {"key": config.api_key(), "models": LIVE_MODELS, "voice": "Aoede", "system": cli.system_prompt(),
                                    "tools": tools.DECLARATIONS, "language": config.get("language", "auto")})
        if u.path == "/api/state":
            return self._json(200, _state())
        if u.path == "/api/events":
            q = parse_qs(u.query)
            after = int((q.get("after") or ["0"])[0])
            return self._json(200, {"events": SESSION.since(after, wait=min(float((q.get("wait") or ["0"])[0]), 20.0)), "busy": SESSION.busy})
        self._json(404, {"error": "not found"})

    def _post(self):
        if not self._host_ok():
            return self._send(403, "forbidden", "text/plain")
        if not self._authed():
            return self._json(401, {"error": "token"})
        p = urlparse(self.path).path
        b = self._body()
        if p == "/api/chat":
            text = str(b.get("text") or "").strip()[:4000]
            if not text:
                return self._json(400, {"error": "khali"})
            if SESSION.busy:
                return self._json(409, {"error": "MYRA abhi kaam kar rahi hai"})
            if not config.api_key():
                return self._json(400, {"error": "API key set nahi hai"})
            threading.Thread(target=_run_chat, args=(text,), daemon=True).start()
            return self._json(200, {"ok": True})
        if p == "/api/tool":
            name = str(b.get("name") or "")
            if name not in tools.REGISTRY:
                return self._json(200, {"result": f"❌ Tool '{name}' nahi hai"})
            return self._json(200, {"result": str(_run_tool(name, b.get("args") or {}))})
        if p == "/api/confirm":
            return self._json(200, {"ok": SESSION.answer(str(b.get("id")), b.get("ok"))})
        if p == "/api/settings":
            out = {}
            if "api_key" in b and str(b["api_key"]).strip():
                k = "".join(str(b["api_key"]).split())
                ok, msg = _check_key(k)
                if ok is False:
                    return self._json(200, {"ok": False, "error": "API key galat hai: " + msg})
                config.set_("api_key", k); out["api_key"] = True
            if "name" in b:
                out["name"] = tools.set_user_name(str(b["name"])) if str(b["name"]).strip() else (config.set_("user_name", "") or "")
            if "language" in b:
                out["language"] = tools.set_language(str(b["language"]))
            return self._json(200, {"ok": True, "result": out, "state": _state()})
        if p == "/api/reset":
            SESSION.history.clear()
            return self._json(200, {"ok": True})
        self._json(404, {"error": "not found"})


_EMBEDDED_SERVER = None
_EMBEDDED_URL = None


def start_embedded(port=8765):
    """Start the same authenticated local UI server for an embedded Android WebView."""
    global _EMBEDDED_SERVER, _EMBEDDED_URL
    if _EMBEDDED_SERVER is not None:
        return _EMBEDDED_URL
    tools.CONFIRM = SESSION.confirm
    tools.LAUNCH = lambda label, url: SESSION.emit("launch", label=label, url=url)
    token = secrets.token_urlsafe(18)
    Handler.token = token
    srv = None
    for p in range(port, port + 20):
        try:
            srv = ThreadingHTTPServer(("127.0.0.1", p), Handler)
            Handler.port = p
            break
        except OSError:
            continue
    if not srv:
        raise RuntimeError("Koi free port nahi mila")
    srv.daemon_threads = True
    _EMBEDDED_SERVER = srv
    _EMBEDDED_URL = f"http://localhost:{Handler.port}/?t={token}"
    threading.Thread(target=srv.serve_forever, name="myra-local-ui", daemon=True).start()
    return _EMBEDDED_URL


def stop_embedded():
    """Stop the in-app UI server when the Android activity closes."""
    global _EMBEDDED_SERVER, _EMBEDDED_URL
    srv = _EMBEDDED_SERVER
    _EMBEDDED_SERVER = None
    _EMBEDDED_URL = None
    if srv is not None:
        srv.shutdown()
        srv.server_close()
    return True


def serve(port=8765, open_browser=True):
    tools.CONFIRM = SESSION.confirm
    tools.LAUNCH = lambda label, url: SESSION.emit("launch", label=label, url=url)
    tools.LAUNCH = lambda label, url: SESSION.emit("launch", label=label, url=url)
    token = secrets.token_urlsafe(18)
    Handler.token = token
    srv = None
    for p in range(port, port + 20):
        try:
            srv = ThreadingHTTPServer(("127.0.0.1", p), Handler)
            Handler.port = p
            break
        except OSError:
            continue
    if not srv:
        print("❌ Koi free port nahi mila.")
        return 1
    url = f"http://localhost:{Handler.port}/?t={token}"
    print(f"MYRA Phone {__version__}  ({tools.BACKEND})")
    print(f"Browser mein kholo:\n\n  {url}\n")
    print("Band karne ke liye Ctrl+C.")
    tools._run(["termux-wake-lock"], timeout=5) if tools.BACKEND == "termux" else None     # Android server na maare
    if open_browser:
        try:
            if tools.BACKEND == "termux":
                tools._run(["termux-open-url", url], timeout=8)
            else:
                import webbrowser
                webbrowser.open(url)
        except Exception:
            pass
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print()
    finally:
        srv.server_close()
        if tools.BACKEND == "termux":
            tools._run(["termux-wake-unlock"], timeout=5)
    return 0
