# Android local-first preview — 0.3.0

This Flutter app is a private, development-signed increment, not the completed assistant. Android 16 / API 36 is the primary qualification target; `minSdk 26` is a package setting, not a promise of tested older-device compatibility. The existing Python/CLI/web and older Android projects are separate and unchanged.

## Install on a phone (no computer required for local tools)

1. Obtain the private ARM64 `personal-agentic-ai-0.3.0-build5-private-arm64.apk` supplied for this build (0.3.0, build 5). There is no public APK release/tag for this increment.
2. Open the APK on the phone. If Android blocks installation, allow installation from that specific browser/file app only if you trust this build; turn that allowance off afterward. The app is labeled **Personal assistant (test)**. It uses an Android Debug/development certificate, not a production identity. Do not uninstall an older copy merely to bypass a signer mismatch: export local data first and inspect the mismatch.
3. Complete onboarding and optionally choose the assistant display name. This changes UI and quoted self-introduction context, not package identity or wake recognition.
4. Leave AI set to **Offline · model not installed** to use local notes, approved memories, tasks, chat search/history, user-authored flashcard decks/cards with local due reviews and study-attempt records, JSON exports and reviewed native actions without a server. The app never makes up an AI reply when no model is installed.
5. Local actions: Home offers a reminder or a searchable catalog of installed apps that Android exposes with a launcher screen. Choosing an app prepares a named, exact launch for review; the app rechecks that it is still launchable after approval. Notification permission is asked for only when first needed. Android accepts an approximate alarm, not guaranteed exact delivery. HyperOS/battery restrictions can delay it. Removing app data removes reminders. Force-stopping can prevent delivery until Android allows the app to run again.

Navigation is Home, Chat, Automations, Memory & Library, Settings. Study and selected files are within those destinations, not separate primary tabs. Automations currently contains individual reviewed actions and receipts, **not** a workflow engine.

### Working local features

- Device-owned conversation retention/reopening and ranked multilingual lexical search. Android uses the Rust native module to tokenize Unicode text and rank exact words/phrases locally; there are no embeddings, model calls, or uploads. Other Flutter test/host targets retain a small Dart fallback.
- Explicitly approved preference/project/summary memories, with current/all-conversation scope, edit/delete/export. Chat retention does not automatically approve facts for long-term memory. Relevant retrieval is lexical top-five matching.
- Private notebook; local task completion; actual practice answers/feedback/results recorded by the owner. Counts reflect records, not inferred mastery. Study includes user-authored decks/cards, editable/deletable content, a due queue and deterministic Again/Hard/Good/Easy intervals; only completed review actions affect review totals. All flashcard data stays in phone-local secure storage and works without AI or network. Tutor prompts/quiz generation still require a configured capable engine; generated answers are not independently verified.
- Android document picker for a specific text/JSON/image/PDF. UTF-8 text preview (200 KB cap) and PNG/JPEG preview (2 MB cap). PDF extraction, OCR, diagram/image AI and camera are **not implemented**. Selected contents are data, never action authority. Text summarization shows exact payload before online sending; images are not submitted to a text-only model.
- Strict local reminder/app-launch approval ledger: five-minute single-use approval consumed before the native effect, explicit denied/failed/unknown receipts, no automatic replay after an uncertain result. The app picker lists installed apps with a visible launcher activity using Android's launcher-intent package visibility; the native bridge rechecks the selected package and label at launch time. AI-generated package strings cannot use the generic action path. No arbitrary intents, shell, messages or purchases.
- Optional Google Tasks, Calendar, Contacts, Drive, Docs and Sheets connectors need the app operator's own Google Cloud/OAuth setup; they never reuse Wabi's connected accounts. Connect and data access are user-triggered, with short-lived tokens in Android secure storage and no background sync. Calendar loads primary-calendar events and Contacts loads limited fields only after you tap Load. Drive and Docs share the limited `drive.file` scope, not whole-Drive access: Drive supports app-created plain-text files; Docs creates native documents from text you enter, lists only its app-tagged Docs, and reads/edits a selected Doc only after your explicit action. Gmail read-only is also available for the latest ten Inbox headers; only opening a message fetches its body. Google's `gmail.readonly` scope is restricted, though: public release needs Google scope verification, and server access/transmission triggers a security-assessment requirement. This build does not send email data to a server or AI, save email bodies, fetch attachments, or scan in the background. See [connector setup](../docs/CONNECTORS.md).
- Markdown display and streaming protocol adapters, cancellation/interrupted-response labels and explicit connection/timeout/rate-limit errors. Actual online generation needs setup below. No offline inference runtime/model is bundled.
- Assistant display name, English/Assamese/Hindi/Hinglish response-language selection, light/dark/system theme, small stateful decorative orb and reduced-motion handling. Voice level display uses recognizer RMS callbacks, not simulated measurements. Language selection is not proof of model quality or installed speech support.
- Custom MCP server management in Settings: add/remove up to 25 named HTTPS endpoints (loopback HTTP only for local testing), optionally store one bearer token in Android secure storage, then test the MCP initialize handshake, initialized notification and inspect `tools/list` descriptions. The test sends only MCP protocol metadata and the optional selected server token; no chat, history or memory is attached. Redirects are refused, replies are capped, and discovery is limited to 200 tools/five pages. Only bounded JSON responses are consumed; SSE response streams, OAuth, and MCP resource/prompt APIs are not implemented. **Tools are display-only**: the app has no `tools/call` path, does not auto-run discovered instructions, and has not yet connected MCP actions to the existing owner-approval flow. Treat server descriptions as untrusted; no protocol/server compatibility is claimed without testing that endpoint.

