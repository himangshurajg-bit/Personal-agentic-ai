# Personal-agentic-ai
A personal agentic AI starter project designed for cloud and offline use, combining planning, memory and tool connections to prepare tasks independently and request owner approval before consequential actions.

---

A working, local-first starting point for a personal AI assistant with bounded autonomy.
It demonstrates a **brain/planner**, **local memory**, **tool connections**, **risk-based
permissions**, and a path to **cloud or offline local-model operation**.

This is a tested starter, not an advanced production assistant that can do everything.
The goal is to grow the architecture without pretending that unbuilt integrations work.

## The autonomy contract

Give the agent a goal. Within explicitly configured capabilities, it should plan and do
safe, reversible preparation without asking permission for every step. Ask early only
for genuinely missing essentials, not routine implementation choices. Present the exact
final action for approval before a message, payment, deletion, access change, or other
consequential external effect. An edit invalidates the old approval.

This release implements that contract in a small scope: up to four validated tool steps,
auto-running calculation/search/local notes, and exact message-draft review. It **cannot
send a message**, even after approval. Real research and account connections are future
work, not secretly enabled features.

## Start in two minutes

Requires Python 3.10+ on a computer or compatible terminal. No dependencies, API keys,
model downloads, or internet are needed for the default demo.

```sh
python --version
python -m agent run "calculate (12 + 8) * 3"
python -m agent run "remember Learn Python for 20 minutes"
python -m agent run "find Python"
python -m agent run "time"
```

On systems where the command is named `python3`, replace `python` with `python3`.
Run these commands from this repository's root. Memory defaults to
`.agent-data/memory.sqlite3`. Use `--db PATH` **before** the subcommand to choose another
installation's database. It is local plaintext; do not store secrets here.

### Open the liquid-glass local interface

```sh
python -m agent web
# Open http://127.0.0.1:8765 in a browser on that same computer.
# Ctrl+C in the terminal stops the server.
```

The visual workspace has translucent water-drop depth, soft lighting, glass edge
highlights on panels/fields/controls and fluid tap feedback. It uses system fonts,
readable text, visible keyboard focus and reduced-motion/high-contrast preferences.
It works without a build tool, external fonts, JavaScript packages or network service.

Try **Preview steps**, **Run locally**, **Remember**, **Find note**, **UTC time** or
**Prepare draft**. Review, revise, reject and approve exact drafts in the sidebar;
approval still means **not sent**. Explicit-folder text search is available on
supported POSIX systems. Unsupported social, voice and device features are labeled,
not represented by pretend working buttons.

The server is bound to `127.0.0.1`, not your network. A phone cannot connect to this
computer's localhost: Android here means a responsive browser layout, not an APK,
deployment, phone file access or installation. Keep that security boundary. It is
not a production/multi-user service. See [local UI guide and security limits](docs/LOCAL_UI.md).

### Inspect before you run

```sh
python -m agent plan "goal: calculate 12 * 3; remember Practice Python; draft friend@example.test: Ready"
python -m agent files "approval" --root ./docs
```

`plan` previews the deterministic demo steps and risk labels without executing tools,
opening memory, contacting a model or creating an approval. A later `run` validates
again; a preview is not authorization. No `--provider` is available for `plan`.

`files` searches eligible text files only in an explicitly supplied directory, returning
bounded matching lines. It does not use a model, write/index files or open the memory
database. Hidden/sensitive-named, binary and oversized files are skipped; a no-match
result covers only the eligible scanned files. The safe no-follow implementation is
Linux-tested and fails closed on unsupported OS primitives; it is not a secret detector
or a security sandbox. See [MYRA review and exact limits](docs/MYRA_REVIEW.md).

### One goal, safe work first, final review last

```sh
python -m agent run "goal: calculate 12 * 3; remember Practice Python; find Python; draft friend@example.test: Ready to discuss the project"
python -m agent pending
```

The demo uses simple commands and semicolon-separated `goal:` steps, not general
natural-language reasoning. It completes the three safe steps, then saves the exact
recipient/message for review. It does not ask permission for each harmless step.
The example address is fictional; there is no messaging connection.

Copy the `proposal_id` from the displayed result, inspect the complete action, then:

```sh
python -m agent approve PROPOSAL_ID
# Returns approved_not_sent and sent: false. Nothing leaves this computer.
```

To change or discard a draft:

```sh
python -m agent revise PROPOSAL_ID --recipient "friend@example.test" --text "Revised draft"
# New proposal ID; the old one and any old approval are superseded.
python -m agent reject NEW_PROPOSAL_ID
```

Pending reviews expire after 15 minutes. Approval is single-use, bound to the exact
stored payload/hash and cannot be supplied by a model. There is no background sender,
scheduler, device control, autonomous shell, deployment, or payment handler.

