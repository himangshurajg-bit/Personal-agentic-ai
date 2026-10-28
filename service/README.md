# Private single-user FastAPI service

This service supports the Flutter client in `../mobile` without changing the legacy CLI or web server. It runs on your own computer. There is no deployed endpoint, subscription or bundled model.

## Start privately

Python 3.11 or newer and `uv` are required. From the repository root:

```sh
uv sync --project service --locked
# Set ASSISTANT_TOKEN in your shell to a fresh random token of at least 24 characters.
# Never commit it or paste it into a chat. Generate it with a password manager or
# Python secrets.token_urlsafe(32), then enter it directly in the mobile settings.
uv run --project service uvicorn service.app:create_app --factory --host 127.0.0.1 --port 8766 --no-access-log
```

Keep this shell and local database private. The default database is `assistant.sqlite3` in the current directory; `ASSISTANT_DB` changes that path. SQLite messages, explicit memories and action receipts are plaintext at rest. Use your own private encrypted disk. There is one authenticated owner, not multiuser isolation. Do not put this development server on `0.0.0.0`, enable wildcard CORS or expose it publicly. Direct browser Origins are denied, API docs are disabled, and all routes require bearer authentication. Any production/network deployment needs a separate security and TLS review.

The Flutter client can reach loopback via USB `adb reverse tcp:8766 tcp:8766` or emulator `10.0.2.2`; otherwise it requires trusted HTTPS. The code does not set up a relay or public tunnel.

## Real language model, explicitly optional

Install and run a model in Ollama on the same service computer using that model's own license and hardware requirements. No model is downloaded or paid API called by this project. Set `OLLAMA_MODEL` to the already-installed model's exact name before starting the service. Optional `OLLAMA_URL` defaults to `http://127.0.0.1:11434`; only loopback origins are accepted. Restart the service to apply changes. Models and credentials are not requested through chat.

With the default `ASSISTANT_PROVIDER=ollama`, without `OLLAMA_MODEL`, `/health` truthfully returns `provider_configured: false` and chat returns 503. This is not a simulated assistant. The test-only provider is injected from tests and cannot be enabled as a production demo responder. The `Provider.stream(messages)` protocol is the replacement boundary.

## Optional Groq hosted API (first cloud adapter)

The service also supports Groq's OpenAI-compatible streaming chat endpoint. It is opt-in and server-side: set `ASSISTANT_PROVIDER=groq`, `GROQ_API_KEY` and optionally `GROQ_MODEL` in the private service process environment, then restart the service. The initial model is `openai/gpt-oss-120b`; Groq's current high-level Free Plan table lists 30 requests/minute, 1,000 requests/day, 8,000 tokens/minute and 200,000 tokens/day for that model. Groq says exact account limits may vary. Keep the account on its Free plan if zero-cost use is required; this project never upgrades an account, retries a request or routes to a paid fallback.

The provider key stays on the service computer, never in the Android APK, repository, or chat. The phone still uses the authenticated private service and requires its existing per-message online payload review. An approved online request can include the current prompt and any selected context. Groq says inference inputs and outputs are not retained by default and are not used to train models under its Services Agreement, but it may temporarily log them for reliability or abuse investigations for up to 30 days; its Data Controls offer Zero Data Retention. Third-party model terms also apply. Groq's Services Agreement requires the account user to be at least 18. Do not configure or use a Groq key until that eligibility condition is met.

The API key and model are not checked into this repository. The provider is selected only when `ASSISTANT_PROVIDER=groq`; merely setting a key does not activate it. If the key or model is missing/invalid, startup fails rather than falling back to Ollama. Tests use a mocked HTTPS response only: no live Groq request, key creation, Assamese quality check, JEE evaluation, or billing-tier verification has been performed. Verify English, Assamese and JEE responses yourself before relying on the service; quality is not guaranteed by API compatibility.

## Optional Cloudflare Workers AI image generation

This adds a separate, opt-in prompt-to-image endpoint using Cloudflare Workers AI `@cf/black-forest-labs/flux-1-schnell`. It is disabled unless `ASSISTANT_IMAGE_PROVIDER=cloudflare` and both `CLOUDFLARE_ACCOUNT_ID` and `CLOUDFLARE_API_TOKEN` are set in the private FastAPI process environment. Create a Cloudflare API token scoped to Workers AI inference for the account, set its account ID and token directly in the server environment, then restart the service. The token stays server-side; never place it in the APK, repository, or chat. The Flutter screen sends only the exact prompt entered there—no conversation history, saved memory, selected file, or other context—to this service and then Cloudflare.

The free Workers AI allowance is 10,000 neurons per day. Free-plan requests fail after that allowance is exhausted; this code never retries or switches to a paid model. However, the app cannot inspect or enforce your Cloudflare account's plan: Paid accounts can be charged above the free allowance. If zero-cost use matters, verify the account is on Free and monitor its usage/billing settings before enabling this option. This is a free allowance, not an unlimited guarantee.

Cloudflare's stateless inference documentation says customer content is not retained after processing and is not used to train models; operational metadata may still be retained. Avoid entering sensitive prompts. The endpoint accepts one prompt (1–1,000 characters), authenticates with the existing private-service token, allows at most three attempts per minute, has no paid fallback, and returns only a validated PNG/JPEG/WebP image. Tests use mocked HTTP and make no Cloudflare account, key, or live API request.

The image creation page is a separate route under Settings. Generation requires a reachable private FastAPI service plus the server-side Cloudflare configuration; an unconfigured service returns 503 and no image is generated.