## Optional online AI — no hosted backend required for compatible providers

An account/endpoint/model must already be yours and authorized; no key, hosted endpoint or subscription is bundled. This work did not create an account or call a paid API.

1. Settings → AI engine → **Online · OpenAI-compatible**.
2. Enter the trusted HTTPS origin (not a URL containing a path, query, username or secret), the exact model ID and provider token directly in Settings. Requests go to `/v1/chat/completions` with bearer authentication and OpenAI-style text SSE. This is a protocol adapter, not a guarantee every vendor supports it. Other authentication, custom base paths, tools and vision are not implemented.
3. Save settings. Tokens use device secure-storage APIs and are never included in export. Switching engine clears the token field to prevent silently reusing a key at another destination.
4. Every send displays destination/model, exact prompt and optional current on-phone history/relevant approved memories. These context choices default OFF each time. The private notebook, unrelated memories and other chats are never silently attached. Choose **Keep local** to cancel. The provider may retain content or charge its own account; this app has no cost-meter/budget enforcement yet. Use only a provider arrangement you accept.
5. No live compatible-provider request was made in this increment because provider configuration is not supplied. Automated tests use synthetic MockClient streams. No online fallback occurs from Offline mode.

### Optional private FastAPI/Ollama path

This remains an optional computer-backed provider, **not the phone-only setup**. Follow [service setup](../service/README.md): Python 3.11+, `uv`, a private bearer token and an independently installed/authorized local model if real generation is needed. Start on loopback only. USB testing can use `adb reverse tcp:8766 tcp:8766`; enter `http://127.0.0.1:8766` on the phone. An Android emulator can use `http://10.0.2.2:8766`. Otherwise use a separately secured HTTPS origin; the app refuses public plaintext HTTP. No server, relay, public tunnel or deployment was created.

Select **Online · private FastAPI** in Settings and enter its origin/token. **Test private FastAPI connection** checks only that service's `/health`; it is not a compatible-provider/model test. Chat still uses explicit per-send review. Existing remote service history and memories are separate from phone storage, and the service can include its already-retained conversation context. Deleting on-phone history does not delete service/provider copies. The service currently caps each text request at 8,000 characters; the phone refuses an oversize payload before transmission. See service docs for its plaintext SQLite storage and retention.

## Offline AI preparation — not installed

Both offline and online AI are requested. Current Offline mode is a truthful unavailable engine boundary, not working on-device LLM inference. Local tools still work. Linux-only Qwen3.5-4B and 2B Q4 candidates both failed concise Class 12 tutoring; the 2B also returned malformed/mixed-language Assamese and ignored a one-sentence instruction. Neither is integrated, and neither test establishes Android performance. Earlier smaller Qwen probes also failed arithmetic or Assamese quality. No model was automatically downloaded and no tiny-model Assamese/tutoring claim is made. A replacement needs representative English, Assamese, Hindi, Hinglish, arithmetic and study-prompt quality tests plus an Android16 runtime, memory/latency/heat/cancellation checks on the phone. The language/voice qualification matrix is in `docs/OFFLINE_LANGUAGE_QUALIFICATION.md`. 128 GB total storage does not establish free space; the app must preflight actual available space before a user-started download. Android16/HyperOS4 compatibility reported by an owner is not a physical-device test result. Do not treat Linux model probes or the computer Ollama smoke test as mobile inference qualification.

## Speech recognition — separate from AI mode

- **Offline** uses native `createOnDeviceSpeechRecognizer`, not an `EXTRA_PREFER_OFFLINE` hint. This build requires Android13+ so it can check `RecognitionSupport.installedOnDeviceLanguages` for the selected exact locale (`en-IN`, `as-IN`, `hi-IN` or `hi-Latn-IN`) before listening. Adding a locale to the selector is not evidence that the device has that on-device language installed. Missing service/language or unverifiable support returns unavailable; no network recognizer, download or silent fallback is attempted. Typing remains usable.
- **Online** deliberately selects Android's installed recognizer after a separate audio-processing disclosure. The microphone permission is requested only after choosing to start. The recognition provider can process audio online; this is not a bundled cloud-speech account. No always-on microphone, background/wake-word listener or automatic retry exists.
- Listening state starts only on a real native `onReadyForSpeech`; stop/cancel, app backgrounding and disposal cancel recognition. Network/provider errors are shown, not treated as transcriptions. Transcript is editable before AI sending.
- Spoken replies use a reported installed, non-network Android TTS voice for the selected locale or remain text-only. No language substitution is permitted. Hindi and Hinglish ASR/TTS, Assamese naturalness/ASR/TTS, and every installed voice must be tested independently; a Hindi voice does not establish Hinglish quality. These voice languages are not yet qualified.
- Settings → **Check device speech capabilities** reports API and recognizer availability without requesting microphone access. Availability does not prove installed language support.

