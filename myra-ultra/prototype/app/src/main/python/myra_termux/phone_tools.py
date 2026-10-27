# -*- coding: utf-8 -*-
"""
Phone automation tools (Termux / Android): apps, YouTube, Spotify, WhatsApp, maps, alarm/timer, camera, Wi-Fi, contacts...

Do tarah ke kaam:
  * Termux:API commands (termux-*)   — `pkg install termux-api` + Termux:API app
  * Android intents (`am start`)     — Termux mein bina kisi extra app ke chalta hai

Jo kaam Android bina root/ADB ke allow nahi karta (dusre app ke andar tap karna, Spotify mein gaana auto-play) usko
sach batate hain — jhooti "done" nahi.
"""
import json
import re
import shutil
import subprocess
import urllib.parse

from . import tools as T

# naam -> package (sabse zyada use hone wale); baaki ke liye `pm list packages` se dhoondha jaata hai
PACKAGES = {
    "whatsapp": "com.whatsapp", "whatsapp business": "com.whatsapp.w4b", "instagram": "com.instagram.android",
    "facebook": "com.facebook.katana", "messenger": "com.facebook.orca", "youtube": "com.google.android.youtube",
    "youtube music": "com.google.android.apps.youtube.music", "spotify": "com.spotify.music", "gmail": "com.google.android.gm",
    "chrome": "com.android.chrome", "maps": "com.google.android.apps.maps", "google maps": "com.google.android.apps.maps",
    "camera": "com.android.camera", "photos": "com.google.android.apps.photos", "gallery": "com.google.android.apps.photos",
    "play store": "com.android.vending", "playstore": "com.android.vending", "settings": "com.android.settings",
    "phone": "com.google.android.dialer", "dialer": "com.google.android.dialer", "contacts": "com.google.android.contacts",
    "messages": "com.google.android.apps.messaging", "clock": "com.google.android.deskclock", "calculator": "com.google.android.calculator",
    "calendar": "com.google.android.calendar", "drive": "com.google.android.apps.docs", "telegram": "org.telegram.messenger",
    "snapchat": "com.snapchat.android", "twitter": "com.twitter.android", "x": "com.twitter.android", "linkedin": "com.linkedin.android",
    "netflix": "com.netflix.mediaclient", "amazon": "in.amazon.mShop.android.shopping", "flipkart": "com.flipkart.android",
    "paytm": "net.one97.paytm", "phonepe": "com.phonepe.app", "google pay": "com.google.android.apps.nbu.paisa.user",
    "gpay": "com.google.android.apps.nbu.paisa.user", "zoom": "us.zoom.videomeet", "meet": "com.google.android.apps.tachyon",
    "termux": "com.termux", "files": "com.google.android.apps.nbu.files", "chatgpt": "com.openai.chatgpt", "gemini": "com.google.android.apps.bard",
    "swiggy": "in.swiggy.android", "zomato": "com.application.zomato", "ola": "com.olacabs.customer", "uber": "com.ubercab",
}

_NUM = re.compile(r"^\+?[0-9][0-9 \-()]{4,18}$")


def _am(*args, timeout=15):
    return T._run(["am", "start", *args], timeout=timeout)


def _am_ok(out, err):
    blob = (out or "") + chr(10) + (err or "")
    bad = ("Exception", "Error:", "Permission Denial", "not found", "Unable to", "Aborted", "Exec format")
    return not err and not any(b in blob for b in bad)


def chrome_intent(data=None, action=None, category=None, package=None, extras=None):
    """Chrome ka `intent:` link — ek tap par Android app/action kholta hai (Termux ki background pabandi ko bypass karta hai)."""
    from urllib.parse import quote
    opts = []
    head = "intent:"
    if data:
        if "://" in data:
            scheme, rest = data.split("://", 1)
            head = "intent://" + rest
        else:
            scheme, rest = data.split(":", 1)
            head = "intent:" + rest
        opts.append("scheme=" + scheme)
    if package:
        opts.append("package=" + package)
    if action:
        opts.append("action=" + action)
    if category:
        opts.append("category=" + category)
    for k, (t, v) in (extras or {}).items():
        opts.append(f"{t}.{k}=" + (quote(str(v), safe="") if t == "S" else str(v).lower() if t == "B" else str(v)))
    return head + "#Intent;" + ";".join(opts) + ";end"


