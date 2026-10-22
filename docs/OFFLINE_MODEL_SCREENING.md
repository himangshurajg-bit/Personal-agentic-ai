# Gemma 4 E4B experimental offline chat and screening

This Android-only path provides fixed candidate-screening prompts and a separate, explicitly opted-in experimental route from normal typed chat. It is not a qualification or production-readiness claim. The person must start the download, separately opt in under Settings → AI & Voice, and explicitly load the model. The model does not start or download silently. The Python/FastAPI backend and online request-review path are unchanged; local inference has no network fallback.

## Pinned candidate

- Model: Gemma 4 E4B Instruct, 8B total / 4.5B effective parameters, LiteRT-LM Android format (`.litertlm`).
- License declared by the published repository: Apache-2.0.
- Artifact: `gemma-4-E4B-it.litertlm`, 3,659,530,240 bytes.
- Immutable repository revision: `e6a3892a8c22cf87ff99583996149cf3cb32452b`.
- Expected SHA-256: `0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0`.
- Artifact URL: <https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/e6a3892a8c22cf87ff99583996149cf3cb32452b/gemma-4-E4B-it.litertlm>.
- Runtime dependency: LiteRT-LM Android `0.18.1`; CPU backend is used.

The app checks the pinned HTTPS host redirects, available app-private storage (remaining model bytes plus a 512 MiB reserve), exact downloaded length and SHA-256, then moves the `.part` file atomically. The person starts/resumes the download, can pause it and can remove the app-private model. No weight file is packaged in source or APK. Before load/inference, the app checks Android's low-memory signal and shows current available RAM; that snapshot is not a fit guarantee, and runtime memory use can still fail.

## Explicit experimental chat

In Settings → AI & Voice, enable “Use Gemma in normal chat · experimental” after reading its warning. Then download and load Gemma from the offline model panel. When AI engine is set to Offline, normal chat calls the native LiteRT-LM conversation directly; the HTTP provider client is not used. A missing model, resource warning, cancellation or runtime error stays local and never changes to an online provider. Disabling the opt-in prevents normal chat from using Gemma; loading is a separate action. App pause cancels local inference and unloads the runtime.

The warning is intentional: the model is unqualified, may answer incorrectly, be slow, consume several GB of memory, heat the device or fail on the Redmi/HyperOS combination. Android's low-memory preflight is a coarse warning, not proof the phone can sustain it. Do not treat the experimental switch, successful load or one response as a passed qualification.

## Fixed screening prompts

The native screening bridge accepts only fixed fixture IDs for English, Assamese, arithmetic/units, Class 12/JEE tutoring, Hindi and Hinglish. Its responses are displayed transiently in Settings and are not saved or sent to an online service. A local sample, process-PSS reading, elapsed time and thermal-status snapshots are observations, not a pass/fail decision. Repeat each prompt at least three times and review factual accuracy, language quality, script, units, brevity and stability manually.

## Remaining qualification

The target Redmi Note 14 Pro 5G / Android 16 / HyperOS behavior, free-space headroom, real peak memory, latency, sustained thermal behavior, cancellation/restart behavior and English/Assamese/arithmetic/JEE answer quality remain to be validated. Emulator/Linux evidence cannot establish those results. The production/qualified status remains “not passed” until the representative cases and device checks pass. The experimental opt-in is not a qualification.

## Validation

Android local unit tests cover pinned metadata, HTTPS redirect allowlist, resume range and free-space policy, fixed fixture IDs, SHA-256 verification and atomic install refusal on bad bytes. The repository Android 16 workflow is required for Kotlin/Flutter integration and API 36 emulator checks. Model weights are never part of CI. Real-device performance and prompt quality require a manually initiated download and test on the target device; they are not automated by CI.
