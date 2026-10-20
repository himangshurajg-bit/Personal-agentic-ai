# Native Android offline test app

This is a small standalone native Java/Android app, **not a WebView or a link to the desktop localhost server**. It deliberately implements only a useful offline subset. The Python CLI, browser UI and database are separate and unchanged.

## What works

- A local calculator for numbers, parentheses and `+ - * /`. Division/multiplication use decimal64 rounding; this is not a scientific calculator.
- Deterministic, side-effect-free plan previews. Preview text never saves notes, sends messages or executes commands. Unsupported steps are labelled unsupported.
- Plaintext local notes in app-private storage, with delete confirmation.
- Local draft preparation with an explicit recipient label and exact text. Each pending review expires after one hour. Approve records `approved_not_sent`, reject records `rejected`. There is no send operation or account connector.
- Rounded translucent gradient surfaces, highlighted glass rims, depth, touch ripples, accessible text and minimum 48dp controls. Tap motion respects the system animator-duration setting.

No Android permissions are requested. There is no internet access, model/API integration, background service, camera/microphone/contact access, filesystem search, voice, device/social control or sync. This is not feature parity with the Python app and is not an AI chat model. Notes/drafts are limited to 100 each and 2,000 characters per input. Uninstalling or clearing app storage erases them. Avoid storing secrets.

## Install

Requires Android 8.0 (API 26) or later. Download `personal-agentic-ai-0.1.0-android-test.apk` from this repository's Android test release and open it on the phone. Android may ask to allow installation from your chosen browser/file manager; permit only that source if you choose to install, then turn that permission off afterward. Do not disable Play Protect. This is locally test-signed, **not a production/Play Store release**. A first-install warning is expected; devices/managed policies may refuse sideloading.

No computer, Python, local server or account is needed to use the installed Android app. The app has separate local storage from the Python version.

## Build from source

Free requirements: JDK 17, `zip`, official Android command-line tools, Android SDK platform 35 and build-tools 35.0.0. No Gradle, Maven dependency, Python runtime or runtime library is bundled.

```sh
sdkmanager 'platforms;android-35' 'build-tools;35.0.0' 'platform-tools'
export ANDROID_HOME=/path/to/Android/Sdk
./android/build-test-apk.sh
```

The script runs standalone calculator/preview logic tests, compiles Java against `android.jar`, links Android resources using aapt2, produces DEX using d8, zip-aligns, test-signs and verifies the APK. Output: `android/build/personal-agentic-ai-0.1.0-android-test.apk`.

The **development-only** keystore is generated outside the repository in `$HOME/.android/personal-agent-test.keystore` (or `AGENT_TEST_KEYSTORE`). Its deliberately standard development password is not production protection. Never use it for a production release, commit the keystore, or publish its private key. Rebuilding on a different machine yields another signature; Android will not install that over this APK without uninstalling and losing local data. A production signing/distribution/update strategy remains future work.

## Verification

See `VERIFICATION.md` for the exact tests performed on this artifact. API 26 is the declared minimum, not proof of physical-device compatibility. No physical phone was tested.