## What's actually included?

| Component | Working now | Not implied |
|---|---|---|
| Brain | Deterministic offline planner; strict JSON model-plan validation | Human-level reasoning or unrestricted goal solving |
| Agent loop | Up to 4 steps; safe preparation runs automatically; side-effect-free offline plan preview | Infinite autonomy, retries, cross-step model replanning |
| Memory | Persistent local SQLite notes and review audit | Encrypted vault, semantic search, cloud sync |
| Connections | Explicit allowlisted tool registry; separate owner-rooted local text-search CLI | Model-selected filesystem access or live email, calendar, browser, WhatsApp or bank access |
| Final review | Exact message draft, expiry, single use, edit invalidation | Sending a message after approval |
| Offline | Complete demo works without a model or network | A downloaded LLM bundled in this repo |
| Local LLM | Optional Ollama-style loopback adapter, mocked tests | Real model tested or installed on your device |
| Cloud | Optional OpenAI chat-completions adapter, mocked tests | A deployed service, free usage, or tested account integration |

## Optional local model: offline after setup

Install a suitable local model runtime and download a model separately, while online.
Then start its server, set `LOCAL_AGENT_MODEL` to the installed model name, and run:

```sh
# Linux/macOS shell; PowerShell users can set the equivalent $env: variables.
export LOCAL_AGENT_MODEL="YOUR_INSTALLED_MODEL"
python -m agent run "Find my Python notes and prepare a short message to friend@example.test saying I will practise" --provider local
```

Default endpoint: `http://127.0.0.1:11434/api/chat`. Only loopback HTTP origins are accepted.
An actual model/runtime has **not** been run here. Small models may return unsupported
or invalid plans. They cannot gain new tools by requesting them. No automatic fallback
to cloud occurs. See [operating modes](docs/MODES.md).

## Optional cloud planner: deliberate opt-in

Cloud mode sends **the current request and tool-policy prompt** to OpenAI, not the saved
notes or tool results. Never put secrets in the request. Provider processing/retention
terms apply. You supply an API account, a compatible model name and any associated
charges; no paid calls were made while creating this project.

```sh
export OPENAI_API_KEY="SET_THIS_PRIVATELY_IN_YOUR_SHELL"
export CLOUD_AGENT_MODEL="YOUR_COMPATIBLE_MODEL"
python -m agent run "Calculate 12 times 3" --provider cloud
```

Only models supporting Chat Completions JSON mode and `max_completion_tokens` work with
this optional adapter. Compatibility is not guaranteed for every model or account.
There is no automatic `.env` loader. `.env.example` lists settings without credentials.
Never paste a real key into code, commits, issues, or this README.

## Tests

```sh
python -m unittest discover -s tests -v
```

Optional local transport fixtures (ephemeral loopback ports only, no real providers):

```sh
python -W error::ResourceWarning -m unittest discover -s tests/integration -v
```

These are separate from the default network-free unit suite. They exercise urllib transport,
not a live cloud account or installed local model. The [comparison record](docs/OPEN_SOURCE_REVIEW.md)
explains the boundary and the reproduced error-handling fix.

The checked result and test scope are in [verification](docs/VERIFICATION.md).
Tests cover local execution, approval boundaries, exact payloads, edits, expiry,
malicious/invalid plans, bounded calculator inputs, and mocked provider protocols.
They do not establish production security, real-model accuracy, or Android compatibility.

## Read and build next

The [staged capability roadmap](docs/ROADMAP.md) covers the proposed chat/voice, study,
media, social/messaging, device and background modules, with explicit status and safety
gates. They are plans, not enabled integrations or a native app. The next small priority
is [provider transport verification (issue #2)](https://github.com/himangshurajg-bit/Personal-agentic-ai/issues/2),
before expanding external execution. The first isolated transport tests are now in place;
live-model verification is still pending. See the [open-source comparison and change](docs/OPEN_SOURCE_REVIEW.md).

- [Architecture / brain and work flow](docs/ARCHITECTURE.md)
- [Connections and capability roadmap](docs/CONNECTIONS.md)
- [Cloud, local and on-device modes](docs/MODES.md)
- [Security model and limits](SECURITY.md)

Optional beginner coding exercise (separate from the next maintenance priority): add a
read-only unit-conversion tool, register its risk and schema, and write tests before enabling it. Keep side-effecting integrations out
until they have a real permission and receipt design.

## Feature comparison notes

- [MYRA implementation/provenance review](docs/MYRA_REVIEW.md): why local search was independently written rather than pasting conflicting-license/compiled code.
- [Leading agent source/license comparison](docs/LEADING_AGENTS_REVIEW.md): bounded execution, visible plans and inspect-before-execute design without heavy framework imports.
