# MYRA source review and Android adaptation

Reviewed upstream repository: <https://github.com/codeninjavik/MYRA-AI-ASSISTANT-> at commit `4f8cd94385274dde8b8eea02834b93ae08471b5e` (23 October 2026).

## What is actually present upstream

The repository's tracked files are its README, `LICENSE`, `.gitignore`, and images; it contains no Python/Flutter application source, setup script, dependency manifest, or implementation files to import. The README describes a Windows 10/11 Python desktop assistant and lists voice, Gemini/OpenRouter, screen reading, camera vision, Windows automation/system controls, file operations, WhatsApp, research, and website generation as features, but this checkout does not contain their implementation. A separate PyPI package page advertises a Windows-only CPython wheel and dependencies such as PyQt5, `pywin32`, `pywinauto`, `pyautogui`, `pyttsx3`, and camera/OCR libraries; it is not the Android/Flutter source tree.

## License issue

The current GitHub repository metadata and root `LICENSE` identify GPL-3.0. Its README says “MIT License,” which conflicts with both. Because the actual application source is absent and its license statement is inconsistent, this project does not copy upstream code or redistribute its package. Resolve the licensing discrepancy with the upstream maintainer before importing code or packaging any of its assets. This independently written Android feature below uses no third-party MYRA code or assets.

## Advertised capabilities vs this Android project

Several concepts already have native equivalents here: provider/chat routing, Gemini and other provider configuration (including reviewed parallel comparison on the separate PR #22), local/offline Gemma experimentation, speech input and on-device system TTS, notes/memory, app-launch and reminder actions, local selected-file preview, and scoped Google tools. PR #22 is independent and remains untouched by this branch.

The README's Windows window/keyboard/mouse/clipboard control, app automation, screen reading, and desktop file operations cannot be ported as-is to Android; they need different Android APIs and explicit per-feature OS consent. The Android app intentionally has no hidden always-on microphone, unrestricted accessibility control, arbitrary file access, or automatic messaging. Camera vision/OCR/PDF extraction, a dedicated neural offline voice, and broad website-generation agent are not supplied by this README as usable code and would require separate Android implementations, safety reviews, and qualification.

## Small Android adaptation

This branch adds an original, on-device search over the exact text already selected through Android's document picker. It does not scan storage, persist/index the text, upload it, or use an AI. Search is limited to locally readable text/Markdown/JSON in the existing 200 KB preview path; PDF extraction and image OCR remain unavailable. Results are bounded to 100 and show local line numbers/snippets. The search is cleared when a different file is selected or the view is closed.

Targeted unit tests cover case-insensitive/multiline matching, repeated terms, empty queries, result limits, and snippet bounds. This is one safe first slice, not a port of MYRA's claimed desktop automation suite.
