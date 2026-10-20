# Security model and limits

## Safe defaults

- Default demo has no networking and no dependencies.
- All plans validated before any step; maximum 4 steps and 4,000-character requests.
- No arbitrary shell, imports, browser, filesystem indexer, account sends or payments.
- Calculator walks a restricted AST; no eval or exponentiation; length/node/value limits.
- Requested local preparation runs without repeatedly asking; consequential actions do not.
- Draft reviews show exact recipient and text; a 15-minute expiry, one-use review, stored
  payload hash and new approval after editing prevent accidental approval reuse.
- Approval returns `approved_not_sent`. There is no executable external dispatch path.
- Provider selection is explicit; no cloud fallback, fixed cloud host, loopback-only local
  origin, redirects disabled, proxy inheritance disabled, bounded responses and timeout.
- Memory is not automatically included in model prompts. Untrusted notes are not replanned
  as instructions. Model plans cannot grant themselves approval or add tools.
- Environment files, databases and Python caches are ignored by Git; example config has no keys.

## Not a security boundary against the computer owner

CLI approval has no authentication factor: anyone able to run the program as the same OS
user can approve a draft, edit the database, change code or read local notes. The payload
hash is not keyed or signed; it detects inconsistent edits, not an attacker with write
access to the database. This is not a hardened sandbox, a secret vault or a multi-user
permission system. Use a trusted local OS account and do not expose the CLI as a server.

SQLite notes, drafts and audit are plaintext. File mode 0600 is attempted but behavior is
OS-dependent; backups and device security remain the owner's responsibility. Audit rows
record note IDs/review hashes, not a complete tamper-evident history. There is no encryption,
retention manager or deletion UI. No sensitive data should be used in the starter.

## Known limitations

Model suggestions can be incorrect, hallucinate notes or choose a permitted tool that
was not appropriate to the user's intent. Schema and allowlist controls narrow effects;
they do not prove semantic correctness. Inspect optional-model output with nonsensitive
examples before trusting it. No live model quality, penetration test, or mobile test was
performed. A process-level timeout does not completely defend against a hostile provider
that drips responses. The current local-mode host checks are not a general-purpose URL
fetch security implementation.

If a run fails midway, earlier safe actions may already have completed. Re-running it can
create duplicate local notes or draft proposals; the CLI is not a durable job scheduler.
Only approvals are single-use. No external operation is retried because none exists.

## Before enabling a real external action

Implement owner authentication, purpose/account scope, exact approved payload/version,
cost and expiry constraints, destination validation, idempotency, cancellation handling,
uncertain-result reconciliation, and a provider success receipt. Changes require a new
review. Never mark an approval or attempted API call as successful execution. Keep deletes,
purchases, transfers and access changes disabled until each has a dedicated permission
and test design. Connecting a service alone is not permission to perform all its actions.
