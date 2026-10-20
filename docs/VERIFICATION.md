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

## Maintenance follow-up: ambiguous duplicate JSON names (bug #6)

At `a901115`, the fresh remote matched the clean working tree. The baseline 53 unit
and eight loopback tests passed. A mocked local plan with two `text` names in one
`notes.add` argument object silently kept the last value and saved it. This is an
ambiguous-input validation gap, not evidence of an approval bypass or external send.

The two provider JSON decode boundaries now reject duplicate names at every object
level, including equivalent escaped names. They retain the existing sanitized errors,
size limits and no-retry behavior. Repeated names in different objects remain valid;
a positive test executes two independent note steps through both decoding layers.
No memory schema, review lifecycle, tools, dependencies or external capabilities changed.

Before the fix, the new regressions produced five unit failures and two loopback/CLI
failures. Final checks on Linux, with ResourceWarning treated as an error:

```text
Python 3.14.7:
python -W error::ResourceWarning -m unittest discover -s tests -q
Ran 56 tests in 0.671s — OK
python -W error::ResourceWarning -m unittest discover -s tests/integration -v
Ran 9 tests in 0.480s — OK

Python 3.11.2 (same commands with /usr/bin/python3):
Ran 56 tests in 0.690s — OK
Ran 9 tests in 0.399s — OK
```

Socket-free regressions cover duplicate root, tool, note text and draft recipient names
for both local and mocked cloud adapters, plus nested/escaped names in transport JSON.
Actual loopback/CLI cases check outer and inner duplicates, one request, structured
errors without fixture text, and no notes/proposals/audit writes. `compileall` passed
on both runtimes and `git diff --check` passed. The daily upstream comparison was
already complete and was not repeated. No live model, paid API, real connector or
external action was used. Python 3.10, other operating systems and production security
remain unverified; issues #2 and #3 retain their separate outstanding scope.


## Local tools, preview and liquid-glass UI — 20 October 2026

Added independently written, bounded explicit-root local text search; side-effect-free
plan preview; and a standard-library, loopback-only browser UI. No upstream code,
assets, compiled packages or new runtime dependencies were incorporated. Source/license
comparison records are in UPSTREAM_ASSISTANT_REVIEW.md and LEADING_AGENTS_REVIEW.md.

Final Linux checks (ResourceWarning treated as an error):

- Python 3.14.7: 102 unit tests passed in 3.092 seconds; 9 loopback tests passed in 0.493 seconds.
- Python 3.11.2: 102 unit tests passed in 6.276 seconds; 9 loopback tests passed in 0.428 seconds.
- compileall on both runtimes, JavaScript syntax checks and git diff --check passed.
- Playwright/Chromium: 19 essential browser checks passed on desktop (1440×1200)
  and touch/mobile emulation (390×844): preview, calculation, note storage/search, UTC,
  draft preparation/edit invalidation/approval/rejection, explicit-root file search,
  unsupported-command feedback, no horizontal overflow, reduced motion and contrast.
- Desktop and Android-emulated screenshots were visually inspected. This is not a
  physical Android, APK installation, accessibility audit or production-security test.

The HTTP tests check loopback binding, Host/Origin checks, JSON/body bounds, CSP,
static-path restrictions and data operations. Browser approval still records
approved_not_sent; no external sender, account connection, paid API or deployment
was introduced. Live-model verification and executor-design issues remain separate.
See LOCAL_UI.md for the local-server threat model and run instructions.


## Documentation-cleanup package patch (20 October 2026)

Version 0.1.1 changes project wording, neutral upstream comparison references and the
package version only. Runtime behavior and the existing MIT license are unchanged.
The prior Python release and Android test APK remain available without modification.

- 102 unit tests and nine loopback tests passed on Python 3.11.6 and 3.14.7.
- Wheel and source distribution installed cleanly on both versions; the installed
  package smoke check passed for all four combinations from outside the checkout.
- Package contents and current source/filenames were checked for the requested naming
  cleanup; local Markdown links resolve after the upstream review document rename.
- Python compilation, JavaScript syntax and diff whitespace checks passed.
- The unchanged published Android test APK was inspected for matching text; it did not
  require a rebuild. This adds no Android install, launch or physical-device verification.

Historic tags, Git history and already downloaded packages retain their original text.
No license notices were removed, release assets overwritten or history rewritten.

## Local-model diagnostic follow-up (issue #2)

On 20 October 2026, fresh main matched `fba69d2` with a clean working tree; only
issues #2 (real model verification) and #3 (external executor design) were open.
The baseline passed 102 offline unit tests and nine loopback transport tests.
No new reproduced bug justified a duplicate issue. This pass advances the existing
#2 with `python -m agent check-local`, a one-attempt fixed-prompt schema diagnostic
that cannot execute a returned plan, open a database or create an approval.

Final regressions passed separately on Python 3.11.2 and 3.14.7:

```text
python -m unittest discover -s tests -q
Ran 112 tests
OK
python -W error::ResourceWarning -m unittest discover -s tests/integration -q
Ran 11 tests
OK
```

New offline cases cover missing/invalid config (including bad/out-of-range ports),
fixed prompt and one attempt, returned arguments excluded from reports, note/draft
plans never executed, empty/invalid plans, sanitized failures, CLI exit/status handling,
no database creation and loopback IPv6 config. Two new real-HTTP loopback fixtures
exercise CLI output/request/no-database behavior and malformed response rejection.
These are fixture tests, not a real runtime/model result.

