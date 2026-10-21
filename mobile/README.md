# Flutter personal assistant — private test client

This is the new Android client for the existing Personal-agentic-ai project. It does not replace `agent/`, the local web UI, or the experimental `android/` application. The new application ID is `dev.personalagent.personal_assistant`; it installs separately. It is a development preview, not a production or phone-qualified release.

## What is implemented

- Onboarding, home, chat, settings and explicit memory screens; named navigation, ChangeNotifier state, light/dark/system theme, blurred glass cards, edge highlights and restrained motion.
- Streaming typed chat with persistent server history, partial/interrupted markers, stop and explicit retry. No invented replies when no provider is configured. The notebook alone is available without a service.
- Tap-to-start Android speech recognition, editable transcription, live listening indicator/sound-level visualization and system text-to-speech. Starting speech stops the current reply/playback. Leaving the foreground stops microphone, playback and streaming. Voice never sends a prompt automatically.
- Explicit conversation-scoped memory save/inspect/forget and JSON export through Android's document picker. New chats get a distinct scope; chat history can be reopened from the history button. Service retrieval is lexical top-five matching, not semantic long-term reasoning. Inspecting memories shows all scopes; only the current scope is considered for a reply.
- Reviewed Android reminders and app-opening requests. Only Settings, Chrome, YouTube and Google Calculator package IDs are allowed. Missing apps fail explicitly. Notification permission is requested at first reminder, microphone permission at first voice use. Typing needs neither.

## Private setup

1. Follow [`../service/README.md`](../service/README.md) to start the authenticated service on your computer's loopback interface. Real model chat needs a separately installed local model there. There is no bundled/on-phone language model and no hosted backend.
2. For a USB-connected phone with developer debugging enabled, run `adb reverse tcp:8766 tcp:8766`. In app Settings use `http://127.0.0.1:8766`. The emulator can instead use `http://10.0.2.2:8766`.
3. Enter the service token directly in the app's obscured Settings field, not in messages or source control. It is held in Android secure storage. Test the saved connection. An unconfigured model is reported separately from a reachable service.
4. Without USB, a properly managed trusted HTTPS endpoint is required. Public plain HTTP, credentials in URLs, redirects and non-origin URLs are refused by the Dart client. This repository does not deploy that endpoint. Never expose the development service publicly just to get a phone connection.

The service's local SQLite database contains plaintext messages/memories. Use a private OS account and encrypted storage, and do not save secrets as memory. The handset's notebook/settings use secure storage. Disabling Android backup reduces accidental backup exposure; it is not a general guarantee of device security.

## Voice, reminders and result boundaries

The Android speech provider may require the network and may send audio to its provider. Supported languages and offline recognition depend on the installed recognizer; there is no promise of offline STT. System TTS voices may require a voice download. Denied/missing permissions leave typed chat usable. The waveform reflects sound-level callbacks, not an always-on microphone. No wake phrase, foreground microphone service or background listening is implemented.

Reminders use `AlarmManager.setAndAllowWhileIdle` and notification channels. Delivery is approximate and can be delayed by battery policy. Boot recovery reinstates future stored reminders; uninstalling clears them. No exact-alarm or battery-exemption permission is requested. A native receipt means Android accepted a schedule/launch request; it does not prove the reminder was seen or another app's screen completed. The service records receipts as device-reported, not independently verified.

Actions are typed and prepared server-side, then shown as an exact action for owner approval. A token is payload-bound, expires after 120 seconds and is atomically consumed once before the device is invoked. There is no automatic retry following unknown outcomes. Cancellation of the dialog does not execute. Model output cannot call arbitrary shell, send messages, make purchases or open arbitrary intents. These are explicit UI tools, not automatically extracted free-form model instructions.

## Build and checks

Requires Flutter 3.47.7 / Dart 3.13.5, JDK 17, Android SDK 36 plus plugin-required platform 35. Minimum Android API is 26, which is a build declaration, not a compatibility test result.

```sh
cd mobile
flutter pub get
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64
```

The release build type intentionally uses the development debug signing configuration for private testing. It is not signed with the owner's production key and must not be uploaded to a store or overwrite prior release assets. Keep dependency lockfiles. Flutter's built-in license view retains package notices. Dependency updates need regression testing; `flutter_tts` currently applies the Kotlin Gradle plugin, which Flutter warns must migrate in a future SDK.

See [`../docs/FLUTTER_TEST_STATUS.md`](../docs/FLUTTER_TEST_STATUS.md) for actual completed checks and remaining device qualification and limited model evidence. An APK build is not an installation or physical-device test.

Forgetting a saved memory deletes that record only. It does not erase facts already present in conversation history; delete that conversation separately if needed. Exported JSON files are outside the memory database and must be handled by their owner.
