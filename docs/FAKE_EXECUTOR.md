# Fake-only reviewed-message executor

This increment is a local backend state-machine seam for issue #3. It is deliberately
not a messaging integration. `agent.execution.FakeMessagingProvider` is the only accepted
adapter, and it has no I/O. `execute_fake_approved(...)` is disabled unless the caller
passes `enabled=True`; there is no CLI dispatch command, provider credential support, or
real account connection.

## What it guarantees locally

- It uses only the exact saved `message.prepare` proposal and rechecks its canonical SHA-256
  payload hash, validator and original 15-minute review expiry immediately before claiming.
- A SQLite `BEGIN IMMEDIATE` transaction creates one row per proposal and a stable
  idempotency key derived from that proposal ID and payload hash before calling the fake.
  Concurrent claimers share the same row; only the first receives a dispatchable claim.
- A rejected or superseded review cannot be claimed. Rejection is allowed for an approved
  but unclaimed review. Once claimed, editing/rejection cannot cancel the in-flight result.
- Fake outcomes are recorded as `provider_accepted`, `provider_rejected` or `unknown`.
  Provider acceptance is not delivery confirmation. Every response retains `sent: false`.
- A claimed/unknown result is never dispatched again. Reconciliation may record only
  `accepted` or `not_accepted`, moving to `reconciled_accepted` or
  `reconciled_not_accepted`; it does not reopen execution.
- Execution rows and audit entries contain proposal references, hashes, idempotency keys,
  state and timestamps, not the message body or credentials.

## Limits and operational caution

The local SQLite claim prevents duplicate calls through this one database, but it cannot
make a future remote side effect transactional. A crash after claim, a timeout, or a lost
response is treated as unresolved; retry is blocked because the remote effect may have
happened. Reconciliation is a constrained local operator assertion, not a provider lookup
or independently verified receipt. `provider_accepted` and `reconciled_accepted` must not
be presented as proof that a person received a message.

This starter has no authenticated account/owner identity, selected sender account, real
provider, live-send capability or cross-device/distributed locking. The fake tests prove
state transitions only; they do not establish transport, provider-side idempotency, message
delivery, production security, or a release-ready executor. No live credentials, external
requests or sends are used.
