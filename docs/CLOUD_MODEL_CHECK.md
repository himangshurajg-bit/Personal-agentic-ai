# Opt-in cloud provider smoke

`check-cloud` is a separate live-provider diagnostic for issue #2. It sends one fixed,
synthetic calculator prompt to the configured OpenAI Chat Completions endpoint, validates
the returned plan against the local allowlist, and never executes the plan. It does not
use caller text, saved notes, a database, or credentials from the repository. The default
unit suite and the loopback fixture suite make no live provider calls.

## Before running

This request may incur an OpenAI charge. First set a billing/usage limit in the provider
account appropriate to your own budget. The command requires a separately supplied
operator budget declaration of at most USD 1.00 and an exact one-request acknowledgement;
the declaration is recorded in the result but is **not** technically enforced as a dollar
cap by this client or by the API request. Do not run if the provider account has no suitable
billing limit or if you cannot accept a possible charge.

Provide the key through your own environment/secret manager, never a command argument,
chat, source file or committed `.env`:

```sh
export OPENAI_API_KEY='...'
export CLOUD_AGENT_MODEL='your-enabled-model'
export CLOUD_AGENT_SMOKE_BUDGET_USD='0.05'
export CLOUD_AGENT_SMOKE_ACK='I_ACCEPT_ONE_OPENAI_REQUEST'
python -m agent check-cloud
```

PowerShell:

```powershell
$env:OPENAI_API_KEY = '...'
$env:CLOUD_AGENT_MODEL = 'your-enabled-model'
$env:CLOUD_AGENT_SMOKE_BUDGET_USD = '0.05'
$env:CLOUD_AGENT_SMOKE_ACK = 'I_ACCEPT_ONE_OPENAI_REQUEST'
python -m agent check-cloud
```

The fixed request caps generated completion at 128 tokens, makes one POST, and has no
retry, streaming, fallback, or model/tool execution. This output limit helps bound the
request but is not a price guarantee; model pricing, tokenization and provider billing
are outside the client's control. The actual ordinary cloud planner remains explicitly
selected with `--provider cloud`; this diagnostic is a separate command and never runs
implicitly during tests or normal startup.

## Result

`skipped` means credentials/model, budget declaration, or acknowledgement is missing; no
provider request was made. `failed` means configuration/response/schema validation failed.
`unknown_outcome` means transport ended without a confirmed response: the request could
have reached the provider, so the command does not retry and the operator should reconcile
usage in the provider account before another attempt. `schema_valid` means one response
passed local structural validation only; it does not prove arithmetic correctness, model
quality, service availability, or production readiness. Inspect `status`, not just the
process exit code. The result includes only status, attempt count, tool names and the
operator budget declaration; keys, prompts, model output, provider error bodies and plan
arguments are not logged or returned.

A budget declaration is an explicit operator decision, not a substitute for an actual
provider-side spending cap. The diagnostic cannot guarantee an exact maximum charge.

## Verification boundary

The separate loopback fixture test substitutes a local HTTP fixture for the fixed provider
URL and verifies the request shape, bounded completion, response validation, and single-call
behavior without any real API key/account or paid request. Other transport fixtures continue
to cover sanitized HTTP/protocol failures. Neither fixture establishes live API/model
compatibility. Run a live check only when the operator explicitly configures the above
values and accepts the associated provider charge risk.
