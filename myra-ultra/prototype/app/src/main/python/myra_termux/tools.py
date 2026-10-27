# -*- coding: utf-8 -*-
"""Phone ke kaam — Termux:API ke zariye. SMS/call se pehle user ki confirmation zaroori."""
import json
import os
import re
import shutil
import subprocess
import sys

from . import config, lang

CONFIRM = None
LAUNCH = None        # web.py yahan set karta hai: LAUNCH(label, url) -> screen par "Kholo" button
LAUNCH = None        # web.py yahan set karta hai: LAUNCH(label, url) -> screen par "Kholo" button        # cli.py yahan ek function set karta hai: confirm(text) -> bool


def _run(cmd, timeout=20, stdin=None):
    exe = cmd[0]
    if not shutil.which(exe):
        return None, (f"`{exe}` nahi mila. Termux mein `pkg install termux-api` chalao aur Play Store/F-Droid se "
                      f"'Termux:API' app install karo.")
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, input=stdin)
        return (p.stdout or "").strip(), (p.stderr or "").strip() if p.returncode else ""
    except subprocess.TimeoutExpired:
        return None, "Timeout — Termux:API app permission/chalu hai ya nahi dekho."
    except Exception as e:
        return None, str(e)


def _ok(out, err, done):
    return f"❌ {err}" if err else (f"✅ {done}" + (f"\n{out}" if out else ""))


_NUM = re.compile(r"^\+?[0-9][0-9 \-()]{2,18}$")


def battery_status():
    out, err = _run(["termux-battery-status"])
    return f"❌ {err}" if err else (out or "no data")


def torch(on: bool = True):
    return _ok(*_run(["termux-torch", "on" if on else "off"]), f"Torch {'on' if on else 'off'}")


def vibrate(ms: int = 300):
    return _ok(*_run(["termux-vibrate", "-d", str(int(ms))]), "Vibrate")


def toast(text: str):
    return _ok(*_run(["termux-toast", text]), "Toast dikha diya")


def notify(title: str, text: str = ""):
    return _ok(*_run(["termux-notification", "-t", title, "-c", text]), "Notification bhej di")


def open_url(url: str):
    if not re.match(r"^(https?://|tel:|geo:|mailto:)", url):
        url = "https://" + url
    return _ok(*_run(["termux-open-url", url]), f"Khol diya: {url}")


def open_app(package: str):
    """package = Android package naam (jaise com.whatsapp, com.spotify.music, com.google.android.youtube)."""
    if not re.match(r"^[A-Za-z0-9_.]+$", package):
        return "❌ Galat package naam"
    return _ok(*_run(["monkey", "-p", package, "-c", "android.intent.category.LAUNCHER", "1"]), f"App khola: {package}")


def set_volume(stream: str = "music", level: int = 7):
    return _ok(*_run(["termux-volume", stream, str(int(level))]), f"Volume ({stream}) = {level}")


def set_brightness(level: int = 128):
    return _ok(*_run(["termux-brightness", str(max(0, min(255, int(level))))]), f"Brightness = {level}/255")


def clipboard_get():
    out, err = _run(["termux-clipboard-get"])
    return f"❌ {err}" if err else (out or "(clipboard khali)")


def clipboard_set(text: str):
    return _ok(*_run(["termux-clipboard-set"], stdin=text), "Clipboard mein copy kiya")


def get_location():
    out, err = _run(["termux-location", "-p", "network"], timeout=40)
    return f"❌ {err}" if err else (out or "location nahi mili")


def _resolve_number(number):
    """Number ya contact naam -> number (naam ho to Termux contacts se)."""
    if _NUM.match(number or ""):
        return number
    try:
        from . import phone_tools
        c = phone_tools._find_contact(number)
        return c[1] if c else None
    except Exception:
        return None


def send_sms(number: str, message: str):
    number = _resolve_number(number)
    if not number:
        return "❌ Number galat hai ya contact nahi mila"
    if not (CONFIRM and CONFIRM(f"SMS bhejun? → {number}: {message[:80]}")):
        return "❌ User ne SMS bhejne ki permission nahi di"
    return _ok(*_run(["termux-sms-send", "-n", number, message]), f"SMS bhej diya ({number})")


def make_call(number: str):
    number = _resolve_number(number)
    if not number:
        return "❌ Number galat hai ya contact nahi mila"
    if not (CONFIRM and CONFIRM(f"Call karun? → {number}")):
        return "❌ User ne call ki permission nahi di"
    return _ok(*_run(["termux-telephony-call", number]), f"Call laga rahi hoon ({number})")


def set_user_name(name: str):
    n = re.sub(r"\s+", " ", re.sub(r"[\x00-\x1f\x7f]", "", name or "")).strip()[:30]
    if not n:
        return "❌ Naam khali hai"
    config.set_("user_name", n)
    return f"✅ Naam save ho gaya: {n}"