def _go(label, am_args, link):
    """Pehle `am start` (seedha). Android ne roka to screen par 'Kholo' button (user ke tap se Chrome kholega)."""
    out, err = _am(*am_args)
    if _am_ok(out, err):
        return None
    low = ((out or "") + " " + (err or "")).lower()
    if "unable to resolve intent" in low or "no activity found" in low or "activity class" in low and "does not exist" in low:
        return f"❌ '{label}' ke liye phone par koi app nahi mila (app installed nahi hai?)."
    fn = getattr(T, "LAUNCH", None)
    if fn:
        fn(label, link)
        return (f"⚠️ ABHI KAAM NAHI HUA: Android ne Termux ko background se app kholne nahi diya. Maine screen par '{label}' ka button dikha diya hai. "
                f"User se bolo ki wo button ek baar tap kare — tap ke baad hi kaam hoga. 'ho gaya / set kar diya' mat bolo. "
                f"(Hamesha ke liye: Settings → Apps → Termux → 'Display over other apps' ON.)")
    return "❌ Android ne background se app kholne nahi diya. Settings → Apps → Termux → 'Display over other apps' ON karo. (" + ((err or out or "")[:80]) + ")"


def _digits(n):
    return re.sub(r"[^\d+]", "", n or "")


def _installed_packages():
    out, err = T._run(["pm", "list", "packages", "-3"], timeout=20)
    if err or not out:
        return []
    return [l.split(":", 1)[1].strip() for l in out.splitlines() if ":" in l]


def _resolve_package(name):
    n = (name or "").strip().lower()
    if re.match(r"^[a-z0-9_]+(\.[a-z0-9_]+)+$", n):
        return n
    if n in PACKAGES:
        return PACKAGES[n]
    key = re.sub(r"[^a-z0-9]", "", n)
    for k, v in PACKAGES.items():
        if re.sub(r"[^a-z0-9]", "", k) == key:
            return v
    pk = _installed_packages()
    hits = [p for p in pk if key and key in re.sub(r"[^a-z0-9]", "", p.lower())]
    hits.sort(key=len)
    return hits[0] if hits else None


def open_app(package: str):
    """App ka naam ('whatsapp', 'spotify', 'instagram'...) ya package naam — dono chalte hain."""
    pkg = _resolve_package(package)
    if not pkg:
        return f"❌ '{package}' naam ka koi app nahi mila. Package naam do (jaise com.whatsapp) ya app install karo."
    link = chrome_intent(action="android.intent.action.MAIN", category="android.intent.category.LAUNCHER", package=pkg)
    r = _go(f"{package} kholo", ["-a", "android.intent.action.MAIN", "-c", "android.intent.category.LAUNCHER", "-p", pkg], link)
    return r or f"✅ App khola: {package} ({pkg})"


def play_on_youtube(query: str):
    url = "https://www.youtube.com/results?search_query=" + urllib.parse.quote(query or "")
    link = chrome_intent(data=url, package="com.google.android.youtube")
    r = _go(f"YouTube par '{query}' dekho", ["-a", "android.intent.action.VIEW", "-d", url, "-p", "com.google.android.youtube"], link)
    return r or f"✅ YouTube par '{query}' ka search khol diya (video par ek tap karke play karo)."


def play_on_spotify(query: str):
    uri = "spotify:search:" + urllib.parse.quote(query or "")
    r = _go(f"Spotify par '{query}' suno", ["-a", "android.intent.action.VIEW", "-d", uri], uri)
    return r or (f"✅ Spotify mein '{query}' search khol diya. Android bina root ke gaana khud play nahi karne deta — result par tap karo.")


def whatsapp_send_message(number: str, message: str):
    n = _digits(number).lstrip("+")
    if not (_NUM.match(number or "") or n.isdigit() and len(n) >= 8):
        c = _find_contact(number)
        if not c:
            return f"❌ '{number}' ka number nahi mila. Poora number (country code ke saath) do."
        n = _digits(c[1]).lstrip("+")
    if not T.CONFIRM or not T.CONFIRM(f"WhatsApp chat kholun? → {n}: {message[:80]}"):
        return "❌ User ne permission nahi di"
    url = f"https://wa.me/{n}?text={urllib.parse.quote(message or '')}"
    r = _go(f"WhatsApp: {n}", ["-a", "android.intent.action.VIEW", "-d", url], url)
    return r or "✅ WhatsApp chat message ke saath khul gaya — bas Send dabao (Android dusre app mein khud tap nahi karne deta)."


def navigate_to(place: str):
    uri = "google.navigation:q=" + urllib.parse.quote(place or "")
    r = _go(f"Maps: {place}", ["-a", "android.intent.action.VIEW", "-d", uri], uri)
    return r or f"✅ Maps mein '{place}' khol diya."


