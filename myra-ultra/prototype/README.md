# MYRA Ultra for Android — early partial port

This is a standalone Android APK project embedding the existing `myra-termux` Python UI and Gemini chat pipeline in Chaquopy and an Android WebView. It is an early partial port, not the complete MYRA app and not feature parity with the Windows/PyQt desktop app or the Termux package. See [FEATURE_MATRIX.md](FEATURE_MATRIX.md) for the source-to-port checklist and exact gaps.

## Current scope

- The embedded Python web UI and Gemini client are bundled; this APK compiles successfully, but no on-device Gemini request or Live voice session has been verified.
- Only the local name/language assistant tools are left enabled. Termux shell/device tools are not exposed because a standalone APK has no Termux command binaries or native Android replacements.
- Android permissions currently include Internet and microphone. This project does not yet implement the source's Android controls (camera, torch, SMS, calls, contacts, location, clipboard, volume/brightness, notifications, files/media, app control, alarms, etc.) or the desktop-only feature areas (dashboard, automations, file/document manager, media, Website Studio/MYRA Coder/WebForge, system monitor and quick-feature tools).
- The microphone is gated by Android's runtime permission dialog; this is not evidence that Live voice works on a device.

## Build

Use JDK 17 and Android SDK Platform 34 with NDK 26.1.10909125, then:

```sh
./gradlew assembleDebug
```

The development APK is written to `app/build/outputs/apk/debug/app-debug.apk`. It is debug-signed and must not be treated as a release APK.

## Rights and distribution

The upstream root has an MIT license, while `myra-termux/pyproject.toml` labels that package Proprietary. The owner confirmed on 28 October 2026 that they control the relevant redistribution rights and authorized public publication of the available Android source/assets and a MYRA-built debug APK; see `docs/MYRA_TRANSFER.md` in the containing repository. The Windows/PyQt desktop source is absent from this snapshot and is not included. Desktop-only files containing hardcoded Firebase key strings were excluded; no cloud restrictions or rotation status has been assessed or changed.
