# Offline model candidate review: Gemma 4 E4B

Reviewed 2026-10-22 against the existing offline-AI quality and device gates. This is a candidate assessment, not an implementation, model download, or qualification result. No model weights were downloaded or added to the repository.

## Recommendation

Use Gemma 4 E4B instruction-tuned in Google's LiteRT-LM format as the next candidate to evaluate on-device. It is substantially larger than the earlier 2B Qwen candidate and is explicitly offered in a mobile runtime format, but it is not yet safe to enable as Offline AI: Assamese and Class 12/JEE performance are untested, and the owner's Redmi has not been measured.

## Verified candidate details

- Official model card: `google/gemma-4-E4B-it`; 4.5 billion effective parameters and 8 billion total including embeddings. The card says out-of-the-box support for 35+ languages and pretraining on 140+; the evidence read here did not name Assamese among the supported languages.
- The official model card states Apache 2.0. Its AIME 2026 no-tools result is 42.5%; that is a math benchmark, not proof of JEE tutoring quality or Assamese accuracy.
- Android-ready LiteRT-LM model: `litert-community/gemma-4-E4B-it-litert-lm/gemma-4-E4B-it.litertlm`, listed as 3.66 GB. The public file entry exposes SHA-256 `0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0` (Xet hash `7301453651814b29d434ca0d341e365e0e28dc811cb764d836995cae25b37f31`). This is metadata from the model host; the artifact itself has not been downloaded or independently hashed. Pin and verify the exact source revision and digest again before shipping a downloader.
- Google's LiteRT-LM Android guide documents an Android/Kotlin API, Gradle artifact `com.google.ai.edge.litertlm:litertlm-android`, background engine initialization (which may take up to 10 seconds), and asynchronous token streaming via Kotlin Flow. The current app is Flutter with an Android Kotlin host, so a MethodChannel bridge is a plausible integration route. The installed runtime version, Flutter bridge, cancellable inference behavior, and Android 16 compatibility still need a prototype and tests.
- The LiteRT Community model card lists a 3,654 MB model bundle and an S26 Ultra CPU result of 3,283 MB peak process memory with 5.3 seconds to first token; that timing excludes model-load time. Google’s overview separately estimates 2.2 GB for mobile text-only and 2.5 GB for the full E4B mobile model. These figures use different scopes/setups and must not be treated as a Redmi benchmark. They suggest the candidate is worth testing, not that an 8 GB phone will safely run it alongside Android and the app.

## Remaining gates before enabling offline inference

1. Run every existing English, Assamese, Hindi, Hinglish, arithmetic, and concise Class 12/JEE fixture against this exact model artifact, retaining raw answers and fluent review for non-English results. The generic multilingual claims and AIME score do not substitute for this.
2. Build a small isolated LiteRT-LM Android/Flutter bridge on a separate branch. Prove model lifecycle, streaming, actual cancellation, safe failure behavior, and strict no-network operation. Do not silently change the current unavailable Offline AI state.
3. Implement only after validating a pinned download URL/revision and checksum. Keep download user-started, check free space before writing, verify SHA-256, support cancellation/restart/removal, and never bundle the weights in the APK or source history.
4. Measure peak app/process memory, load and response latency, thermals, cancellation and restart on API 36 and the actual Redmi Note 14 Pro 5G. Its reported 8 GB RAM / 128 GB storage does not establish current free space or runtime fit.

Until every applicable language, runtime, safety, and device gate passes, keep Offline AI unavailable. Do not claim the model was downloaded, tested on Android, or installed on the owner's phone.

## Sources

- [Google Gemma 4 model card](https://ai.google.dev/gemma/docs/core/model_card_4)
- [Google Gemma 4 overview and memory estimates](https://ai.google.dev/gemma/docs/core)
- [Google LiteRT-LM Android guide](https://ai.google.dev/edge/litert-lm/android)
- [Gemma 4 E4B LiteRT-LM model card and performance table](https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm)
- [Exact `.litertlm` artifact file entry and SHA-256](https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/blob/main/gemma-4-E4B-it.litertlm)
- [Existing offline language qualification plan](OFFLINE_LANGUAGE_QUALIFICATION.md)
