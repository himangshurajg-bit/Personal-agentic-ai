# Opt-in local model schema check

For the separate explicitly authorized OpenAI cloud-provider smoke, see [CLOUD_MODEL_CHECK.md](CLOUD_MODEL_CHECK.md).

Issue #2 includes a gap between fixture-tested HTTP transport and real local-model
compatibility. `check-local` provides a repeatable, side-effect-free diagnostic for an
already-installed Ollama-compatible runtime. It does not install a model/runtime or
certify compatibility before an operator runs it against a real model.

## Run

From an updated source checkout (or a future package containing this command):

```sh
# Linux/macOS: replace the example name with your exact already-installed model.
export LOCAL_AGENT_MODEL='your-installed-model'
# Optional, defaults to this exact loopback origin:
export LOCAL_AGENT_URL='http://127.0.0.1:11434'
python -m agent check-local
```

PowerShell:

```powershell
$env:LOCAL_AGENT_MODEL = 'your-installed-model'
python -m agent check-local
```

Only HTTP origins on `127.0.0.1`, `localhost` or `::1` are allowed. Credentials,
paths, queries, fragments, invalid/out-of-range ports and non-loopback hosts are
refused before a request. Redirects and inherited proxies stay disabled. Configure
only a local runtime you trust: its own telemetry/network behavior is outside this
program's control.

## What happens

The command sends the static planner policy plus the fixed request:

> Calculate 2 + 2 using the calculator tool. Return one step only.

It makes one nonstreaming `/api/chat` attempt, with the same 512-token output option,
response-size limits, strict JSON parsing and whole-plan validation as the existing
local adapter. The transport uses a 30-second socket-operation timeout, **not** an
end-to-end wall-clock deadline; a slow peer can take longer. There is no retry, model
pull, fallback to cloud, tool execution, notes lookup/write, approval creation or send.
Even a schema-valid `notes.add` or `message.prepare` response is only inspected, never
executed. The ordinary offline `plan` command remains offline.

## Read the JSON result

- `skipped`: model configuration is missing, or local transport could not complete.
  No success is claimed. A configured unavailable runtime has `attempts: 1`; missing
  model configuration has `attempts: 0`. Start/check your own installed runtime before
  explicitly running again. Transport failure is not proof the runtime is absent.
- `failed`: invalid configuration, HTTP/protocol/JSON/plan rejection, or empty plan.
  Exit code is 1. Error details and provider-controlled content are not echoed.
- `schema_valid`: a nonempty response passed schema/argument validation; exit code 0.
  Tool names/count are reported, not arguments, drafts or generated text. This **does
  not** check arithmetic correctness, task adherence, model reliability or production
  readiness. `executed` remains false.

Skipped checks also exit 0; automation must inspect `status` rather than treating
exit code 0 as successful inference. `attempts` counts inference POSTs, not metadata
GETs, responses or completed inference. With valid configuration, a best-effort `GET /api/version` runs first against the same validated loopback origin. It uses no model,
credential, proxy or redirect; the response is capped at 4 KiB and the socket-operation
timeout is two seconds. Only a numeric `major.minor.patch` value is reported.

`runtime_version_status` is `not_attempted` when configuration is missing/invalid,
`reported` when that strict version format is returned, and
`unavailable_or_unrecognized` when the optional endpoint fails, is unsupported, or
returns an unrecognized value. In the last case `runtime_version` remains null and the
inference check continues. This best-effort metadata probe does not qualify a runtime or
model; never infer a version from a fixture or model label.

## Verification scope

Tests cover socket-free missing/invalid configuration, one-attempt behavior, safe
error reporting, empty/invalid plans and no execution/database access. Separate
loopback fixture tests run the real CLI and HTTP transport, including a schema-valid
note request that must not create a database. These fixtures are not real inference.

During development on 20 October 2026, no installed Ollama executable or listening
runtime was found at the default endpoint. The actual no-model command reported
`skipped`. No model download, paid API, emulator, Android modification or deployment
was performed. Real local-model accuracy/runtime verification and live cloud compatibility in
issue #2 remain open; the external executor in issue #3 is unchanged and unimplemented.
