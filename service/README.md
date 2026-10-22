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

Without `OLLAMA_MODEL`, `/health` truthfully returns `provider_configured: false` and chat returns 503. This is not a simulated assistant. The test-only provider is injected from tests and cannot be enabled as a production demo responder. The `Provider.stream(messages)` protocol is the replacement boundary. An additional provider must undergo privacy, license, cost and transport review first.

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
- `GET /conversations`: most recent 100 conversation scopes, title and message count for reopening history.
- `GET/DELETE /conversations/{id}`: persisted last 100 messages/deletion. Incomplete assistant messages keep an explicit state; the model context uses only complete messages from the latest 20. Deletion refuses while a stream is active.
- `GET/POST /memories`, `DELETE /memories/{id}`, `GET /memories/export`: explicit, owner-controlled facts. Relevant retrieval selects up to five lexical matches within the conversation only. Memory content is quoted data, not authorization. This is intentionally limited lexical recall, not semantic retrieval or inferred personalization.
- `POST /actions/prepare`, `POST /actions/{id}/approve`, `POST /actions/{id}/receipt`: strict discriminated arguments, exact stored payload, expiring hashed token, transactional single-use consumption. Only future reminder title/time and four allowlisted Android package names are accepted. The Android UI displays a review before consumption/execution. This server does not execute device actions, arbitrary shell, external messages, purchases or credential operations.

A receipt is a device report and always has `independently_verified: false`. Android scheduling/launch acceptance is not proof of a delivered notification or a completed external app operation. Lost replies must not cause an automatic duplicate. Denied, failed and unknown outcomes are shown plainly. Approval tokens are consumed before requesting the device action, deliberately favoring no duplicate over automatic retries.

## Tests

```sh
uv run --project service pytest service/tests -q
```

The tests cover auth/origins, strict schemas, persisted history, conversation-scoped factual selection and forgetting, unconfigured/provider errors, rate limits, expired/used approvals and device-reported results. The client suite separately exercises weak/disconnected streams, status failures, timeout cancellation and denied-permission flows with mocks. No test-provider response should be described as a real AI conversation or physical-device result.

Forgetting a saved memory deletes that record only. It does not erase facts already present in conversation history; delete that conversation separately if needed. Exported JSON files are outside the memory database and must be handled by their owner.
