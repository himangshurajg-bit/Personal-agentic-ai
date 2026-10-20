# Verification record

Checked on 20 October 2026 in a Linux environment with Python 3.14.7.
Python 3.10+ is the intended minimum; other Python versions/operating systems were not
run in this verification. All tests use temporary local databases and fictional data.

## Test run

Command:

```sh
python -m unittest discover -s tests -v
```

Observed result:

```text
Ran 46 tests in 0.719s
OK
```

`python -m compileall -q agent tests` also completed without errors.

Coverage includes bounded arithmetic, rejecting code/unknown tools and extra arguments,
validating the whole plan before effects, local persistent memory, safe preparation without
repeated questions, exact review, single-use approval, expiry, rejecting/invalidating drafts,
changing an already approved draft, refusing inconsistent payload hashes, not treating saved
note content as instructions, and no direct send/payment/delete/shell tool.

Optional local/cloud planners were tested with mocked responses/configuration. Tests also
checked that stored notes are not copied into a cloud planner request. Real inference,
model availability, network transport integration and provider billing were not exercised.

## Separate CLI smoke test

Ran the real CLI as subprocesses with a temporary database:

1. `goal: calculate 12 * 3; remember Practice Python; find Python; draft friend@example.test: Ready to discuss`
2. Confirmed three completed safe steps, arithmetic result 36, and an exact pending draft.
3. Approved that draft; confirmed `approved_not_sent`.
4. Revised the approved draft; confirmed the old approval failed with exit code 1.
5. Rejected the new draft.

Observed smoke result: passed. No messages were sent and no real accounts were connected.
The fictional example address was not contacted. The test database was temporary and
was not included in the repository.

## Not verified

- Any actual local/cloud model, OAuth connection or external action executor.
- Autonomous public-web research or broad natural-language goal solving.
- Cloud hosting, Android/iOS installation, background device behavior or hardware speed.
- Security against a hostile local OS user, formal correctness or production readiness.

These limits are deliberate, not claims of features waiting behind a hidden switch.