def set_alarm(hour: int, minute: int = 0, label: str = "MYRA"):
    h, m = int(hour) % 24, int(minute) % 60
    link = chrome_intent(action="android.intent.action.SET_ALARM", extras={
        "android.intent.extra.alarm.HOUR": ("i", h), "android.intent.extra.alarm.MINUTES": ("i", m),
        "android.intent.extra.alarm.MESSAGE": ("S", label or "MYRA"), "android.intent.extra.alarm.SKIP_UI": ("B", True)})
    r = _go(f"Alarm {h:02d}:{m:02d} set karo", ["-a", "android.intent.action.SET_ALARM", "--ei", "android.intent.extra.alarm.HOUR", str(h),
            "--ei", "android.intent.extra.alarm.MINUTES", str(m), "--es", "android.intent.extra.alarm.MESSAGE", label or "MYRA",
            "--ez", "android.intent.extra.alarm.SKIP_UI", "true"], link)
    return r or f"✅ Alarm set: {h:02d}:{m:02d} ({label})"


def set_timer(seconds: int, label: str = "MYRA"):
    sec = max(1, int(seconds))
    link = chrome_intent(action="android.intent.action.SET_TIMER", extras={
        "android.intent.extra.alarm.LENGTH": ("i", sec), "android.intent.extra.alarm.MESSAGE": ("S", label or "MYRA"),
        "android.intent.extra.alarm.SKIP_UI": ("B", True)})
    r = _go(f"Timer {sec} second", ["-a", "android.intent.action.SET_TIMER", "--ei", "android.intent.extra.alarm.LENGTH", str(sec),
            "--es", "android.intent.extra.alarm.MESSAGE", label or "MYRA", "--ez", "android.intent.extra.alarm.SKIP_UI", "true"], link)
    return r or f"✅ Timer set: {sec} second"


def dial_number(number: str):
    """Dialer kholo (call nahi lagata) — number bhar ke."""
    n = _digits(number)
    if not _NUM.match(number or ""):
        c = _find_contact(number)
        if not c:
            return f"❌ '{number}' ka number nahi mila."
        n = _digits(c[1])
    r = _go(f"Dialer: {n}", ["-a", "android.intent.action.DIAL", "-d", "tel:" + n], "tel:" + n)
    return r or f"✅ Dialer khol diya: {n}"


def take_photo(camera: int = 0):
    import os, time
    d = os.path.expanduser("~/storage/dcim") if os.path.isdir(os.path.expanduser("~/storage/dcim")) else os.path.expanduser("~")
    path = os.path.join(d, f"myra_{int(time.time())}.jpg")
    out, err = T._run(["termux-camera-photo", "-c", str(int(camera)), path], timeout=30)
    return f"❌ {err}" if err else f"✅ Photo li: {path}"


def wifi_status():
    out, err = T._run(["termux-wifi-connectioninfo"])
    return f"❌ {err}" if err else (out or "no data")


def wifi_set(on: bool = True):
    """Android 10+ par koi app Wi-Fi on/off nahi kar sakta — tab Wi-Fi panel kholte hain (ek tap)."""
    sdk, _ = T._run(["getprop", "ro.build.version.sdk"], timeout=5)
    try:
        modern = int((sdk or "0").strip()) >= 29
    except ValueError:
        modern = False
    if not modern:
        out, err = T._run(["termux-wifi-enable", "true" if on else "false"])
        return f"❌ {err}" if err else f"✅ Wi-Fi {'on' if on else 'off'}"
    link = chrome_intent(action="android.settings.panel.action.INTERNET_CONNECTIVITY")
    r = _go("Wi-Fi panel kholo", ["-a", "android.settings.panel.action.INTERNET_CONNECTIVITY"], link)
    return ("⚠️ Android 10+ par koi app Wi-Fi seedha on/off nahi kar sakta (ye Android ka rule hai). " +
            (r or "Maine Wi-Fi ka panel khol diya hai — usme switch ek tap se on/off karo."))


def _contacts():
    out, err = T._run(["termux-contact-list"], timeout=30)
    if err or not out:
        return []
    try:
        return [(c.get("name", ""), c.get("number", "")) for c in json.loads(out) if c.get("number")]
    except Exception:
        return []


def _find_contact(name):
    q = re.sub(r"[^a-z0-9 ]", "", (name or "").lower()).strip()
    if not q:
        return None
    best = None
    for n, num in _contacts():
        nn = re.sub(r"[^a-z0-9 ]", "", n.lower())
        if nn == q:
            return (n, num)
        if q in nn and (best is None or len(nn) < len(best[0])):
            best = (n, num)
    return best