Built a local wheel (not a new published release), installed it into clean isolated
Python 3.11/3.14 environments outside the checkout and ran
`tests/packaging/check_installed.py`: both passed. Checks include installed assets,
CLI calculation/notes/search, review/approval-not-sent, loopback UI, preview, and
missing-model diagnostic without database creation. Compileall and diff whitespace
checks also passed. No new runtime dependency or copied upstream source was added.

The actual unconfigured command reported `skipped`, zero inference attempts. A separate
explicit check of the default loopback origin with a diagnostic model label reported
`skipped` after one unavailable-transport attempt; no model was downloaded or run.
Real inference/accuracy/runtime-version verification remains open in #2. The output
states `schema_valid`, not task success, and leaves unknown runtime version null.
No cloud call, external executor, Android/emulator, deployment or account change was
made. Existing Android and liquid-glass UI source files are unchanged.

## Local UI JSON boundary follow-up (bug #8)

Fresh remote main matched `3c105217a6e994d89ac50086db5837f83f3dc559`; the working
checkout was clean and no open pull requests existed. The baseline passed 112 unit
and 11 separate transport tests on Python 3.14.7. Today's upstream comparison was
already complete and was not repeated.

Real local HTTP regressions reproduced two decoding gaps in the UI endpoint:
repeated JSON names silently selected the last value (including escaped-equivalent
names), and Python 3.11.2's decoder raised an uncaught RecursionError for a 4,001-byte
body of 2,000 nested arrays. The latter closed that request without a JSON response;
the server process remained running. Python 3.14.7 parses that fixture and rejects
its type normally. Duplicate `id` fields could select the last pending demo draft
for `approved_not_sent`; no message was sent and no external executor exists.
Existing loopback, Host, Origin and content-type checks were required by these tests;
this is not evidence of a remote-origin exploit.

The UI now reuses the provider decoder's duplicate-name rejection and maps decoder
ValueError/RecursionError to the ordinary safe 400 response before database or review
access. Body limits, schemas, approval payload binding, expiry, single-use rules,
assets, Android source and dependencies are unchanged. HTTP regression coverage checks
root/nested/escaped duplicates, two pending review IDs remaining pending with no
approval audit event, no database creation on invalid input, safe deep-JSON errors
and a successful following preview request. Test clients now close connections even
when a response fails.

Final Linux runs with ResourceWarning treated as an error:

- Python 3.14.7: 115 unit tests (6.950s) and 11 transport tests (0.658s) passed.
- Python 3.11.2: 115 unit tests (6.234s) and 11 transport tests (0.530s) passed.
- A local verification wheel installed into fresh isolated environments on both
  versions; installed CLI/assets/notes/approval-not-sent/loopback UI smoke checks passed.
  This is not a new published package or release, and existing downloads are unchanged.
- All 14 UI HTTP tests, including the new regressions, also passed against the installed
  wheel from outside the checkout on both versions. Compilation on both Python versions,
  JavaScript syntax checking and diff whitespace checking passed.

No model runtime/inference, cloud call, external action, emulator, deployment or
unrelated project change was performed. No installed Ollama executable/process was
found during this review. Real-model verification (#2) and executor design (#3)
remain open; the latter is not enabled by this fix.

## Local notebook: Unicode matching, browsing and export (#9, #10)

Reviewed fresh remote main at `1849b98643ddaa43baa1948ae015039716582414` and its
existing issues/releases before this change. SQLite's built-in `lower()` reproduced
a real note-search miss: saved `École` was not found with `école` (#9). The fix uses
literal NFC-normalized Unicode case folding without a model or new dependency.

The independent notebook feature (#10) adds newest-first ID-cursor pagination to
CLI and the existing glass local UI, plus an explicit streaming notes-only JSONL
export. CLI inspection uses SQLite read-only mode; the existing UI initialization
behavior is unchanged. There is no export HTTP endpoint, automatic upload, import,
note deletion, new model integration or external executor. Development package
version is `0.1.2.dev0`; existing published packages/APK remain unchanged.

Verification with synthetic data on Linux:

- Python 3.11.6: 134 unit tests and 11 separate loopback transport tests passed.
- Python 3.14.7: 134 unit tests and 11 separate loopback transport tests passed.
- Unit/HTTP coverage includes Unicode normalization/case folding, literal percent
  and underscore, page boundaries and inserts between pages, cursor/query validation,
  exact export fields/text, read-only/missing-database behavior, no changed review/audit
  bytes after inspection, and existing same-origin/Host gates.
- Chromium: 11 new notebook acceptance checks and all 19 existing UI checks passed,
  at desktop and 390px phone-emulated widths with no page errors. Notebook tests
  include HTML-as-text safety, no duplicate IDs across pages, decomposed Unicode,
  no-match state, reduced motion and no horizontal overflow. Desktop/mobile notebook
  screenshots were inspected. These are not physical-phone tests or a WCAG audit.
- Built wheel and sdist; the wheel built from the sdist installed into fresh isolated
  Python 3.11.6 and 3.14.7 environments. Installed CLI notes/export plus existing
  calculator/search/preview/review-not-sent/assets/loopback UI smoke checks passed.
- Wheel/sdist inspected for expected assets/docs/tests and exclusion of database/env
  files. JavaScript syntax and diff whitespace checks passed. No runtime dependency
  was added. Optional Playwright tooling stayed outside the project environment.

Search scans locally rather than providing a full-text index. Keyset pages are not a
multi-request snapshot. Export is plaintext, can hold a read lock, and excludes
reviews/audit/approval tokens; it is not a full database backup or restore system.
Real model inference (#2) and the external executor design (#3) remain unfinished.
