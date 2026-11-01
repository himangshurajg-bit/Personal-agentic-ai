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

### Reviewed temporary brightness
Personal AI now adapts MYRA's bounded `set_brightness` feature as a user-started slider in Skills & actions. The selected 0–255 level is shown for approval and applied only to Personal AI's current Android window; the original window value is restored when the app pauses or the owner taps Restore now. It never changes system-wide brightness or requests `WRITE_SETTINGS`. Flutter interaction and range mapping have focused tests; physical screen behavior and lifecycle restoration remain unverified on a device. This is a manual app control, not Gemini function-call routing.

### Reviewed live-voice timer handoff

Personal AI adapts MYRA's source-backed `set_timer` action for Live Conversation. A local parser accepts only a direct `set/start/create timer for/of` request with one exact numeric seconds/minutes/hours duration, bounded to 24 hours; ambiguous, delayed, repeating, negated, multi-duration, and non-direct phrasing stay in ordinary conversation. The app previews the duration in a review dialog, then opens Android Clock only after approval. The user must still confirm/start the timer in Clock; Personal AI cannot verify it is running. This does not add background action execution or claim full MYRA parity. Focused parser tests were added; Android/device behavior remains unverified.

### Read-only device status and offline text tools

The current MYRA source's offline text transformations (Base64, URL-form encoding/decoding, and JSON pretty/minify) were already present in Personal AI's bounded, local-only Text tools, so no duplicate implementation was needed. Personal AI now adds a separate Device status tab that reads a one-shot phone snapshot only after an explicit refresh, including Android/app versions, security patch, uptime, storage, memory, display, locale, ringer/theme, thermal and battery-saver state, brightness, notification state, and battery readings. It requests no permissions, reads no location or network identifiers, and does not poll or persist the snapshot. Existing Wi-Fi and system-monitor views remain separate. This is a manual native adaptation, not Gemini function-call routing; the source's other capabilities, missing desktop/PyQt code and MYRA-specific settings are not claimed as fully integrated. Physical-device behavior remains unverified.

### Reviewed media search and volume controls

Personal AI now adapts MYRA's explicit YouTube/Spotify search and audio-stream volume tools as a separate Android tools tab. The search text is bounded and shown for review before an Android search handoff; it opens results only and does not start playback. Volume is read only after a user tap; changing a named stream to an exact percentage requires a separate review, and the UI reports Android's read-back rather than assuming the requested value was applied. These are manual, visible controls rather than Gemini auto-executable function calls. Android-version-specific stream limits and Redmi behavior still need physical-device testing.

### Reviewed one-contact selection

Personal AI now adapts the source-backed contact picker as a separate, user-started Android tool. The owner taps Choose a contact, Android's system phone picker returns at most the selected contact, and Personal AI reads only that granted URI's display name and phone number. It requests no broad Contacts permission, does not enumerate the address book, and keeps the selected details only in the open screen; a local review dialog shows the exact values, and Clear removes them. This is not MYRA's direct-message-to-Gemini lookup: Personal AI does not persist or transmit these details, and full parity is not claimed. The focused picker tests and full Flutter suite pass (386 tests), and `flutter analyze` reports no issues. In a separate clean validation checkout on 30 October 2026, `:app:testDebugUnitTest` and `:app:assembleDebug` also completed successfully: all 61 JVM tests passed (zero failures, errors or skips), the Rust local-search libraries built for arm64-v8a and x86_64, and a debug APK was produced at `mobile/build/app/outputs/flutter-apk/app-debug.apk`. This build used Android compile/target SDK 36. No SDK licenses were accepted for this work. The debug APK is not a release, and the picker and other new Android behavior remain unverified on a physical device, including the Redmi; this is a focused adaptation, not full MYRA parity.

### Reviewed immediate notification

Personal AI now adapts MYRA's source-backed `post_notification` as a manual, user-composed Android action. The owner enters an exact title (up to 80 characters) and text (up to 300), reviews both, and separately approves posting one immediate local notification; Android notification permission is requested only after that approval. The content is not saved, scheduled, shared, or routed through Gemini. Flutter bounds/control-character and review-order tests and Android parser tests cover this adaptation; the Android bridge, notification display, and behavior on the owner's phone remain unverified. This is not full MYRA parity.

### Reviewed SMS draft and phone dialer handoffs

Personal AI now provides manual, user-started SMS-draft and phone-dialer handoffs alongside the existing WhatsApp and social-caption drafts. The owner enters one full international phone number; SMS also requires the exact message text. Android presents the full number and message in a review dialog, then opens the system SMS composer only after approval. The owner must send from that app; Personal AI does not send SMS or request SMS permission. Dialer handoff likewise previews the exact number, uses Android's `ACTION_DIAL` (not `ACTION_CALL`), and never places a call. Both accept only a strict E.164-style number; SMS text is capped at 1,600 characters. The Flutter interaction tests and Kotlin argument-policy tests pass; the fresh Android JVM suite passes all 75 tests, and a full debug APK assembly including Rust local search now succeeds for arm64-v8a and x86_64. Physical-device handoffs remain unverified. These are explicit UI handoffs, not MYRA Gemini tool-call routing or full parity.

## Reviewed email-draft handoff

