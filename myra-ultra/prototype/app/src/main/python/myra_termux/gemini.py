# -*- coding: utf-8 -*-
"""Gemini REST client (sirf standard library) — function calling ke saath."""
import json
import urllib.error
import urllib.request

from . import config

BASE = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"


class GeminiError(Exception):
    pass


def generate(contents, system, tools=None, timeout=60):
    key = config.api_key()
    if not key:
        raise GeminiError("API key set nahi hai. `myra-termux --setup` chalao.")
    body = {"contents": contents, "systemInstruction": {"parts": [{"text": system}]},
            "generationConfig": {"temperature": 0.7}}
    if tools:
        body["tools"] = [{"functionDeclarations": tools}]
    req = urllib.request.Request(BASE.format(model=config.model()), data=json.dumps(body).encode("utf-8"),
                                 headers={"Content-Type": "application/json", "x-goog-api-key": key})
    import time
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return json.loads(r.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            if e.code in (429, 500, 503) and attempt < 2:
                time.sleep(2 + attempt * 3)                  # server busy / free-tier limit — thoda ruk ke dobara
                continue
            return _fail_http(e)
        except Exception as e:
            if attempt < 2:
                time.sleep(1.5)
                continue
            raise GeminiError(f"Network error: {e}")


def _fail_http(e):
    try:
        msg = json.loads(e.read().decode("utf-8"))["error"]["message"]
    except Exception:
        msg = str(e)
    raise GeminiError(f"Gemini error {e.code}: {msg}")


def parts_of(resp):
    try:
        return resp["candidates"][0]["content"]["parts"]
    except Exception:
        reason = (resp.get("promptFeedback") or {}).get("blockReason") or "empty response"
        raise GeminiError(f"Jawab nahi mila ({reason})")