## Privacy and permissions

No broad storage, contacts, calendar, notification-listener, camera, accessibility or overlay access is requested. Microphone and notification permissions are just-in-time and optional for local typing/notes. Document grants are scoped to the selected file and not persisted for background scanning.

Chats, memories, notes, tasks, attempts, settings, app-lock preference and tokens use `flutter_secure_storage` Android secure-storage APIs; backups are disabled. Native reminder title/time is stored separately in app-private SharedPreferences for rescheduling (not encrypted by this implementation). Exports are ordinary plaintext JSON in your chosen location and must be protected separately. Local data currently has a two-million-character cap; export/delete older records before it fills. No cloud sync by default.

The optional Settings → **App lock** uses Android device authentication (biometrics or the device credential when supported). The operating system must confirm authentication before enabling or disabling the setting. With it enabled, the app gates its contents after launch and whenever it returns from the background; cancelling or unavailable authentication leaves the gate in place. If the secure setting cannot be read, content remains hidden. The app creates no PIN and stores no biometric/device credential or authentication secret. This feature does not encrypt exported JSON or third-party copies and is not a full security audit or protection guarantee for a compromised/rooted device. API36 emulator checks exercise the native plugin bridge without prompting for a biometric; real enrolled biometric/device-credential behavior and Redmi/HyperOS remain untested.

Memory deletion, chat deletion, clearing a notebook, uninstalling the app, deleting an export and deleting provider copies are distinct. No account-deletion flow claims to erase third-party data. Deeper encryption review, broader privacy controls and usage-cost tracking remain staged work.

## Build and test

Tested toolchain: Flutter 3.47.7 / Dart 3.13.5, JDK17, Android SDK36, Rust stable, `cargo-ndk`, and Flutter-selected NDK. Android builds compile the Rust crate from source for ARM64 and x86_64; generated `.so` files stay under the ignored build output and are not committed. From the repository root:

```sh
cd mobile
rustup target add aarch64-linux-android x86_64-linux-android
cargo install cargo-ndk --locked
export ANDROID_NDK_HOME="$(find "$ANDROID_HOME/ndk" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1)"
cargo test --manifest-path rust/local_search/Cargo.toml --locked
flutter pub get
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64
# Output: build/app/outputs/flutter-apk/app-release.apk
```

Release builds require the owner’s release key; never silently create a debug-signed release APK or commit a private keystore. The GitHub Actions workflow `Signed Android APK release` creates a downloadable, release-key-signed GitHub release when manually run. Before running it, add these repository secrets under Settings → Secrets and variables → Actions: `ANDROID_KEYSTORE_BASE64` (base64 of the existing `.jks`/`.keystore` file), `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, and `ANDROID_KEY_PASSWORD`. The workflow validates the key, runs Rust and Flutter checks, builds an ARM64 APK, verifies its signature and checksum, then publishes the APK as a GitHub release asset. Gradle is limited to one worker and a 1200 MB heap/768 MB metaspace for the small build computer. A current flutter_tts warning notes future Flutter built-in-Kotlin migration; this is not an observed runtime failure. Versions remain locked in `pubspec.lock`.

On a disposable API36 emulator only (tests deliberately clear app secure data and create synthetic reminders):

```sh
adb shell pm grant dev.personalagent.personal_assistant android.permission.POST_NOTIFICATIONS
flutter test --no-uninstall integration_test/android16_test.dart -d emulator-5554
adb shell pm path dev.personalagent.personal_assistant # verify it remains installed
adb shell am force-stop dev.personalagent.personal_assistant
flutter test --no-uninstall integration_test/rehydrate_test.dart -d emulator-5554
```

[API36 workflow](../.github/workflows/android16.yml) uses an accelerated GitHub-hosted emulator, synthetic data and no provider secrets. Check its actual run before claiming a pass. Native emulator tests do not establish physical Redmi/HyperOS behavior, offline model quality, successful speech, battery-delayed notification delivery, picker workflows or every Android16 restriction. Current evidence is in [test status](../docs/FLUTTER_TEST_STATUS.md). Complete staged scope is in [roadmap](../docs/ANDROID_ROADMAP.md).


## Google Sheets connector

The phone library includes an explicitly user-triggered Google Sheets panel. It uses the limited `drive.file` permission, creates/list only app-tagged spreadsheets, and lets the user read or write an explicitly selected rectangular range (rows 1–50, columns A–J, at most 500 cells). The `RAW` input mode preserves values as text. Google applies this scope to a whole spreadsheet file, not a single tab; the app does not search the whole Drive or access arbitrary existing sheets. Google Picker is not configured. Enable both Sheets and Drive APIs and configure the app-owned Android/Web OAuth clients described in `docs/CONNECTORS.md`; no Wabi account credentials are reused.
