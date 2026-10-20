# Python release packaging

The first published release is `v0.1.0`; the existing project version was already
`0.1.0` and no earlier tags/releases existed. Its wheel and source distribution are
GitHub Release downloads, not a PyPI/GitHub Packages registry publication.

## Documentation cleanup patch: v0.1.1

Version `0.1.1` removes third-party product/assistant naming from current project prose
and renames the upstream comparison document while retaining numeric source identity,
pinned commit/artifact evidence, licensing observations and the unchanged MIT notice.
No third-party code or assets were imported; behavior is unchanged. The earlier
`v0.1.0` packages/tags and Android test artifact are not overwritten. Old downloads
and Git history still contain their original text; current documentation is in main.

## Install

Requires Python 3.10+. Download the wheel from the Releases page, create/activate a
virtual environment, then run:

```sh
python -m pip install ./personal_agentic_ai-0.1.1-py3-none-any.whl
python -m agent run "calculate 12 * 3"
python -m agent web
```

Open `http://127.0.0.1:8765` on the same computer. Keep the terminal open. Memory
uses `.agent-data/memory.sqlite3` in your current directory unless `--db PATH`
appears before the command. The source distribution `.tar.gz` is an alternative;
installing it requires a build backend (usually downloaded by pip).

## Packaging regression fixed

The original implicit build configuration produced a wheel **without**
`agent/web_assets/{index.html,style.css,app.js}`. Installing it outside the checkout
caused `FileNotFoundError` when accessing the UI. The installed-artifact check
failed against that original wheel, then passed after explicit build metadata and
package-data configuration were added. The source distribution now includes the
security guide, docs, examples and all test directories too. No runtime dependency
was added. The existing MIT license is preserved.

## Maintainer checks

```sh
uv build --out-dir /tmp/personal-agent-dist
uv venv /tmp/personal-agent-check --python 3.11
uv pip install --python /tmp/personal-agent-check/bin/python /tmp/personal-agent-dist/*.whl
cd /tmp
/tmp/personal-agent-check/bin/python /path/to/repo/tests/packaging/check_installed.py
```

Repeat with the source `.tar.gz` in a fresh environment and Python 3.14. Run checks
outside the checkout so imports cannot accidentally use uninstalled source files.
The check uses synthetic temporary notes/drafts and loopback HTTP only. It verifies
installed assets, preview without database creation, calculator, notes, draft
approval-not-sent, eligible local file search on Linux, and actual CLI web startup.

Release preparation passed:
- 102 unit and nine loopback tests on Python 3.11.2 and 3.14.7.
- Clean wheel and source-distribution installations on Python 3.11.6 and 3.14.7.
- Installed CLI/UI smoke checks for all four installation combinations.
- Compilation, JavaScript syntax and diff checks.

The release checks do not establish Windows/macOS, physical Android, live-model or
external service compatibility. File search needs POSIX no-follow primitives and
was tested on Linux. The Python browser UI is computer-local only: it is not hosted,
not a phone app, and cannot be reached using another device's localhost address.
Draft approval remains `approved_not_sent`. No external executor exists. See
`LOCAL_UI.md`, `VERIFICATION.md` and `ROADMAP.md` for capability/security limits.
