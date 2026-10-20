# Cloud, offline and on-device

## Offline demo — tested here

A Python 3.10+ interpreter and these source files are enough. The demo planner, arithmetic,
clock, notes, drafts, review and tests require no external packages or network. This is a
useful orchestration demo, not a language model and not a claim of general AI intelligence.
The program writes its own local SQLite state; it does not browse arbitrary device files.

## Local language model — optional, not tested with a real model

The adapter expects an independently installed local runtime and downloaded compatible
model. First installation/model download needs internet. Thereafter inference may work
offline if all required model files are present. Hardware RAM, available storage, CPU/GPU,
model size, battery and heat determine usability. No universal device-performance claims
are made. The agent does not install a runtime or download models for you.

Local requests only go to an HTTP loopback origin; redirects and inherited proxies are
disabled. The local model process can itself have telemetry/network behavior outside this
program's controls. Audit its settings before calling the whole system fully offline.
The planner receives only the current request, not the SQLite memory. It can request a
local search tool whose results are displayed locally, without model replanning.

## Cloud planner — optional, privacy opt-in

The adapter calls OpenAI only when `--provider cloud` is selected, with both configuration
variables present. The current request and static tool schema/policy leave the device.
Existing notes, audit history and tool results are not attached. A user can still disclose
private information in the request itself. Understand provider terms, retention and
billing; this repository cannot promise zero retention or free inference. There is no
silent cloud fallback. No live API call was made while building or testing this repo.

## Cloud-hosted assistant — design only

The CLI could run on a self-managed server as ordinary Python, but no cloud service has
been deployed or tested. It is not an internet-facing multi-user server. Before hosting,
add authentication, account isolation, encrypted storage, secrets management, TLS,
rate/cost limits, backups, endpoint security and approval delivery bound to the owner.
Do not expose this SQLite-backed demo through a public port.

## Android/iPhone/on-device apps — not implemented

No native mobile app or background service is included, and nothing has been installed
or tested on the owner's phone. A compatible Python terminal on Android might run the
demo, but that is not verified compatibility, a native assistant, or permission to read
phone messages, contacts, microphone, screen or sensors. iOS execution/background limits
also apply. A future native shell would need platform permissions, secure storage and
separate tested bindings. Local-model hardware support is device-specific.

## Suggested split for a future hybrid system

Keep private memory, permissions, review and final execution local. Use a local planner
when feasible; send only deliberately minimized requests to an opt-in cloud planner.
Give each model the same narrow registry, never account tokens. Persist exact task state
locally and reconcile external outcomes before retries. These are architectural goals,
not currently deployed capabilities.