Personal AI now offers a manually entered, one-recipient email draft from Phone & message drafts. Android validates the address and bounded subject/body, shows the exact recipient and text in a native review dialog, then opens an email composer with a `mailto:` intent only after the user taps Open email draft. Cancel opens nothing; the action never sends. This is a safe manual adaptation of MYRA's source-side single-recipient `send_email` draft input, not Gemini tool-routing parity: the current source flow's email-sending behavior is intentionally not reproduced, and no account lookup, automatic recipient selection or draft persistence is claimed. Flutter and pure-JVM policy tests cover the handoff and input bounds; Android app Kotlin compilation and the JVM suite passed, but Android device behavior remains unverified.


### Reviewed one-off alarm handoff

Personal AI now adapts MYRA's source-backed `set_alarm` capability as a manual Android tools tab. The owner chooses one exact time, reviews it, and only then opens Android Clock with that time; Clock's UI is not skipped, and Personal AI cannot confirm the alarm was saved. Native inputs are bounded to hour 0–23 and minute 0–59. Flutter interaction and pure-JVM argument-policy tests passed; the fresh Android JVM suite passes all 75 tests, and full debug APK assembly including Rust local search succeeds. Clock availability and physical-device behavior remain unverified. This is a visible manual handoff, not MYRA's Live voice function-call route.

### Reviewed exact-text Sharesheet handoff

The social-caption handoff now adds a native Android review showing the exact title and complete text before opening the Sharesheet. Cancel/dismiss opens nothing; after approval, Android presents destination choices, and Personal AI neither selects a recipient nor sends the text. The existing caption flow and exact-text bounds are preserved. The focused Kotlin policy test confirms the title/text are retained verbatim, and the Flutter workflow test confirms the platform handoff receives the exact caption; native dialog and recipient-app behavior still need device validation.

### Reviewed fixed haptic pulse

Personal AI's haptic test now uses MYRA's source-bounded one-shot vibration behavior: the action accepts no caller-controlled pattern or duration, presents an Android confirmation, and requests one fixed 80 ms pulse only after approval. It reports Android accepting the request, not proof that the phone physically vibrated. Pure-JVM argument-bound tests and focused Flutter action tests cover the path; physical-device behavior remains untested.

### Reviewed local task excerpt for chat drafts

Personal AI now provides a user-started, bounded local-task excerpt from the chat composer, adapting the source's `read_myra_tasks` data selection without claiming its Gemini function-routing parity. The owner reviews at most 20 task titles, completion states, and available due-date metadata; IDs and other task fields are omitted, titles are clearly marked as untrusted quoted data, and nothing is sent until the owner later taps Send. Cancel leaves the draft unchanged. Pure Dart bounds/formatting tests and focused Flutter review/cancel tests cover the flow; persistent storage is read locally, and device/provider behavior is not implicated by this manual draft-only path.

## Concise source-to-target gap audit

The preserved `myra-ultra/FEATURE_MATRIX.md` is the source inventory; this is a coverage summary, not a claim that every source behavior is ported.

| Source area | Personal AI status | Remaining gap |
|---|---|---|
| Native shell, dashboard, local tasks and files | Existing target features are present, with independent Personal AI data models and UX. Chat can now add a user-reviewed excerpt of up to 20 local tasks to an editable draft, using only title/status/due date and marking titles as untrusted quoted data. | This does not implement MYRA's Gemini `read_myra_tasks` function routing or any automatic task sharing; MYRA-specific dashboard/backend behavior is not claimed. |
| Chat, Gemini tools and Live voice | Target has its own Gemini chat/voice flows and a growing allowlist of reviewed device actions, including the source-matched timer, alarm, Maps, media, communication and device-status slices documented here. | Tool set, prompts, session behavior and visual UI are not fully equivalent; live provider behavior and phone runtime remain unverified. |
| Phone/device actions | Manual reviewed handoffs now cover selected source actions; the social-caption Sharesheet now shows a native exact-text approval before opening Android destination choices. Some direct native controls already exist in Personal AI. | Remaining actions require per-feature source review and privacy/permission design; this is not MYRA Gemini `share_text` tool-routing parity or a general-purpose privileged tool bridge. The native Sharesheet and destination-app flow remain device-untested. |
| Website Studio, MYRA Coder/WebForge, app/AI integrations | No complete source-parity port is established by this focused transfer. | The source's project-generation, integration and external-service workflows require separate scoped design and tests. |
| Automation/background tasks and desktop/PyQt behavior | No full equivalent is established. | Backend, autonomous/continuous execution and omitted desktop source cannot be inferred or reconstructed as parity from this Android snapshot. |
| Verification | Focused Kotlin/Flutter tests cover reviewed phone/email/alarm/haptic/Sharesheet flows; local-task excerpt formatter and review/cancel behavior have focused Dart/Flutter tests. A fresh Android JVM rerun passed all 75 tests; full `:app:assembleDebug` succeeded with the Rust local-search libraries built for arm64-v8a and x86_64. | No physical-device/Redmi or emulator behavior, full MYRA parity, or live provider behavior is claimed. |


### Reviewed Gemini task-list routing

Personal AI now exposes a read-only `read_myra_tasks` Gemini function for direct questions about the owner's saved task list. The latest message must explicitly ask to show/list tasks and match the requested all/open/completed filter; model calls without that intent or with extra arguments are rejected before task rows are read. The native dialog shows the exact excerpt (up to 20 sanitized titles, status and due dates) and requires a separate Share with Gemini tap. On approval, only that excerpt is sent once in the Gemini function response; cancellation sends no task data, and tasks are never changed. Focused policy/provider and mocked end-to-end routing tests pass. Live Gemini behavior and Android review/share behavior remain unverified on a device; this is one bounded task-query adaptation, not full MYRA parity.
