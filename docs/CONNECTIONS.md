# Functions and connections

Nothing in this repository imports the owner's Wabi connections. Connecting an account
in Wabi does not connect this independent project. No account credentials, personal
records, chat history, contact details or tokens were copied into this repository.

## Implemented functions

| Tool | Input | Effect |
|---|---|---|
| calculator | expression | Bounded arithmetic; no calls, names, exponentiation or eval |
| notes.search | query | Read up to 20 matching local notes |
| notes.add | text | Save a requested plaintext local note |
| clock | no args | Read current UTC time |
| message.prepare | recipient, text | Save an exact review artifact, never send |

A registry entry declares argument limits and risk. The runner executes only registered
handlers. Adding an API name to a README is not an implemented connection.

## Optional model connections

- Local: Ollama-style `/api/chat` JSON over loopback, explicitly selected with
  `--provider local`, already-installed model required. Protocol checked with mocks;
  real runtime/model integration not tested.
- Cloud: fixed OpenAI HTTPS Chat Completions endpoint, explicitly selected with
  `--provider cloud`, key/model supplied outside the repository. Protocol checked with
  mocks; no real account, charge or deployment tested.

Protocol references for future compatibility checks:
- https://docs.ollama.com/api/chat
- https://platform.openai.com/docs/api-reference/chat/create

These are implementation references, not a claim that provider documentation or every
model was freshly verified. Provider APIs and eligible models may change.

## Planned connection order

Before adding connections, verify the existing provider transport in
[issue #2](https://github.com/himangshurajg-bit/Personal-agentic-ai/issues/2). The broader
[staged roadmap](ROADMAP.md) distinguishes proposed social, messaging, device, media and
background capabilities from implemented code, and gives their acceptance gates.

1. Add public read-only research with source URLs, timestamps, bounded response sizes,
   SSRF protections, content-as-data handling and no automatic credential use.
2. Add one read-only account integration using least-privilege OAuth and explicit owner
   account selection. Keep tokens in the platform keychain or a real secret manager.
3. Add reversible draft creation and exact review artifacts. Do not equate drafts with
   messages sent, meetings booked or files shared.
4. Only then implement a single side-effecting action with explicit approval binding,
   idempotency, outcome reconciliation, audit and revocation tests.

Email, Calendar, WhatsApp, Drive, browser operation, file indexing, payments, contacts,
mobile sensors, voice, notifications, and smart-home/device actions are all **unimplemented**.
Purchases, destructive actions and access changes remain disabled. Do not fill these gaps
with arbitrary shell execution or broad catch-all tool permissions.