## Optional ElevenLabs expressive speech

`POST /voice/speech` creates an MP3 only when an authenticated client explicitly requests it. Set `ELEVENLABS_API_KEY` and `ELEVENLABS_VOICE_ID` in the private service process environment (never in the APK, repo, or chat); optional `ELEVENLABS_MODEL_ID` accepts `eleven_v4` or `eleven_v4_turbo` and defaults to `eleven_v4`. The API key remains on this service and is sent only to ElevenLabs over HTTPS. ElevenLabs TTS input/output history is retained by default; this project does not enable Zero Retention Mode, which is limited to select Enterprise customers and requires `enable_logging=false`. The app warns before sending each selected reply. This endpoint returns 503 until both required settings are present, permits at most three requests per minute, limits text to 2,000 characters, and does not retry provider failures. Each generation may consume the owner's ElevenLabs credits. The Android app asks before sending one selected assistant reply and stores no provider key.

The supported styles map to ElevenLabs' documented audio tags (`curious`, `crying`, `mischievously`, `whispers`, `shouts`, `laughs`, `sighs`) or no tag for natural speech. They guide delivery; they do not guarantee any emotion or voice performance. The app uses the `eleven_v4` model by default for expressive per-reply playback; this is generated audio, not a real-time conversation. No live provider request or account setup is performed by the tests. The service remains private/local as described above: this feature is not usable from a phone-only install unless the owner has an already-running reachable service with their own authorized API key and voice ID configured.

The Ollama adapter streams `/api/chat`, requires the provider's explicit final `done: true` marker, and does not follow redirects. A synthetic smoke test passed against Ollama 0.40.7 with the separately installed Apache-2.0 Qwen2.5 0.5B Q4_K_M model: it returned the selected saved color, then `unknown` after the memory and conversation history were removed. This verifies a narrow real-provider path, not general accuracy, reliable reasoning or Android runtime behavior. No runtime or model is bundled. See `../docs/FLUTTER_TEST_STATUS.md`.

With an already-running loopback Ollama and already-installed model, reproduce the synthetic check explicitly (never part of default tests):

```sh
uv run --project service python service/smoke_local_model.py --model YOUR_INSTALLED_MODEL
```

The smoke script uses a temporary database, synthetic facts and no personal data. It never downloads a model or calls a paid provider. Missing runtime/model exits nonzero with `verified: false`; weak models can fail. All deterministic memory-selection tests remain network-free.

## API and safety boundaries

- `POST /chat`: conversation ID and prompt; NDJSON `start`, `delta`, `done`/`error`. One active response per conversation, ten accepted requests/minute, provider connection/read timeouts and a total 120-second response budget. The client must not call a truncated stream complete.
- `POST /images/generate`: a single, explicit 1–1,000-character prompt; returns an image only with the opt-in Cloudflare adapter configured. Three requests per minute, bounded validated image response, no retries or provider fallback.
- `GET /conversations`: most recent 100 conversation scopes, title and message count for reopening history.
- `GET/DELETE /conversations/{id}`: persisted last 100 messages/deletion. Incomplete assistant messages keep an explicit state; the model context uses only complete messages from the latest 20. Deletion refuses while a stream is active.
- `GET/POST /memories`, `DELETE /memories/{id}`, `GET /memories/export`: explicit, owner-controlled facts. Relevant retrieval selects up to five lexical matches within the conversation only. Memory content is quoted data, not authorization. This is intentionally limited lexical recall, not semantic retrieval or inferred personalization.
- `POST /actions/prepare`, `POST /actions/{id}/approve`, `POST /actions/{id}/receipt`: strict discriminated arguments, exact stored payload, expiring hashed token, transactional single-use consumption. Only future reminder title/time and four allowlisted Android package names are accepted. The Android UI displays a review before consumption/execution. This server does not execute device actions, arbitrary shell, external messages, purchases or credential operations.

A receipt is a device report and always has `independently_verified: false`. Android scheduling/launch acceptance is not proof of a delivered notification or a completed external app operation. Lost replies must not cause an automatic duplicate. Denied, failed and unknown outcomes are shown plainly. Approval tokens are consumed before requesting the device action, deliberately favoring no duplicate over automatic retries.

## Tests

```sh
uv run --project service pytest service/tests -q
```

The tests cover auth/origins, strict schemas, persisted history, conversation-scoped factual selection and forgetting, unconfigured/provider errors, opt-in Cloudflare selection and mocked image generation, rate limits, expired/used approvals and device-reported results. The client suite separately exercises weak/disconnected streams, status failures, timeout cancellation and denied-permission flows with mocks. No test-provider response should be described as a real AI conversation or physical-device result.

Forgetting a saved memory deletes that record only. It does not erase facts already present in conversation history; delete that conversation separately if needed. Exported JSON files are outside the memory database and must be handled by their owner.

## Paired screen-share receiver prototype

The private service includes an opt-in paired receiver contract for an external Android sender. It requires a one-use expiring pairing code, sender-scoped credentials, and per-session receiver approval; frames remain in memory and are never saved. It does not capture screens, grant MediaProjection, or include an Android receiver UI. Read [`docs/SCREEN_SHARE_RECEIVER.md`](../docs/SCREEN_SHARE_RECEIVER.md) for the protocol, security boundaries, and outstanding integration/device work. The development server is loopback-only; do not expose these routes over a network without HTTPS/WSS, owner-controlled access, and client lifecycle validation.
