# Local liquid-glass studio

## Run

From the cloned repository root, with Python 3.10+:

```sh
python -m agent web
# Open http://127.0.0.1:8765 in a browser on the same computer.
```

No npm install, application build, API key or model download is needed to use it.
Keep the terminal open; Ctrl+C stops it. Use `python -m agent web --port 8766` if
another program already uses the port. A separate scratch database can be selected:

```sh
python -m agent --db /tmp/agent-studio-demo.sqlite3 web
```

That scratch path is a Linux example. The default database is the same local
`.agent-data/memory.sqlite3` used by the CLI. Both interfaces remain usable.

## Real controls

- Preview the deterministic demo commands without executing their steps. No approval
  is created. Loading the UI separately reads pending reviews from local memory.
- Run a supported command: calculate, remember a note, find a saved note, UTC time or
  prepare an exact message draft. This is not general AI chat or a cloud planner UI.
- Inspect pending draft recipient/text and its expiry; revise creates a fresh review
  and invalidates the earlier one. Reject discards a pending draft. Approve records
  `approved_not_sent`; there is no sending implementation.
- Search eligible text files beneath a folder explicitly typed by the person. This
  uses the existing bounded no-follow search, not a model, upload or whole-device scan.
  It requires supported POSIX primitives; unsupported platforms refuse safely.

Unsupported connections and voice/device/APK/background capabilities are named as
unavailable instead of presenting fake action controls.

## Appearance and accessibility

System-font typography stays readable on a liquid-glass background. Water-drop depth,
soft ambient lighting, translucent panels, inset glass fields and edge highlights
extend to buttons and inputs. Controls have tap ripples/short transitions and visible
keyboard focus. The layout becomes a single column at phone widths. Reduced-motion,
higher-contrast and forced-colors preferences have CSS fallbacks. Standard labels,
buttons and live result regions are used. This is not a full accessibility audit.

Android-sized Chromium with touch emulation was tested; no physical Android phone,
APK, PWA install or remote hosting was tested or added. `localhost` belongs to the
machine running Python, so a separate phone cannot access that computer's local UI.

## Local security boundary

The standard-library server listens only on `127.0.0.1`. Host checks reject other
hostnames; POST requires matching Origin and JSON with bounded body/exact field sets.
Repeated JSON names (including escaped equivalents) and decoder nesting failures are
rejected before database/review access rather than selecting the last value.
Only three named static assets are served. There is no directory/download endpoint,
CORS allowance, telemetry, external font or script dependency. A Content Security
Policy restricts scripts/connections to this origin and prohibits framing. Results
are rendered as text, not interpreted HTML. Requests do not log note content, file
paths or recipient addresses.

Do not bind it publicly or reverse-proxy it. There is no login, TLS or multi-user
isolation. Other programs/users already able to act as the local user are outside
this boundary. Files/notes can contain sensitive content despite filename filters;
choose an appropriate root, do not store secrets and do not share screenshots with
private data. Notes are plaintext. A plan preview is not authorization or a guarantee
that a later execution will succeed. All existing approval/expiry/single-use controls
remain. No external send, shell executor, phone control or model service is enabled.

## Optional browser regression check

The Python HTTP tests are in `tests/test_web.py`; they need local ephemeral sockets.
For the separate 19-check Chromium smoke test, use a **scratch database**, because
it saves synthetic notes and creates/revises/approves/rejects example drafts:

```sh
python -m agent --db /tmp/agent-ui-smoke.sqlite3 web
# In another terminal, install optional test tooling outside the repo:
npm install --prefix /tmp/agent-ui-tests playwright@1.64.1
/tmp/agent-ui-tests/node_modules/.bin/playwright install chromium
PLAYWRIGHT_MODULE=/tmp/agent-ui-tests/node_modules/playwright \
UI_SCREENSHOTS=/tmp/agent-ui-screens node tests/ui/check.cjs
```

Node/npm/Playwright are optional development-test tools, not runtime dependencies.
`UI_URL` selects a different local port. `CHROMIUM_PATH` optionally names an already
installed Chromium. Screenshots are written outside the repo. The script checks real
controls, no overflow at 390px, reduced motion, contrast preference and browser errors;
it does not establish physical-device compatibility or complete WCAG conformance.

## Notebook panel (development main)

The local notebook provides 20-note pages with a literal Unicode-aware filter and
ID-based continuation. It renders notes as text and keeps the existing same-origin,
Host, JSON schema and CSP checks. There is no HTTP export/download endpoint; an
explicit notes-only JSONL export is available in the CLI. See [notebook guide](NOTEBOOK.md).

Run `tests/ui/notebook.cjs` with the same optional tooling and scratch server for
11 additional notebook checks: pagination without duplicate IDs, composed/decomposed
Unicode filtering, literal HTML text, no-match state, mobile overflow, reduced motion
and page errors. It creates 26 synthetic notes and does not delete them.
