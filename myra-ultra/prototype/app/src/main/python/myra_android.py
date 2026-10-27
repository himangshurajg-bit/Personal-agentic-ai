"""Android entry point for the embedded MYRA Termux backend."""
import os

# This build uses the existing local web UI and Python Gemini/tool pipeline. Phone
# controls remain unavailable unless implemented through Android APIs; it must not
# pretend Termux binaries are present inside this APK.
os.environ["MYRA_BACKEND"] = "android"
os.environ["MYRA_TERMUX_HOME"] = os.path.join(os.path.expanduser("~"), ".myra_termux")

from myra_termux import web, tools  # noqa: E402

# Only settings operations currently have a safe, local Android implementation.
# Advertise no Termux shell actions until a native Android bridge exists.
_ALLOWED = {"set_user_name", "set_language"}
tools.DECLARATIONS = [d for d in tools.DECLARATIONS if d["name"] in _ALLOWED]
tools.REGISTRY = {k: v for k, v in tools.REGISTRY.items() if k in _ALLOWED}


def start_server():
    return web.start_embedded(8765)


def stop_server():
    return web.stop_embedded()
