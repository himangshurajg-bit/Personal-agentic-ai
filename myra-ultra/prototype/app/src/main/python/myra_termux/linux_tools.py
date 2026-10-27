# -*- coding: utf-8 -*-
"""Linux desktop/server backend — Termux:API ki jagah normal Linux commands (notify-send, xdg-open, pactl...)."""
import glob
import os
import re
import shutil
import subprocess


def _run(cmd, timeout=20, stdin=None):
    if not shutil.which(cmd[0]):
        return None, f"`{cmd[0]}` install nahi hai (jaise: sudo apt install {_PKG.get(cmd[0], cmd[0])})"
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, input=stdin)
        return (p.stdout or "").strip(), (p.stderr or "").strip() if p.returncode else ""
    except subprocess.TimeoutExpired:
        return None, "Timeout"
    except Exception as e:
        return None, str(e)


_PKG = {"notify-send": "libnotify-bin", "xdg-open": "xdg-utils", "pactl": "pulseaudio-utils", "brightnessctl": "brightnessctl",
        "xclip": "xclip", "espeak-ng": "espeak-ng"}


def _ok(r, done):
    out, err = r
    return f"❌ {err}" if err else (f"✅ {done}" + (f"\n{out}" if out else ""))


def battery_status():
    for d in glob.glob("/sys/class/power_supply/BAT*"):
        try:
            cap = open(d + "/capacity").read().strip()
            st = open(d + "/status").read().strip()
            return f'{{"percentage": {cap}, "status": "{st}"}}'
        except Exception:
            pass
    return "❌ Battery nahi mili (desktop/server hoga)"


def toast(text: str):
    return _ok(_run(["notify-send", "MYRA", text]), "Notification dikha di")


def notify(title: str, text: str = ""):
    return _ok(_run(["notify-send", title, text]), "Notification bhej di")


def open_url(url: str):
    if not re.match(r"^(https?://|mailto:)", url):
        url = "https://" + url
    return _ok(_run(["xdg-open", url]), f"Khol diya: {url}")


def open_app(package: str):
    """Linux par app ka command naam (firefox, spotify, code, gedit, nautilus...)."""
    if not re.match(r"^[A-Za-z0-9_.\-]+$", package or ""):
        return "❌ Galat app naam"
    exe = shutil.which(package)
    if not exe:
        return f"❌ '{package}' install nahi hai ya PATH mein nahi"
    subprocess.Popen([exe], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    return f"✅ App khola: {package}"


def set_volume(stream: str = "music", level: int = 7):
    pct = max(0, min(100, round(int(level) * 100 / 15)))        # 0-15 scale -> percent
    return _ok(_run(["pactl", "set-sink-volume", "@DEFAULT_SINK@", f"{pct}%"]), f"Volume = {pct}%")


def set_brightness(level: int = 128):
    pct = max(1, min(100, round(int(level) * 100 / 255)))
    return _ok(_run(["brightnessctl", "set", f"{pct}%"]), f"Brightness = {pct}%")


def clipboard_get():
    for c in (["wl-paste"], ["xclip", "-selection", "clipboard", "-o"], ["xsel", "-b", "-o"]):
        if shutil.which(c[0]):
            out, err = _run(c)
            return f"❌ {err}" if err else (out or "(clipboard khali)")
    return "❌ clipboard tool nahi mila (sudo apt install xclip)"


def clipboard_set(text: str):
    for c in (["wl-copy"], ["xclip", "-selection", "clipboard"], ["xsel", "-b", "-i"]):
        if shutil.which(c[0]):
            return _ok(_run(c, stdin=text), "Clipboard mein copy kiya")
    return "❌ clipboard tool nahi mila (sudo apt install xclip)"


def tts(text: str, code: str = ""):
    for exe in ("espeak-ng", "spd-say", "espeak"):
        if shutil.which(exe):
            cmd = [exe] + (["-v", code.split("-")[0]] if exe != "spd-say" and code and code not in ("auto", "hi-Latn") else []) + [text[:3000]]
            _run(cmd, timeout=120)
            return


# naam -> function (sirf jo Linux par chalte hain); baaki (torch, vibrate, sms, call, location) Termux-only
FUNCS = {f.__name__: f for f in (battery_status, toast, notify, open_url, open_app, set_volume, set_brightness, clipboard_get, clipboard_set)}