def find_contact(name: str):
    c = _find_contact(name)
    return f"📇 {c[0]}: {c[1]}" if c else f"❌ '{name}' contacts mein nahi mila (Termux:API ko Contacts permission do)."


def share_text(text: str):
    out, err = T._run(["termux-share", "-a", "send", "-c", "text/plain"], stdin=text)
    return f"❌ {err}" if err else "✅ Share menu khol diya"


def download_file(url: str):
    if not re.match(r"^https?://", url or ""):
        return "❌ Sahi URL do"
    out, err = T._run(["termux-download", "-t", "MYRA download", url], timeout=30)
    return f"❌ {err}" if err else f"✅ Download shuru: {url}"


def media_player(action: str = "info", file: str = ""):
    a = (action or "info").lower()
    cmd = {"play": ["play", file] if file else ["play"], "pause": ["pause"], "stop": ["stop"], "info": ["info"]}.get(a)
    if not cmd:
        return "❌ action: play (file ke saath), pause, stop, info"
    out, err = T._run(["termux-media-player", *cmd])
    return f"❌ {err}" if err else (out or f"✅ {a}")


def _p(props, req=()):
    return {"type": "object", "properties": {k: {"type": v} for k, v in props.items()}, "required": list(req)}


DECLARATIONS = [
    {"name": "play_on_youtube", "description": "YouTube app mein video/gaana search karo ('youtube par ... chalao')", "parameters": _p({"query": "string"}, ["query"])},
    {"name": "play_on_spotify", "description": "Spotify app mein gaana/artist search karo (Spotify ka naam aaye)", "parameters": _p({"query": "string"}, ["query"])},
    {"name": "whatsapp_send_message", "description": "WhatsApp chat message ke saath kholo. number = phone number (country code ke saath) ya contact naam", "parameters": _p({"number": "string", "message": "string"}, ["number", "message"])},
    {"name": "navigate_to", "description": "Google Maps mein jagah ka rasta kholo", "parameters": _p({"place": "string"}, ["place"])},
    {"name": "set_alarm", "description": "Alarm set karo (24 ghante ka hour, minute)", "parameters": _p({"hour": "integer", "minute": "integer", "label": "string"}, ["hour"])},
    {"name": "set_timer", "description": "Timer set karo (seconds mein)", "parameters": _p({"seconds": "integer", "label": "string"}, ["seconds"])},
    {"name": "dial_number", "description": "Dialer kholo number bhar ke (call nahi lagata). number ya contact naam", "parameters": _p({"number": "string"}, ["number"])},
    {"name": "take_photo", "description": "Camera se photo lo (camera 0 = peeche, 1 = front)", "parameters": _p({"camera": "integer"})},
    {"name": "wifi_status", "description": "Wi-Fi ka haal (connected network, signal)", "parameters": _p({})},
    {"name": "wifi_set", "description": "Wi-Fi on/off (Android 10+ par block ho sakta hai)", "parameters": _p({"on": "boolean"}, ["on"])},
    {"name": "find_contact", "description": "Contacts mein naam se number dhoondho", "parameters": _p({"name": "string"}, ["name"])},
    {"name": "share_text", "description": "Text ko share menu se kisi app mein bhejo", "parameters": _p({"text": "string"}, ["text"])},
    {"name": "download_file", "description": "URL se file download karo", "parameters": _p({"url": "string"}, ["url"])},
    {"name": "media_player", "description": "Termux media player: play (file path), pause, stop, info", "parameters": _p({"action": "string", "file": "string"}, ["action"])},
]

FUNCS = {f.__name__: f for f in (open_app, play_on_youtube, play_on_spotify, whatsapp_send_message, navigate_to, set_alarm, set_timer,
                                 dial_number, take_photo, wifi_status, wifi_set, find_contact, share_text, download_file, media_player)}


def register(tools):
    """Termux backend par naye tools + behtar open_app jodo."""
    tools.REGISTRY.update(FUNCS)
    names = {d["name"] for d in DECLARATIONS} | {"open_app"}
    tools.DECLARATIONS[:] = [d for d in tools.DECLARATIONS if d["name"] not in names] + [
        {"name": "open_app", "description": "Phone ka koi bhi app kholo — naam se ('whatsapp', 'instagram', 'spotify', 'camera', 'settings'...) ya package naam se",
         "parameters": _p({"package": "string"}, ["package"])}] + DECLARATIONS
    return tools
