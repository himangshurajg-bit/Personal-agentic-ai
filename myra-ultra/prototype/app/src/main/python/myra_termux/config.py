# -*- coding: utf-8 -*-
"""Settings ~/.myra_termux/config.json mein (API key, naam, language, model). Key kabhi print nahi hoti."""
import json
import os
from pathlib import Path

DIR = Path(os.environ.get("MYRA_TERMUX_HOME") or (Path.home() / ".myra_termux"))
FILE = DIR / "config.json"
DEFAULT_MODEL = "gemini-2.5-flash"


def load() -> dict:
    try:
        return json.loads(FILE.read_text(encoding="utf-8"))
    except Exception:
        return {}


def save(cfg: dict) -> None:
    DIR.mkdir(parents=True, exist_ok=True)
    FILE.write_text(json.dumps(cfg, indent=2, ensure_ascii=False), encoding="utf-8")
    try:
        os.chmod(FILE, 0o600)                       # sirf user padh sake (API key hai)
    except Exception:
        pass


def get(key, default=None):
    return load().get(key, default)


def set_(key, value) -> None:
    cfg = load()
    cfg[key] = value
    save(cfg)


def api_key() -> str:
    return (os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY") or load().get("api_key") or "").strip()


def model() -> str:
    return os.environ.get("MYRA_MODEL") or load().get("model") or DEFAULT_MODEL
