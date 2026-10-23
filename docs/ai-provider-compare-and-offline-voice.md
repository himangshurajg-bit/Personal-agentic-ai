# AI provider comparison and offline voice boundary

## Provider comparison

Normal chat remains single-provider. The separate **Compare AIs** action is user-started and presents a per-run review containing the exact typed prompt, each selected provider, its model ID and endpoint host. It sends only that prompt, with no conversation history, memory, files, retries or hidden fan-out, after the user presses **Send to selected AIs**. Requests run concurrently and return as separate answers; the app does not automatically combine them by calling a fourth model.

Gemini uses its `generateContent` request/response format. OpenAI API, Groq and OpenRouter use individually configured OpenAI-compatible endpoints and model IDs. An OpenAI API key is not a ChatGPT subscription. Keys are persisted in platform secure storage, never source or logs. The comparison explicitly leaves Offline · Gemma and may transmit prompt text to each chosen service, whose provider may retain the prompt and bill account usage. ElevenLabs is optional online speech synthesis, not a chat model, and is not called by offline Gemma playback.

Provider adapter tests use mock HTTP clients only. No credentials are included in fixtures; no live provider calls are part of tests.

## Offline Gemma speech

When opted-in Offline · Gemma is active, its generated reply can be spoken with an already-installed system voice only when Android reports that the exact selected locale voice does not require network access. Replies retain their generating engine in local chat data, so the **Play installed offline voice** action rejects online, interrupted, and older untagged replies; it accepts only complete replies marked as local Gemma output while opt-in is enabled. A missing language/voice leaves the answer as text and does not switch to ElevenLabs or another online service.

This is a safe reply-text → local system-TTS → playback seam, not an integrated Indic-Speak runtime. The owner selected Indic-Speak as a preferred candidate; existing research reports a roughly 6.6 GB checkpoint and inconsistent published parameter counts (3.36B active vs 3.78B listed). Redistribution/inference license fit, Android packaging/runtime support, quantization, peak memory, language coverage and Redmi Note 14 Pro performance are not established. No checkpoint was downloaded or bundled. The existing Android system TTS path offers no app-controlled emotion tags or guarantee of a cute voice, Assamese/Hinglish quality, latency or stability.

## Microphone/background boundary

The existing voice-recognition bridge starts from a visible app interaction and the app cancels capture when it leaves the foreground. This branch does not add a background/continuous microphone toggle or service: the current architecture lacks a user-started Android microphone foreground service, its required service declaration/permission, persistent notification and stop channel. A future screen-off session must start while the app is visible, show an ongoing notification with a stop action, and use a verified on-device recognizer only. No boot autostart, hidden always-on capture, or offline-mode cloud recognizer fallback is permitted.

## Qualification remaining

Host Android 16 CI is not a Redmi/HyperOS qualification. Before a public stable APK, install the eventual signed build on the Redmi Note 14 Pro Android 16, verify install/update compatibility, then explicitly download the model and record local TTS availability, memory headroom, generation latency, heat and interruption behavior. The previously reported “App not installed as package appears to be invalid” error remains unresolved; this feature branch does not change signing or create an APK.
