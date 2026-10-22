# Gemma 4 E4B local screening (not production chat)

This Android-only screen is a contained engineering evaluation path. It does not enable the model in normal chat, persist prompts or answers, add a network fallback, or alter the Python/FastAPI backend. Online chat continues to use its existing per-send review flow. The model runtime is not started until the person explicitly downloads and loads the candidate; app pause stops in-flight inference/download work and unloads the engine.

## Pinned candidate

- Model: Gemma 4 E4B Instruct, 8B total / 4.5B effective parameters, LiteRT-LM Android format (`.litertlm`).
- License declared by the published repository: Apache-2.0.
- Artifact: `gemma-4-E4B-it.litertlm`, 3,659,530,240 bytes.
- Immutable repository revision: `e6a3892a8c22cf87ff99583996149cf3cb32452b`.
- Expected SHA-256: `0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0`.
- Artifact URL: <https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/e6a3892a8c22cf87ff99583996149cf3cb32452b/gemma-4-E4B-it.litertlm>.
- Runtime dependency: LiteRT-LM Android `0.18.1`; CPU backend is used for the initial conservative screening path.

The app checks the pinned HTTPS host redirects, available app-private storage (model remainder plus a 512 MiB reserve), exact downloaded length, SHA-256, then moves the `.part` file atomically. The user starts/resumes the download, can pause it, and can remove the app-private model. No weight file is packaged in source or APK.

## Fixed test prompts and limits

The native bridge accepts only fixed fixture IDs for English, Assamese, arithmetic/units, Class 12/JEE tutoring, Hindi and Hinglish. User-provided URLs/prompts are not accepted by this evaluation channel. Responses are displayed transiently in Settings and are not saved or sent to an online service. A local sample, process-PSS reading, elapsed time and thermal-status snapshots are observations, not a pass/fail decision. Repeat the prompts and review factual accuracy, language quality, script, units, brevity and stability manually.

This path is not a qualification. The target Redmi Note 14 Pro 5G / Android 16 / HyperOS behavior, free-space headroom, real peak memory, latency, sustained thermal behavior, and English/Assamese/arithmetic/JEE answer quality remain to be validated. Emulator/Linux evidence cannot establish those results. Until the representative cases and device checks pass, normal-chat Offline AI remains unavailable.

## Validation

Android local unit tests cover the pinned metadata, HTTPS redirect allowlist, resume range and free-space policy, fixed fixture IDs, SHA-256 verification and atomic install refusal on bad bytes. The repository Android 16 workflow is required for Kotlin/Flutter integration and API 36 emulator checks. Model weights are never part of CI. Real-device performance and prompt quality require a separately authorized, manually initiated download and test on the target device; they are not automated by CI.
