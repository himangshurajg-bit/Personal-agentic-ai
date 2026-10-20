# Verification record

Checked on 20 October 2026 in a Linux environment with Python 3.14.7.
Python 3.10+ is the intended minimum; other Python versions/operating systems were not
run in the initial verification (later cross-version checks are recorded below). All tests use temporary local databases and fictional data.

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

## Follow-up: expired pending-review listing (issue #1)

On 20 October 2026, the original 46-test suite passed before the change. Three new
regression tests reproduced the listing bug (four failing assertions/subtests): reviews
were still listed exactly at expiry, after expiry, and after refused approval, including
an equivalent timestamp expressed with a non-UTC offset.

`Memory.pending()` now compares parsed expiry instants against one current-time snapshot
and returns only unexpired pending reviews. Expired database rows, payloads and original
expiry timestamps remain unchanged; listing never renews or approves them. The existing
approval-time expiry check remains authoritative when an action is approved.

After the fix:

```text
python -m unittest discover -s tests -v
Ran 49 tests in 0.608s
OK
```

`python -m compileall -q agent tests` and `git diff --check` also passed. Regression
coverage checks before/at/after expiry, history preservation, listing after a refused
expired approval, and timezone-offset equivalence. No live providers or external actions
were used. All previously documented verification limits still apply.

## Documentation follow-up: staged capability roadmap

On 20 October 2026, reviewed the existing code, tests, documentation and issues before
adding `docs/ROADMAP.md` and linking it from README/connections. No runtime behavior,
dependencies, model calls, service connections, device permissions or deployments changed.
The roadmap labels implemented local functions, mock-tested model adapters and proposed
modules separately. Existing issues #2 and #3 retain the transport-first/fake-executor
priorities; broad desired capabilities are not represented as completed code.

Before and after this documentation change, all 49 tests passed (final run: 0.695s).
`python -m compileall -q agent tests` and `git diff --check` passed. Local Markdown links
were checked against existing files. Official Android, Instagram, WhatsApp and YouTube
references were read for the roadmap constraints. This checks documentation consistency,
not real platform compatibility or a new feature's acceptance tests. No APK was built.


## Open-source-informed transport follow-up (issue #2, bug #4)

Read pinned source, model tests and MIT licenses in OpenAI Agents SDK for Python and
Pydantic AI. Independently implemented a standard-library loopback transport fixture suite;
no upstream code or dependency was copied. Sources and comparison are in
[the open-source review](OPEN_SOURCE_REVIEW.md).

The 49-test unit baseline passed. Before the fix, six of seven new loopback transport cases
passed; malformed HTTP status produced an unsanitized `BadStatusLine` containing fictional
response text. Now HTTP protocol exceptions are mapped to the sanitized request failure,
and raised HTTPError response streams are explicitly closed. Redirect refusal and approval
controls remain intact. No real provider was contacted.

Final observed runs on Linux / Python 3.14.7:

```text
python -m unittest discover -s tests -q
Ran 51 tests in 0.675s
OK

python -W error::ResourceWarning -m unittest discover -s tests/integration -v
Ran 7 tests in 0.093s
OK
```

Default discovery remains socket-free; transport fixtures are invoked separately and bind
only ephemeral IPv4 loopback ports. New offline unit tests inject protocol exceptions and
timeout errors; an actual slow-peer/30-second deadline was not tested. The underlying urllib
transport is exercised locally, superseding the earlier untested-transport limitation, but
real local/cloud model compatibility, credentials, live service execution, Android and
production security are still unverified. Optional live-model checks in #2 remain open.


## Maintenance follow-up: JSON decoder failures across Python versions (bug #5)

Fresh remote and local main both matched `9fe9586`; the working tree was clean and open
issues #2/#3 did not cover this reproduced bug. Before changes, 51 unit tests and seven
loopback tests passed on both available runtimes, Python 3.14.7 and Python 3.11.2.
Daily upstream comparisons were already completed; no unchanged research was repeated.

A 4,001-character JSON value containing 2,000 nested arrays is below both response size
limits. On Python 3.11.2 it raised an uncaught `RecursionError` at either outer HTTP JSON
or inner planner JSON decoding. The real CLI consequently printed a traceback instead
of structured error JSON. Python 3.14.7 parses that value and existing schema validation
rejects it; the nesting failure is runtime-dependent, not universal.

Both decode boundaries now sanitize decoder `ValueError` and `RecursionError` exceptions
into the existing provider/planner errors, without exception chaining. `ValueError` also
covers JSON syntax, invalid Unicode decoding and interpreter integer-digit limits. There
is no new retry, relaxed schema, changed byte/character limit, tool or external capability.

Before the fix, the two new unit methods had three failing and three erroring subtests;
both new real-CLI nesting subtests failed on Python 3.11.2. After the fix:

```text
Python 3.14.7:
python -W error::ResourceWarning -m unittest discover -s tests -q
Ran 53 tests in 1.035s — OK
python -W error::ResourceWarning -m unittest discover -s tests/integration -v
Ran 8 tests in 0.427s — OK

Python 3.11.2 (same commands with /usr/bin/python3):
Ran 53 tests in 0.907s — OK
Ran 8 tests in 0.283s — OK
```

The real loopback/CLI cases cover outer and inner deep JSON, one request without retries,
structured failure without traceback or prompt echo, and no notes/proposals/audit effects.
Offline unit regressions inject decoder failures at both boundaries and for both planner
adapters. Test inspection connections are explicitly closed. `compileall` passed on both
runtimes and `git diff --check` passed. Default unit discovery remains socket-free; the
separate transport suite uses only temporary databases and ephemeral loopback listeners.
Python 3.10, other operating systems, live models and real external execution remain
unverified; no provider keys, paid calls, dependencies or service connections were used.
