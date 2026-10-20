# Capability roadmap: personal agent, bounded autonomy

This is a staged design, not a list of features that already work. The aim is a helpful
personal assistant that understands a goal, prepares useful work independently, and asks
for exact approval before consequential actions. It cannot do everything or control every
app. Platform access, device support, user permissions and tested implementations decide
what is possible. There is no release date or continuous-operation guarantee.

## Status at this documentation update

| Status | Capability and evidence |
|---|---|
| Implemented and locally tested | Python CLI; deterministic command planner; maximum four validated steps; calculator, UTC clock, SQLite notes/search; exact message-draft review with expiry, single-use approval and edit invalidation. Independent bounded local-file search, side-effect-free plan preview and a loopback-only liquid-glass browser UI are also implemented. The 102-test unit suite passes. |
| Implemented adapters; mocked models, loopback-tested transport | Optional loopback local-model and cloud planner adapters. Nine isolated loopback transport tests pass; no real model or live account compatibility is established. Explicit cloud selection is required; no automatic cloud fallback. |
| Proposed, not implemented | Conversational chat/voice, study tutor, web research, connected social/messaging services, media editing/generation, camera, device/app control, gaming help, coding workspace execution, native mobile UI, scheduler, cloud hosting and sync. |

`approve` still returns `approved_not_sent`. No message, post, payment, destructive action
or access change can execute. A local browser UI and a separate limited native Android test app are included (see `android/README.md`); no model download or always-running service
is included. See [local UI](LOCAL_UI.md) for setup and limitations. Wabi's own connected accounts and device access are **not** inherited here.
See [verification](VERIFICATION.md), [architecture](ARCHITECTURE.md),
[connections](CONNECTIONS.md), [modes](MODES.md) and [security](../SECURITY.md).

## Rules that must survive every stage

- Safe, reversible preparation within the owner's authorized task should run without
  repeated questions. Missing essential personal decisions should be asked, never invented.
- Access is scoped to a specific owner, account, purpose and capability. A connected
  account is not blanket action permission; never read another person's account without
  their permission. Treat messages, web pages and model suggestions as data, not commands.
- Before sending a message, publishing a post/Story/video, making a purchase, deleting
  data or changing access, show the exact account/destination, content or media version,
  privacy/audience, cost/limits and timing for owner review. An edit needs new approval.
  Device prompts and explicit consent for sensitive data access still apply even to reads.
- Approval is not success. Require durable execution state, idempotency, receipt checking
  and reconciliation of unknown outcomes before retries. Default external execution stays
  disabled until these controls pass tests for the particular integration.
- Offer clear pause, cancel, disconnect and permission-revocation controls. Stopping a job
  must prevent later dispatch, but cannot undo a message already sent; show that distinction.
- Keep secrets out of notes, prompts, logs, issues and commits. Use an OS keystore/secret
  manager before connecting accounts. Minimize data; cloud processing must be explicit.
- Natural conversation and a synthetic voice must disclose that this is AI, not claim to
  be human or impersonate someone. Use a licensed voice or an explicitly authorized voice;
  no unconsented cloning, hidden recording, surveillance or security bypass.

## Stage 1 — verify the existing brain before widening its powers

