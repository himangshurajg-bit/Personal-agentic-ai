# HyperOS Super Island integration

## What this prototype does

Personal AI's existing `personal_assistant/task_tracker` path already displays a finite, user-started assistant task as an Android progress notification. A developer-gated adapter can attach Xiaomi's `miui.focus.param` extra to that notification. It uses a documented OS3 summary layout (image-text component 1 plus text; static app-icon small-island component), a generic fixed app label and one of the existing safe task-status labels. It does not send the user's task title, prompt, chat, account details, or model output in the vendor payload, and it does not invent a numeric progress value.

The ordinary Android notification remains the source of truth and fallback. If the build opt-in is off, the device is not Xiaomi-family, `persist.sys.feature.island` is unavailable/false, or `notification_focus_protocol` is not 3, no vendor payload is attached. OS2 is intentionally excluded because Xiaomi documents different OS2 Focus Notification templates. The build flag defaults off: use `-PhyperosIslandOptIn=true` only for a controlled developer test after the corresponding Xiaomi scenario has been accepted and a device is whitelisted. This flag is not evidence of permission; the app cannot detect portal approval. The vendor integration is best-effort and no Super Island rendering has been verified here.

The adapter uses only the existing notification flow. It does not add MiPush/cloud delivery, an overlay, accessibility service, background polling/service, or a third-party SDK. Notification permission, when needed, remains governed by the existing ordinary Android notification behavior; the adapter does not request it.

## Xiaomi steps still required

Before claiming a real HyperOS Super Island integration is live:

1. Register/verify the developer account and app in Xiaomi's developer platform; enable the Xiaomi Super Island service for the app, configure the required app fingerprint, and submit the specific assistant-task scene for review.
2. Request device whitelist access for an actual HyperOS 3 test device. Xiaomi's guide says whitelist devices bypass local build-permission checks for testing; whitelist access is temporary (30 days) and limited to 10 devices per app.
3. On that whitelisted HyperOS 3 device, enable the notification permission and app/service as required, install the opted-in development APK, and verify the initial/update/dismiss lifecycle and ordinary-notification fallback. Record the OS/device/build and actual observed UI. Until this test happens, the UI must not be described as displayed.
4. After sufficient device testing, submit the tested production APK and a reproducible scenario-validation method through Xiaomi's formal online verification flow. Only after Xiaomi approves that verification can a public release build enable the flag. New scenarios need their own review.
5. Do not treat HyperOS 2 Focus Notifications as equivalent to Super Island. A separate OS2 integration needs its documented templates, approval and testing.

No Xiaomi developer-service approval, whitelist entry, HyperOS 3 device test, or formal launch permission is currently established for this project. The current change is local-only; it has not been pushed to `main`.

## Official documentation

- [Xiaomi Super Island development guide](https://dev.mi.com/xiaomihyperos/documentation/detail?pId=2131) — native-notification extension, `miui.focus.param`, `param_v2`, template library and OS support/protocol checks.
- [Xiaomi Super Island integration process](https://dev.mi.com/xiaomihyperos/documentation/detail?pId=2132) — service enablement, scene review, device whitelist testing and formal verification.
