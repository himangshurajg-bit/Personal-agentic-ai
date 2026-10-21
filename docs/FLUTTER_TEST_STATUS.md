# Flutter + FastAPI private test — 21 October 2026

## Delivered scope and non-goals

The new `mobile/` Flutter client and `service/` private single-owner FastAPI service are additive. The existing CLI, web UI, old `android/` app and published assets remain unchanged. This is a private development preview, not a stable production release.

The client implements onboarding, home, chat (stream/stop/retry/history), settings, explicit memory inspection/save/forget/export, local notebook, tap-to-use STT/system TTS, and reviewed reminders/allowlisted app-opening. ChangeNotifier, named routes and light/dark/system themes support the glass-styled UI. Microphone/notification permission is requested at feature use, never onboarding. There is no wake phrase, always-on microphone, model-generated shell, live messaging or purchase executor.

Chat and memory require the separately started authenticated FastAPI service and an installed local model on that computer. This APK does **not** contain on-phone LLM inference or a hosted endpoint. Only the notebook is independent of the service. USB port forwarding (`adb reverse tcp:8766 tcp:8766`) is documented; a non-USB service requires separately managed trusted HTTPS, not an insecure public development server.

## Completed verification

- Flutter 3.47.7 / Dart 3.13.5 analyzer: no issues.
- Flutter suite: **13 tests passed**, including UTF-8 streaming, interrupted replies, explicit retry/no automatic retry, timeout/rate-limit/unconfigured handling, memory operations, persistent conversation selection/history, 382×754 light/dark layouts, no early microphone initialization, denied microphone with typed chat retained, and denied device action review/result.
- FastAPI suite: **17 tests passed**, including auth/browser-origin refusal, strict discriminated schemas, streaming and persisted history, scoped relevant memories/forget/export, correct conversation reopening, local-provider host/transport/completion checks, cancellation releasing active scope, rate limit, expired/wrong/single-use approvals and device-reported receipts, typed success-result validation and distinct unknown outcomes without replay.
- Existing legacy Python suite: **134 passed** during this implementation before final mobile/service-only changes; legacy code was not changed.
- ARM64 release APK build completed after correcting a network-security XML lint error. `includeSubdomains="false"` is explicit on loopback development entries. Gradle resource limits were reduced for this small build computer. Subsequent analyzer, tests and release build all passed.
- `apksigner verify --verbose --print-certs`: APK Signature Scheme v2 verified, one signer. Debug/development signer, not a production signing identity.
- Widget captures were rendered and visually inspected with real Roboto and Material Icons fonts. These are widget-render previews, **not Android emulator or physical-device screenshots**.

Client network/permission tests use mocks. They do not establish actual carrier-network behavior, Android recognizer availability, permission dialog behavior on all versions or notification delivery. Streaming requires an explicit done marker; truncated output stays interrupted. Actions have exact payload review, expiring single-use admission and native receipts. Android schedule/launch acceptance is not proof that a notification was seen or an external app's screen completed.

## Narrow real-model evidence

A temporary synthetic service conversation was exercised against actual loopback Ollama **0.40.7**, with separately installed **Qwen2.5 0.5B**, GGUF Q4_K_M (494.03M parameters; Apache-2.0 license observed). Relevant saved color: `blue`; conflicting `red` fact in another scope; irrelevant pet in the current scope. Model returned `blue` with an explicit completion marker. After deleting saved facts **and** conversation history, it returned `unknown`, also complete.

The initial smoke used an actual local HTTP FastAPI endpoint. The checked-in reproducible smoke (`service/smoke_local_model.py`) repeated the check through FastAPI's ASGI transport to the actual local Ollama HTTP runtime; it passed with 3.55s and 0.50s measured respectively. Results: [`FLUTTER_LOCAL_MODEL_SMOKE.json`](FLUTTER_LOCAL_MODEL_SMOKE.json). Default unit tests remain offline. Neither runtime nor model is committed or bundled. No paid API, cloud deployment, personal prompt or owner-device action was used.

This is **not** broad accuracy/safety/latency qualification. A 0.5B model is weak and can invent facts; the service enforces no model-triggered actions regardless of its output. Forgetting a memory does not erase copies in chat history or previously exported JSON; those need separate deletion.

## APK identity

- Filename: `personal-agentic-ai-0.2.0-private-arm64.apk`
- Application ID: `dev.personalagent.personal_assistant` (separate from old native app)
- Version: `0.2.0`, code `2`
- Size: `19,040,746` bytes
- SHA-256: `6b81870c06c571b7393304dc33f5e7049f370e1bc5b59c930608eee17acd4cd1`
- Main Flutter payload: ARM64 (`libapp.so` and `libflutter.so`); not a general x86/32-bit build.
- Minimum SDK declared: API 26; target/compile SDK: API 36. These are metadata, **not compatibility-test claims**.
- Signer: Android Debug, RSA 2048; certificate SHA-256 `4e4911d0e0cf7b0c312b9bcc6ad431bec9cd9cb64420e6a3a9fc4fa1c50c9603`.

The development key is for this private test only. Do not submit to a store or overwrite older signed release assets. No GitHub release, tag or public APK upload was created for this preview. The APK is supplied privately outside source control.

## Remaining qualification and limits

No connected Android device was available (`adb devices` empty). This computer has no `/dev/kvm` and no installed emulator. Therefore no Android installation/launch, real microphone/TTS, denied OS permission dialog, alarm delivery/boot restoration, weak real mobile network, physical-device or older-version qualification is claimed. Those are outstanding checks, not passed tests. Existing Lecture Finder emulator results do not apply to this separate app.

SQLite messages/memories are plaintext on the service computer; use a private encrypted disk. Secure token storage and disabled Android backups are not comprehensive device security. Only a single authenticated owner is supported. Lexical top-five retrieval is deliberately simple, not semantic memory reasoning. Reminder delivery is approximate, subject to Android battery limits. Android STT may send audio through the installed provider's network service; offline recognition is not guaranteed.

Dependency locks and Flutter's built-in license view retain package notices. `flutter_tts` produces a future Built-in Kotlin migration warning; it did not fail this build. No general zero-vulnerability claim is made. Existing external-executor and legacy provider-verification issues remain open; this new local device/client service does not silently satisfy their separate acceptance criteria.
