# -*- coding: utf-8 -*-
"""myra-termux — Termux par MYRA: chat + voice + phone control (Gemini)."""
import argparse
import getpass
import sys

from . import __version__, config, gemini, lang, tools

_DEVICE = {"termux": "unke Android phone (Termux) par", "linux": "unke Linux computer par"}
BASE_PROMPT = (
    "Tum MYRA ho — user ki friendly, smart AI assistant jo {device} chal rahi ho. "
    "Chhote, natural jawab do (voice mein bolne layak). Device ka koi kaam ho (jo tools diye gaye hain: battery, app kholna, "
    "volume, brightness, clipboard, URL, notification{phone_extra}) to turant sahi tool call karo — bas bolo mat. "
    "Kabhi andaza mat lagao; tool na ho ya fail ho to sach batao. "
    "Default style Hinglish hai jab tak user koi aur language na chune."
)


def system_prompt():
    cfg = config.load()
    s = BASE_PROMPT.format(device=_DEVICE[tools.BACKEND], phone_extra=", torch, SMS, call, location" if tools.BACKEND == "termux" else "")
    if cfg.get("user_name"):
        s += f"\nUser ka naam {cfg['user_name']} hai — kabhi-kabhi naam se bulao."
    s += lang.prompt_block(cfg.get("language", "auto"))
    return s


def ask(history, text, on_tool=None):
    """Ek user message -> MYRA ka jawab (tool calls loop ke saath). history list mutate hoti hai."""
    history.append({"role": "user", "parts": [{"text": text}]})
    for _ in range(6):
        parts = gemini.parts_of(gemini.generate(history, system_prompt(), tools.DECLARATIONS))
        history.append({"role": "model", "parts": parts})
        calls = [p["functionCall"] for p in parts if "functionCall" in p]
        if not calls:
            return "".join(p.get("text", "") for p in parts).strip()
        results = []
        for c in calls:
            out = tools.dispatch(c.get("name"), c.get("args"))
            if on_tool:
                on_tool(c.get("name"), c.get("args"), out)
            else:
                print(f"  🔧 {c.get('name')} → {out.splitlines()[0][:90] if out else ''}")
            results.append({"functionResponse": {"name": c.get("name"), "response": {"result": out}}})
        history.append({"role": "user", "parts": results})
    return "Kaam bahut lamba ho gaya — dobara try karo."


def _confirm(msg):
    try:
        return input(f"⚠️  {msg} [y/N]: ").strip().lower() in ("y", "yes", "haan", "ha")
    except EOFError:
        return False


def setup():
    print("MYRA Termux setup (Gemini API key: https://aistudio.google.com/apikey)")
    key = getpass.getpass("API key (type karte waqt dikhegi nahi): ").strip()
    if key:
        config.set_("api_key", key)
    name = input("Aapka naam (optional): ").strip()
    if name:
        print(tools.set_user_name(name))
    print("Language: naam likho (jaise Hindi, English, Tamil, Spanish) ya Enter = Hinglish.")
    l = input("Language: ").strip()
    if l:
        print(tools.set_language(l))
    print("✓ Setup ho gaya. Ab `myra-termux` chalao.")


def make_alias():
    """`myra` likhne se phone UI khule — ~/.bashrc / ~/.zshrc mein alias."""
    from pathlib import Path
    line = "alias myra='myra-termux web'"
    done = []
    for rc in (".bashrc", ".zshrc"):
        p = Path.home() / rc
        try:
            txt = p.read_text(encoding="utf-8") if p.exists() else ""
            if line not in txt:
                p.write_text(txt + (chr(10) if txt and not txt.endswith(chr(10)) else "") + line + chr(10), encoding="utf-8")
            done.append(rc)
        except Exception as e:
            print(f"{rc}: {e}")
    print("✅ Alias bana diya (" + ", ".join(done) + "). Termux band karke dobara kholo, phir sirf ye likho:  myra")
    return 0