**Next small improvement: [issue #2 — provider integration verification](https://github.com/himangshurajg-bit/Personal-agentic-ai/issues/2).**
The first seven isolated HTTP fixture tests and protocol-error fix are implemented; see
[the comparison record](OPEN_SOURCE_REVIEW.md). This advances #2 without completing its
opt-in live-model work. Continue verifying existing transport before adding a new service.
Test request encoding, malformed/oversized replies, redirect refusal, timeouts and sanitized
failures. Keep ordinary tests secret-free and independent of live internet/providers.
A local fixture may bind only loopback during explicit integration tests; distinguish those
from the default offline unit suite. Live-model checks must be separate, opt-in and report
missing setup as a skip, not success. No paid cloud calls as a default test dependency.

Acceptance: existing unit tests still pass; new tests fail against a reproduced transport
defect or validate a documented boundary; results identify mocks, fixtures and any actual
live verification separately. Do not add a feature just to create a daily commit.

## Stage 2 — conversational help and low-risk preparation

Introduce one small module at a time, with bounded plans, source tracking and test fixtures.
None of these modules currently exists:

| Proposed module | First useful scope | Acceptance gate |
|---|---|---|
| Natural chat and study help | Clarify a missing essential, explain a lesson, make a practice quiz and verify answers with approved materials | Distinguish sourced facts from guesses; test factual examples, refusal to invent user facts, prompt injection, and cancellation. Not an exam-cheating tool. |
| Speech | Push-to-talk transcription and clearly synthetic text-to-speech | Visible recording state, explicit mic permission, immediate stop, text fallback, and documented local/cloud processing. No always-listening default. |
| Coding | Suggest a patch to a selected project; show diff and test output | Preserve unrelated files; sandbox any future execution with resource/network limits. No unrestricted shell or automatic dependency/credential use. Review before public upload or other external effects. |
| Photo/video creation and editing | Work on selected files; crop/edit, storyboard, captions and local export before publishing | Preserve originals, identify generated content, validate output, honor media/voice rights and expose preview. Processing may need hardware or explicit paid-provider approval. |
| Camera / photography | Open a user-invoked capture flow and return the chosen result | In-context permission or platform capture UI, visible capture state, no covert/background camera activation, cancel without capture. |
| Gaming assistance | Guides, strategies, accessible explanations and practice tools | Respect game rules; no anti-cheat bypass, credential theft, competitive cheating or unauthorized game automation. |

An LLM is a planner/language interface, not authority. Offline chat/voice/media require
separate compatible models/runtimes, downloads, RAM/storage and CPU/GPU support. Benchmark
battery, heat, latency and quality on actual supported devices before making claims. If a
module is unavailable offline, say so; never silently upload private input to the cloud.

## Stage 3 — one authorized connection, then one reviewed action

Read-only access and draft preparation come before dispatch. Reuse
[issue #3 — approval-bound external executor](https://github.com/himangshurajg-bit/Personal-agentic-ai/issues/3)
for the execution design; do not create a generic catch-all app-control executor.
Start with a fake provider, authenticated owner/account binding, exact media/content hashes,
expiry, duplicate/unknown-outcome tests and clear attempted/confirmed/failed states.

Future integrations need their own compatibility check and consent, not a promise of
access to all apps:

- **Instagram posts, Reels and Stories:** prepare media/captions first. The Instagram API
  with Instagram Login is for professional business/creator accounts, not unrestricted
  consumer-account control. Check the chosen API's publishing formats, account eligibility,
  permissions/app review and limits before implementation; support for one format does not
  establish another. Approve exact media, caption, target account, audience and schedule.
- **YouTube:** a future upload needs the channel owner's OAuth authorization and appropriate
  scope. Validate media, quota/availability, privacy, audience settings and required disclosures.
  Explicitly set privacy rather than relying on a default. Preview before upload/publication;
  record provider receipt and processing status, not just an accepted HTTP request.
- **WhatsApp and other messages:** the official WhatsApp Cloud API is a business platform
  requiring business resources; it is not general access to someone's personal chat history.
  Identify a supported, authorized integration first. Other services require their own scoped
  authentication and capability checks. No promise to read/control every message, no account
  scraping or session theft. Prepare replies automatically only within granted scope; send
  exact owner-reviewed content once, and handle unavailable messages honestly.

Rate limits, eligibility, account restrictions, policy changes and service outages can make
an operation unavailable. Detect them, preserve prepared work and explain the supported
next step. Do not evade restrictions through hidden UI automation or alternate accounts.

## Stage 4 — native device bridge and bounded background work

**Device-control features remain design only. The separate native Android offline test app does not implement these controls, and this roadmap creates no deployment.**

- Launch supported app activities through documented Android intents/deep links; handle
  missing apps and OS restrictions. Opening an app is not permission to control its UI,
  read its private storage, or send/post within it. Arbitrary cross-app control, lock-screen
  bypass and exploiting accessibility permissions are not a substitute for supported APIs.
- Ask for only the permissions a specific requested feature needs. Re-check grants at use,
  degrade gracefully on denial/revocation, and use selected-file/photo access when possible.
  Screen capture, notification/message access, microphone and camera need separate purpose-
  appropriate consent and OS flows; installation alone grants none of them.
- Use platform scheduling (usually WorkManager for persistent deferrable Android work),
  constraints, bounded retries and persistent checkpoints. Android restricts background
  execution; in-memory work can stop when the process/lifecycle ends. Foreground services
  have eligibility/start/type rules and user-visible notification requirements. A cloud job
  cannot bypass phone permissions, offline state, battery controls or app restrictions.
- Provide a visible queue and pause/stop controls; test process death, reboot, lost network,
  revoked permissions, cancelled tasks and stale approvals. No exact-time or 24/7 guarantee.
  Background execution must never turn an old draft approval into a new commitment.
- A future cloud coordinator needs owner authentication, isolation, encrypted storage,
  secure token handling, cost caps, revocation and local/cloud data minimization before
  hosting. No public port, paid deployment or synchronization is enabled by this document.

Acceptance: start with one allowlisted local action and one cancellable queued task on a
named tested Android version/device. Verify stop/revoke and no dispatch after cancellation.
Publish measured compatibility/limitations; do not claim all phones, all apps or iOS parity.

## Work organization and evidence

1. Complete the isolated transport portion of #2 first; optional live verification remains
   opt-in, not a reason to demand keys or incur charges.
2. Develop #3 against a fake provider before selecting any real consequential integration.
3. Choose one low-risk module or native prototype only after its prerequisites are tested.
   Split out a new issue when work has a concrete small outcome and acceptance tests, not
   one speculative issue for every desired feature.

Mark a capability implemented only after code, relevant tests and observed results exist.
Record actual defects and limits, not fictional failures. Preserve existing README/license,
review history and working features. A mock success, documented plan, granted permission,
scheduled job or approved draft is not completed external work.

## Official platform references

Reviewed for the constraints above on 20 October 2026. Policies can change; re-check the
selected endpoint/platform version before implementation. These links are evidence for
design limits, not evidence that this project is connected, certified or deployed.

- [Android background tasks](https://developer.android.com/develop/background-work/background-tasks)
- [Android common intents](https://developer.android.com/guide/components/intents-common)
- [Android runtime permissions](https://developer.android.com/training/permissions/requesting)
- [Instagram API with Instagram Login](https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login/)
- [WhatsApp Cloud API overview](https://developers.facebook.com/docs/whatsapp/cloud-api/overview)
- [YouTube video upload API](https://developers.google.com/youtube/v3/docs/videos/insert)
