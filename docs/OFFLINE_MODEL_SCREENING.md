# Gemma 4 E2B experimental offline chat and screening

This Android-only path provides fixed candidate-screening prompts and a separate, explicitly opted-in experimental route from normal typed chat. It is not a qualification or production-readiness claim. The person must start the download, separately opt in under Settings → AI & Voice, and explicitly load the model. The model does not start or download silently. The Python/FastAPI backend and online request-review path are unchanged; local inference has no network fallback.

## Pinned candidate

- Model: Gemma 4 E2B Instruct, 5.1B total / 2.3B effective parameters, LiteRT-LM Android format (`.litertlm`).
- License declared by the published repository: Apache-2.0.
- Artifact: `gemma-4-E2B-it.litertlm`, 2,588,147,712 bytes (about 2.59 GB).
- Immutable repository revision: `6e5c4f1e395deb959c494953478fa5cec4b8008f`.
- SHA-256 independently matches the Hugging Face LFS metadata at that pin: `181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c`.
- AI Edge Gallery v1.0.13 allowlist: 8 GB minimum device RAM. That is a published minimum, not evidence this particular phone has enough free headroom or will run it well.
- Artifact URL: <https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/6e5c4f1e395deb959c494953478fa5cec4b8008f/gemma-4-E2B-it.litertlm>.
- Runtime dependency: LiteRT-LM Android `0.18.1`; CPU backend is used.

The selected file is the general `gemma-4-E2B-it.litertlm` CPU/GPU build from the allowlisted repository, not a vendor-specific Qualcomm or Google Tensor variant. The pinned Hugging Face repository reports public/ungated access and Apache-2.0 metadata; the official Gemma 4 card also states Apache 2.0. We did not accept terms, use credentials or fetch model weights. The published artifact card describes this `.litertlm` format for Android and LiteRT-LM; this project uses LiteRT-LM Android 0.18.1 with the CPU backend. That establishes format/runtime compatibility, not successful inference or performance on the Redmi.

## Review of the ~3B-parameter target

The current Gemma 4 E2B path is not a 3B model: Google lists 2.3B effective parameters and 5.1B total including embeddings. Its 2.59 GB file is a quantized/packaged artifact size, not its parameter count or live RAM requirement. The AI Edge Gallery v1.0.13 allowlist lists E2B at an 8 GB minimum and E4B at 12 GB; the minimum is not a Redmi performance guarantee.

A genuine dense 3B alternative is publicly available as `litert-community/SmolLM3-3B`, a community LiteRT-LM conversion of HuggingFaceTB/SmolLM3-3B. At immutable repository revision `282baa69693339f07d24938fd08ce45a6b08aeeb`, its `SmolLM3-3B_q4_block32_ekv4096.litertlm` artifact is 2,004,633,520 bytes, INT4 block-32 with an INT8 embedding table, 4K context; the repository reports Apache-2.0 and ungated access. Its published LFS SHA-256 is `bdd7eb05b6764fb5a5173bdbdd59354a26f66e4c20b040f0d3da3532071d18f6`. This is publisher metadata, not a hash we independently recomputed from downloaded bytes. The artifact bundles tokenizer and ChatML template. The source card reports a successful Android GPU run on an 8 GB Pixel 8a with LiteRT-LM 0.16.1, but not this Redmi or the app's current LiteRT-LM 0.18.1 CPU path. The card's listed native languages are English, French, Spanish, German, Italian and Portuguese; Hindi and Assamese are not listed.

A second candidate, Ministral 3 3B, is Apache-2.0 and has a community INT4 `.litertlm` conversion around 2.3 GB. Mistral's model card describes a 3.4B language model plus a 0.4B vision encoder and names 11 languages (English, French, Spanish, German, Italian, Portuguese, Dutch, Chinese, Japanese, Korean and Arabic); it does not list Hindi or Assamese. Published Android evidence on an 8 GB Pixel is mixed: the Gallery route is CPU-only and can be killed if roughly 4 GB of free RAM is unavailable, while a separate direct GPU run worked. Neither demonstrates this app's CPU path on the Redmi.

So the runtime ecosystem has real ~3B `.litertlm` options, but this app is currently hard-coded to Gemma E2B and CPU. SmolLM3 is the closest exact 3B candidate with public Apache-2.0 weights and Android 8 GB GPU evidence, yet its published language coverage would regress the app's Hindi/Assamese screening. Gemma E2B better matches that language screening and the supplied 8 GB allowlist, but its count is 2.3B effective / 5.1B total, not 3B. No model-specific inference has been verified in this app for SmolLM3 or Ministral, and the Redmi's exact 4G/5G SKU/SoC and physical run are still needed before claiming compatibility.

The pinned SmolLM3 source is public and ungated, so no terms or credentials are required to inspect its metadata; no weights were fetched. Do not silently replace the current Gemma path: the model choice changes both parameter target and the supported-language expectations.

The app checks the pinned HTTPS host redirects, available app-private storage (remaining model bytes plus a 512 MiB reserve), exact downloaded length and SHA-256, then moves the `.part` file atomically. The person starts/resumes the download, can pause it and can remove the app-private model. If an older E4B install or partial file remains after updating, it is reported and only deleted after the user selects Remove files. No weight file is packaged in source or APK. Before load/inference, the app checks Android's low-memory signal and shows current available RAM; that snapshot is not a fit guarantee, and runtime memory use can still fail.

## Explicit experimental chat

In Settings → AI & Voice, enable “Use Gemma in normal chat · experimental” after reading its warning. Then download and load Gemma from the offline model panel. When AI engine is set to Offline, normal chat calls the native LiteRT-LM conversation directly; the HTTP provider client is not used. A missing model, resource warning, cancellation or runtime error stays local and never changes to an online provider. Disabling the opt-in prevents normal chat from using Gemma; loading is a separate action. App pause cancels local inference and unloads the runtime.

The warning is intentional: although the owner reports 8 GB RAM and the allowlist minimum is 8 GB, the model is unqualified, may answer incorrectly, be slow, consume several GB of memory, heat the device or fail on the Redmi/HyperOS combination. Android's low-memory preflight is a coarse warning, not proof the phone can sustain it. Do not treat the experimental switch, successful load or one response as a passed qualification.

## Fixed screening prompts

The native screening bridge accepts only fixed fixture IDs for English, Assamese, arithmetic/units, Class 12/JEE tutoring, Hindi and Hinglish. Its responses are displayed transiently in Settings and are not saved or sent to an online service. A local sample, process-PSS reading, elapsed time and thermal-status snapshots are observations, not a pass/fail decision. Repeat each prompt at least three times and review factual accuracy, language quality, script, units, brevity and stability manually.

## Remaining qualification

The target Redmi Note 14 Pro 5G / Android 16 / HyperOS behavior, free-space headroom, real peak memory, latency, sustained thermal behavior, cancellation/restart behavior and English/Assamese/arithmetic/JEE answer quality remain to be validated. Emulator/Linux evidence cannot establish those results. The production/qualified status remains “not passed” until the representative cases and device checks pass. The experimental opt-in is not a qualification.

## Validation

Android local unit tests cover pinned metadata, HTTPS redirect allowlist, resume range and free-space policy, fixed fixture IDs, SHA-256 verification and atomic install refusal on bad bytes. The repository Android 16 workflow is required for Kotlin/Flutter integration and API 36 emulator checks. Model weights are never part of CI. Real-device performance and prompt quality require a manually initiated download and test on the target device; they are not automated by CI.