def list_languages():
    for c, e, n in lang.LANGUAGES:
        print(f"{c:8} {e} — {n}" if e != n else f"{c:8} {e}")


def chat(voice=False):
    tools.CONFIRM = _confirm
    if not config.api_key():
        print("API key nahi mili."); setup()
        if not config.api_key():
            return 1
    if voice and not tools.STT_OK:
        print("ℹ️  Linux par mic se sunna abhi nahi hai — text se likho, MYRA bolkar jawab degi (espeak-ng chahiye).")
    cfg = config.load()
    who = cfg.get("user_name") or ""
    print(f"MYRA Termux {__version__} — {'voice' if voice else 'chat'} mode. 'exit' ya Ctrl+C se band.")
    history = []
    try:
        greet = ask(history, "Mujhe chhota sa greeting do." + (f" Mera naam {who} hai." if who else ""))
        print(f"MYRA: {greet}")
        if voice:
            tools.tts(greet, cfg.get("language", ""))
        while True:
            if voice and tools.STT_OK:
                print("🎤 Boliye...")
                text = tools.stt()
                if not text:
                    continue
                print(f"Aap: {text}")
            else:
                text = input("Aap: ").strip()
            if not text:
                continue
            if text.lower() in ("exit", "quit", "q", "bye"):
                break
            try:
                reply = ask(history, text)
            except gemini.GeminiError as e:
                print(f"❌ {e}"); continue
            print(f"MYRA: {reply}")
            if voice:
                tools.tts(reply, config.get("language", ""))
    except (KeyboardInterrupt, EOFError):
        print()
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(prog="myra-termux", description="MYRA AI assistant for Termux (Android) and Linux")
    ap.add_argument("command", nargs="?", choices=["web", "chat", "alias", "setup"], help="web = phone UI (browser), chat = terminal chat, alias = `myra` shortcut banao")
    ap.add_argument("--port", type=int, default=8765, help="web UI ka port (default 8765)")
    ap.add_argument("--no-open", action="store_true", help="web UI browser mein khud na kholo")
    ap.add_argument("--setup", action="store_true", help="API key, naam, language set karo")
    ap.add_argument("--voice", action="store_true", help="mic se suno aur bolkar jawab do (Termux:API chahiye)")
    ap.add_argument("--language", "-l", metavar="NAME", help="language set karo (jaise Tamil, Spanish, auto)")
    ap.add_argument("--languages", action="store_true", help="saari languages dikhao")
    ap.add_argument("--name", metavar="NAAM", help="apna naam set karo")
    ap.add_argument("--ask", metavar="TEXT", help="ek sawaal puchho aur band")
    ap.add_argument("--version", action="store_true")
    for _s in (sys.stdout, sys.stderr):                 # Windows cp1252 console par bhi Hindi/Tamil crash na kare
        try:
            _s.reconfigure(errors="replace")
        except Exception:
            pass
    a = ap.parse_args(argv)
    if a.version:
        print(__version__); return 0
    if a.languages:
        list_languages(); return 0
    if a.setup or a.command == "setup":
        setup(); return 0
    if a.command == "alias":
        return make_alias()
    if a.name:
        print(tools.set_user_name(a.name))
    if a.language:
        print(tools.set_language(a.language))
    if a.name or a.language:
        return 0
    if a.ask:
        tools.CONFIRM = _confirm
        try:
            print(ask([], a.ask))
        except gemini.GeminiError as e:
            print(f"❌ {e}"); return 1
        return 0
    if a.command == "web" or (a.command is None and not a.voice and tools.BACKEND == "termux"):
        from . import web
        if not config.api_key():
            print("Pehle API key (browser mein bhi daal sakte ho):")
        return web.serve(a.port, open_browser=not a.no_open)
    return chat(a.voice)


if __name__ == "__main__":
    sys.exit(main())
