# MYRA Ultra source snapshot in Personal Agentic AI

This repository preserves the available MYRA Ultra Android/Termux project under [`myra-ultra/`](../myra-ultra/), including its Android app, prototype/client source, docs, assets, build scripts, and tests. It came from `MYRA-Ultra-Android-source.zip` (207 files, 612,539 bytes; SHA-256 `3ad9347469e79d44d23a3eb6c3eb3c020b1e00c47505a1798ccd6e63dab81685`). Generated Gradle caches and build output are not part of the source snapshot.

The owner confirmed on 28 October 2026 that they control the relevant redistribution rights and specifically authorized public publication of these MYRA-derived source/assets and a MYRA-built APK in this repository. This records the owner's authorization; it is not an independent legal audit or verification of third-party rights. Upstream license and notice files remain alongside the source.

## Build and verification

On 28 October 2026, `:app:testDebugUnitTest` and `:app:assembleDebug` completed successfully: 383 JVM tests passed with no failures or errors, and the MYRA Android debug APK was produced. The archived project requests compile SDK 34; the build environment had API 36 but not API 34, so `compileSdk` was temporarily set to 36 for the successful build and then restored to the source value 34. Android Gradle Plugin 8.5.2 warned that it had only been tested through API 34. The APK is a debug/development build, not a production-signed release, and it has not been installed or runtime-tested on a physical phone.

The MYRA-specific debug artifact is `MYRA-Ultra-Android-debug-2026-10-28.apk` (17,579,564 bytes; SHA-256 `ef411ca6d710fe47854bb974364c23e7138ca1e51f94e3f66b839d572d24b493`). It is built from `myra-ultra/native-android`; it is not the Personal AI app's APK.

## Scope and gaps

This is a source transfer, not an integration of every MYRA capability into Personal Agentic AI's existing Flutter app. Its public main branch already contains separate Personal AI-specific work; this transfer does not overwrite that app or claim feature parity. The supplied source excludes the original desktop/PyQt code, so full desktop parity cannot be claimed. No user-specific settings or API credentials are included. A source-pattern scan for common API keys, private keys, GitHub tokens, AWS access keys, and quoted credential assignments found no matches; this is a focused scan, not a guarantee that no sensitive value exists.

See the preserved source's [`SOURCE-NOTICE.md`](../myra-ultra/SOURCE-NOTICE.md) and [`FEATURE_MATRIX.md`](../myra-ultra/FEATURE_MATRIX.md) for project-specific context and remaining feature gaps.


## Targeted feature mapping

The Personal AI app now has a user-started Android download manager for direct HTTP/HTTPS file URLs, adapted from the available MYRA Android Download Manager handoff. The Downloads tab shows Android DownloadManager status and progress, lets the owner open completed files or confirm cancel/delete, and stores them in Personal AI's app-specific Downloads folder without broad storage permission. The app asks the owner to review the exact URL before enqueueing; this implementation does not add Gemini/AI-triggered downloads, infer URLs, or claim a transfer of MYRA's unavailable desktop/backend behavior.

This is a focused feature adaptation, not complete MYRA parity. The preserved `myra-ultra/FEATURE_MATRIX.md` remains the source inventory; its available Android functionality is not all implemented as Personal AI features. The original desktop/PyQt/backend source and the owner's actual MYRA settings export remain unavailable, and the Personal AI app has not been runtime-tested on the owner's Redmi device.

### Reviewed Maps search handoff

Personal AI now adapts MYRA's source-backed `navigate_to` capability as a user-entered Android Skills & actions flow: the owner types one place/address (up to 120 characters), then Android shows that exact text in a confirmation dialog before opening a `geo:` search in an available map app. The app does not read location, infer a destination, start turn-by-turn navigation, or claim that a map result loaded. This is a manual, user-started handoff rather than MYRA's Gemini tool-call route. Parser encoding/bounds and the Flutter interaction have focused tests; physical map-app selection and Redmi behavior remain untested.

- Wi-Fi: Personal AI has a separate user-tapped enabled-state read and Android connectivity-settings handoff; it does not toggle Wi-Fi, read network details, or claim post-settings state. See `docs/MYRA_WIFI.md`; runtime/device behavior remains unverified.

### Reviewed clipboard copy

Personal AI now has a manual, user-entered copy flow in Skills & actions, based on MYRA's bounded `copy_text` behavior. The person enters up to 4,000 characters, reviews the complete exact text, and only a separate approval writes it to Android's clipboard. The action does not send text to Gemini or save it in Personal AI; other apps may read clipboard contents. This is a manual adaptation, not Gemini function-call routing. The Flutter interaction has focused widget-test coverage; Android clipboard behavior has not been tested on a physical device.

### Reviewed clipboard excerpt

Personal AI reads clipboard text only after the user taps **Review clipboard text**. It previews the first plain-text item (up to 4,000 characters) and, only after **Add to draft**, inserts a clearly marked quoted excerpt into the editable chat draft. It does not send, monitor, or retain the clipboard content automatically. The draft still requires the usual user Send action. This is a manual reviewed adaptation of MYRA's `read_clipboard_text` capability, not automatic Gemini function-call routing; Android device behavior remains unverified.
