# MYRA Ultra source snapshot in Personal Agentic AI

This repository preserves the available MYRA Ultra Android/Termux project under [`myra-ultra/`](../myra-ultra/), including its Android app, prototype/client source, docs, assets, build scripts, and tests. It came from `MYRA-Ultra-Android-source.zip` (207 files, 612,539 bytes; SHA-256 `3ad9347469e79d44d23a3eb6c3eb3c020b1e00c47505a1798ccd6e63dab81685`). Generated Gradle caches and build output are not part of the source snapshot.

The owner confirmed on 28 October 2026 that they control the relevant redistribution rights and specifically authorized public publication of these MYRA-derived source/assets and a MYRA-built APK in this repository. This records the owner's authorization; it is not an independent legal audit or verification of third-party rights. Upstream license and notice files remain alongside the source.

## Build and verification

On 28 October 2026, `:app:testDebugUnitTest` and `:app:assembleDebug` completed successfully: 383 JVM tests passed with no failures or errors, and the MYRA Android debug APK was produced. The archived project requests compile SDK 34; the build environment had API 36 but not API 34, so `compileSdk` was temporarily set to 36 for the successful build and then restored to the source value 34. Android Gradle Plugin 8.5.2 warned that it had only been tested through API 34. The APK is a debug/development build, not a production-signed release, and it has not been installed or runtime-tested on a physical phone.

The MYRA-specific debug artifact is `MYRA-Ultra-Android-debug-2026-10-28.apk` (17,579,564 bytes; SHA-256 `ef411ca6d710fe47854bb974364c23e7138ca1e51f94e3f66b839d572d24b493`). It is built from `myra-ultra/native-android`; it is not the Personal AI app's APK.

## Scope and gaps

This is a source transfer, not an integration of every MYRA capability into Personal Agentic AI's existing Flutter app. Its public main branch already contains separate Personal AI-specific work; this transfer does not overwrite that app or claim feature parity. The supplied source excludes the original desktop/PyQt code, so full desktop parity cannot be claimed. No user-specific settings or API credentials are included. A source-pattern scan for common API keys, private keys, GitHub tokens, AWS access keys, and quoted credential assignments found no matches; this is a focused scan, not a guarantee that no sensitive value exists.

See the preserved source's [`SOURCE-NOTICE.md`](../myra-ultra/SOURCE-NOTICE.md) and [`FEATURE_MATRIX.md`](../myra-ultra/FEATURE_MATRIX.md) for project-specific context and remaining feature gaps.
