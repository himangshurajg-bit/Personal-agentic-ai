# Open-source comparison and bounded improvement

Reviewed on 20 October 2026. This is a focused code/license comparison, not a claim to
have audited either entire project or run their test suites. Upstream source was read
at the pinned commits below, not installed or executed. Both projects are substantially
larger and use SDK/dependency stacks that this dependency-free starter does not need.

## Compared actual code and licenses

### OpenAI Agents SDK for Python

Repository: [openai/openai-agents-python](https://github.com/openai/openai-agents-python)

Pinned revision: `64cd5dfc5a1579870dcbed0ea42b27aa84033fee`.

- [Chat Completions implementation](https://github.com/openai/openai-agents-python/blob/64cd5dfc5a1579870dcbed0ea42b27aa84033fee/src/agents/models/openai_chatcompletions.py): provider-backed response handling around its Chat Completions client.
- [Model tests](https://github.com/openai/openai-agents-python/blob/64cd5dfc5a1579870dcbed0ea42b27aa84033fee/tests/models/test_openai_chatcompletions.py): `test_runner_normalizes_nullable_chat_usage` exercises the client/model/runner path with an injected `httpx2.MockTransport`, rather than replacing the whole planner. This shows the value of testing below a high-level adapter mock.
- [License](https://github.com/openai/openai-agents-python/blob/64cd5dfc5a1579870dcbed0ea42b27aa84033fee/LICENSE): MIT, copyright 2025 OpenAI; redistribution of copied/substantial code requires preserving its notice and license.

### Pydantic AI

Repository: [pydantic/pydantic-ai](https://github.com/pydantic/pydantic-ai)

Pinned revision: `b40096c4c91e4db361ee3f23b0e3f6b85569faa2`.

- [OpenAI model implementation](https://github.com/pydantic/pydantic-ai/blob/b40096c4c91e4db361ee3f23b0e3f6b85569faa2/pydantic_ai_slim/pydantic_ai/models/openai.py): `_map_api_errors` maps status, connection and generic API errors into application-level model errors.
- [Model tests](https://github.com/pydantic/pydantic-ai/blob/b40096c4c91e4db361ee3f23b0e3f6b85569faa2/tests/models/test_openai.py): `test_model_connection_error`, `test_model_status_error` and stream-error transport fixtures test distinct failure classes. Some upstream errors retain provider bodies/messages; that behavior is not adopted here because this starter deliberately hides potentially private provider text.
- [License](https://github.com/pydantic/pydantic-ai/blob/b40096c4c91e4db361ee3f23b0e3f6b85569faa2/LICENSE): MIT, copyright Pydantic Services Inc. 2024 to present; copied/substantial code needs the license/copyright notice preserved.

## Selected improvement, not feature accumulation

The shared useful idea is to test at the transport boundary and classify failures. Existing
[issue #2](https://github.com/himangshurajg-bit/Personal-agentic-ai/issues/2) already identified
that `post_json` was bypassed by model adapter mocks. Rather than importing an agent framework,
adding a new tool, or copying upstream implementation, this project now has independently
written standard-library loopback HTTP fixture tests and a small provider-error fix.

The fixtures reproduced [issue #4](https://github.com/himangshurajg-bit/Personal-agentic-ai/issues/4):
a malformed HTTP status line raised `http.client.BadStatusLine` outside the sanitized error
boundary. The previous catch covered `URLError` and `OSError`, not HTTP protocol exceptions.
The fix maps `HTTPException` to the existing sanitized `ValueError`, suppressing raw provider
text in the displayed traceback. An `HTTPError` response stream is also explicitly closed.
Redirect refusal, bounded responses, no retry, no proxy inheritance and approval checks stay
unchanged. No complete-deadline guarantee is added by this fix.

No upstream source, test snippets or dependency was copied into this repository. This is
inspiration from a testing/error-boundary pattern; all added code was written for this
project's current urllib transport. Therefore no third-party code notices are added to the
project license. Pinned attribution above records the sources of the design comparison.
Future copied code must carry its applicable notices; MIT is not a waiver of attribution.

## Test commands and scope

Default offline unit suite, no sockets or external providers:

```sh
python -m unittest discover -s tests -v
```

Explicit local transport checks (bind ephemeral ports on **127.0.0.1 only**):

```sh
python -W error::ResourceWarning -m unittest discover -s tests/integration -v
```

The integration directory intentionally has no `__init__.py`, keeping these socket-using
fixtures out of default unittest discovery. Tests stop and close their local servers.
They make no public-network calls, use no credentials and do not invoke real model runtimes.
Restricted environments may deny even loopback listeners; that is not a provider failure.

Seven real-loopback cases check request JSON/headers with proxy variables set, malformed
JSON, invalid encoding, oversize responses, refusal to follow redirects, sanitized HTTP
errors with no retry, and malformed HTTP status lines. Two new offline unit methods check
protocol exceptions and the configured timeout/error sanitization without a real 30-second
wait. Timeout duration under an actual stalled/dripping peer remains unverified.

Before the fix: 49 default unit tests passed; the new transport suite had six passing
cases and one failing case with `BadStatusLine`/fictional response text in its traceback.
After the fix: 51 default tests and all seven transport tests pass. See the verification
record for the observed runs. This partially advances #2; live-model smoke checks remain
open and opt-in. No real integration, send, new account, deployment, model download or paid
call was introduced, and #3's external executor remains unimplemented.

## 29 October 2026: SSE framing review

LangGraph's MIT-licensed Python SDK recently fixed its SSE decoder after regressions in
multiline/empty `data` fields, CR line endings, and event IDs across reconnects. The
source change and focused tests are pinned at
[`2f46bb3ca48f7e5d34eae000df7dfe77f9c0139d`](https://github.com/langchain-ai/langgraph/commit/2f46bb3ca48f7e5d34eae000df7dfe77f9c0139d), which
references the WHATWG event-stream parsing rules. This is relevant to Personal-agentic-ai's
Groq OpenAI-compatible stream, but LangGraph's reconnect cursor/backoff is not: this app
intentionally does not retry a provider stream or resume a partial answer.

The existing Groq adapter parsed each `data:` line as a separate JSON object, which did
not follow SSE's rule to join multiple data lines within one blank-line-delimited event.
The project now independently assembles those payload lines, tolerates comments/heartbeat
lines, and still requires a complete `[DONE]` event before treating a response as complete.
A mocked HTTP test covers multiline JSON plus CRLF framing; no credentials, external calls,
retries, dependencies, or upstream code were added. This is a narrow standards-based
hardening, not a port of LangGraph's decoder or claim of exhaustive SSE conformance.

## 31 October 2026: initial UTF-8 BOM in server-sent events

LangGraph's MIT-licensed Python SDK PR [#9402](https://github.com/langchain-ai/langgraph/pull/9402)
fixed SSE-spec handling for repeated `data:` fields, empty event IDs, and a UTF-8 BOM at
stream start. This service already joins repeated data fields with newlines and does not use
SSE IDs or reconnect cursors. Its `_iter_sse_data()` did, however, treat an initial BOM as
part of the first field name (`\ufeffdata`), silently dropping the first provider event.

The service now strips a BOM only at the start of a stream, with a `MockTransport`
regression test that first failed by returning no content and now verifies the first event
is preserved. No upstream code or dependency was copied or added; this narrow change needs
no third-party notice. FastAPI 0.162.0's new boolean-form defaults do not apply to this
service's JSON-body routes. CrewAI's security fixes concern framework-specific code the
service does not use; MCP Python SDK 2.3.0 predates this review and is not used by the
Android MCP client. No dependency or lockfile changes are warranted.

`uv run --frozen --group dev pytest -q` in `service/`: 29 tests passed. No live provider,
network service, credentials, or paid call was used.