def set_language(language: str):
    k = (language or "").strip().lower()
    if k in ("", "auto", "default", "reset"):
        config.set_("language", "auto")
        return "✅ Language Auto/Hinglish. Pehle jaise Hinglish mein bolo."
    it = lang.find(language)
    if not it:
        return "❌ Ye language nahi mili. User se poora naam pucho."
    config.set_("language", it[0])
    return f"✅ Language set: {it[1]} ({it[2]}). Ab se sirf {it[1]} mein bolo, is jawab se hi."


def _p(props, req=()):
    return {"type": "object", "properties": {k: {"type": v} for k, v in props.items()}, "required": list(req)}


DECLARATIONS = [
    {"name": "battery_status", "description": "Phone ki battery % aur charging status", "parameters": _p({})},
    {"name": "torch", "description": "Torch/flashlight on ya off", "parameters": _p({"on": "boolean"}, ["on"])},
    {"name": "vibrate", "description": "Phone vibrate karo", "parameters": _p({"ms": "integer"})},
    {"name": "toast", "description": "Screen par chhota message dikhao", "parameters": _p({"text": "string"}, ["text"])},
    {"name": "notify", "description": "Notification bhejo", "parameters": _p({"title": "string", "text": "string"}, ["title"])},
    {"name": "open_url", "description": "Browser mein URL kholo (ya tel:/geo:/mailto:)", "parameters": _p({"url": "string"}, ["url"])},
    {"name": "open_app", "description": "Phone ka app kholo — Android package naam se (com.whatsapp, com.spotify.music, com.google.android.youtube, com.instagram.android, com.android.chrome)", "parameters": _p({"package": "string"}, ["package"])},
    {"name": "set_volume", "description": "Volume set karo. stream: music|ring|alarm|notification|system|call, level 0-15", "parameters": _p({"stream": "string", "level": "integer"}, ["level"])},
    {"name": "set_brightness", "description": "Screen brightness 0-255", "parameters": _p({"level": "integer"}, ["level"])},
    {"name": "clipboard_get", "description": "Clipboard ka text padho", "parameters": _p({})},
    {"name": "clipboard_set", "description": "Text clipboard mein copy karo", "parameters": _p({"text": "string"}, ["text"])},
    {"name": "get_location", "description": "Phone ki current location (lat/long)", "parameters": _p({})},
    {"name": "send_sms", "description": "SMS bhejo (user se confirmation li jayegi)", "parameters": _p({"number": "string", "message": "string"}, ["number", "message"])},
    {"name": "make_call", "description": "Phone call lagao (user se confirmation li jayegi)", "parameters": _p({"number": "string"}, ["number"])},
    {"name": "set_user_name", "description": "User ka naam save karo jab wo bataye ('mera naam Rahul hai')", "parameters": _p({"name": "string"}, ["name"])},
    {"name": "set_language", "description": "User ki language badlo (duniya ki koi bhi; 'speak Spanish', 'tamil me bolo'); 'auto' = Hinglish", "parameters": _p({"language": "string"}, ["language"])},
]

REGISTRY = {f.__name__: f for f in (battery_status, torch, vibrate, toast, notify, open_url, open_app, set_volume, set_brightness,
                                    clipboard_get, clipboard_set, get_location, send_sms, make_call, set_user_name, set_language)}


def dispatch(name, args):
    fn = REGISTRY.get(name)
    if not fn:
        return f"❌ Tool '{name}' nahi hai"
    try:
        return str(fn(**(args or {})))
    except TypeError as e:
        return f"❌ Galat arguments: {e}"
    except Exception as e:
        return f"❌ {type(e).__name__}: {e}"


def tts(text: str, code: str = ""):
    """Bolkar sunao (Android TTS). Language code mile to usi mein."""
    cmd = ["termux-tts-speak"]
    if code and code not in ("auto", "hi-Latn"):
        cmd += ["-l", code.split("-")[0]]
    _run(cmd + [text[:3000]], timeout=120)


def stt():
    """Mic se suno (Android speech recognizer). Text return karta hai."""
    out, err = _run(["termux-speech-to-text"], timeout=60)
    return out or ""


# ── Backend: Termux (Android) ya Linux ───────────────────────────
def _detect():
    b = (os.environ.get("MYRA_BACKEND") or "").lower()
    if b in ("termux", "linux", "android"):
        return b
    if "com.termux" in os.environ.get("PREFIX", "") or os.path.isdir("/data/data/com.termux"):
        return "termux"
    return "linux" if sys.platform.startswith("linux") else "termux"


BACKEND = _detect()
STT_OK = BACKEND == "termux"
_termux_tts = tts

if BACKEND == "linux":
    from . import linux_tools as _lx
    for _n in ("torch", "vibrate", "get_location", "send_sms", "make_call"):     # Linux par nahi
        REGISTRY.pop(_n, None)
    REGISTRY.update(_lx.FUNCS)
    DECLARATIONS = [d for d in DECLARATIONS if d["name"] in REGISTRY]
    for _d in DECLARATIONS:
        if _d["name"] == "open_app":
            _d["description"] = "Computer ka app kholo — uska command naam (firefox, spotify, code, gedit, nautilus, vlc)"
    tts = _lx.tts

    def stt():
        return ""


if BACKEND in ("termux", "android"):
    from . import phone_tools as _phone
    _phone.register(sys.modules[__name__])
