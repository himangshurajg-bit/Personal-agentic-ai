# MYRA-derived short in-app message

MYRA's Android feature matrix describes `show_toast` as a short, exact-text action allowed only for a direct user request, with a native preview/confirmation. It is an ephemeral in-app toast, not a notification, and is not saved. The relevant source-backed behavior is recorded in `myra-ultra/FEATURE_MATRIX.md`; this adaptation does not copy MYRA code or assets.

Personal Agentic AI adds an `In-app toast` screen reachable from the Tools navigation. The user enters at most 120 printable characters, reviews the exact message in a confirmation dialog, and taps `Show in app` before it appears as a three-second floating in-app message. It stays local, is not persisted, and does not request notification permission.

This is a manual user-started counterpart, not an AI-callable or speech-routed `show_toast` action. It uses Flutter's transient in-app message surface rather than Android's native Toast API. It therefore does not claim the source's model-routing parity or native-toast behavior. Tests cover bounds, rejected control characters, exact review text, and no display before approval; Android rendering and device/OEM behavior remain unverified.
