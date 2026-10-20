# Leading-agent comparison and side-effect-free plan preview

Reviewed 20 October 2026 for the owner's request to learn from established, highly
starred agent repositories. This is a focused source/license comparison, not an audit
or an exhaustive GitHub ranking. Stars are a changeable popularity signal, not evidence
of quality, safety or suitability. Upstream frameworks were read, not installed, run or
added as dependencies.

## Candidate snapshot

GitHub API `stargazers_count` at review time:

| Repository | Stars | License evidence | Relevant observation and decision |
|---|---:|---|---|
| [Microsoft AutoGen](https://github.com/microsoft/autogen) | 61,496 | Code: MIT in `LICENSE-CODE`; top-level `LICENSE` is CC-BY-4.0, so a single repository SPDX label is insufficient | Explicit message-count termination is useful; this starter already enforces a strict four-step cap. Do not add multi-agent conversations merely to match popularity. |
| [CrewAI](https://github.com/crewAIInc/crewAI) | 59,909 | MIT | `PlanningConfig` exposes planning-step and refinement/replanning limits. Retain this starter's smaller fixed cap; expose a validated plan before local execution instead of adding iterative LLM crews. |
| [LangGraph](https://github.com/langchain-ai/langgraph) | 43,572 | MIT | Its interrupt mechanism surfaces information to a person and supports checkpointed resumption. Make upcoming steps/risk visible here, but do not import graph checkpoint/replay semantics or treat a preview as authorization. |
| [OpenAI Agents SDK for Python](https://github.com/openai/openai-agents-python) | 30,168 | MIT | Reuse today's [source/model-test review](OPEN_SOURCE_REVIEW.md): transport-boundary tests and classified errors already informed the existing provider fix and loopback fixtures. No duplicate implementation. |
| [Pydantic AI](https://github.com/pydantic/pydantic-ai) | 20,752 | MIT | Reuse today's [source/error-mapping review](OPEN_SOURCE_REVIEW.md). Keep this starter's privacy-preserving error handling and dependency-free validation. No wholesale SDK import. |

These are selected established candidates, not a claim that they are the five most
starred projects or that their current defaults are safe for this application.

## Pinned implementation and license evidence

### AutoGen

Inspected commit `004749e6b7102c8fd317b9b1499ce5807223c278`:

- [`MaxMessageTermination`](https://github.com/microsoft/autogen/blob/004749e6b7102c8fd317b9b1499ce5807223c278/python/packages/autogen-agentchat/src/autogen_agentchat/conditions/_terminations.py) counts chat messages (optionally agent events), returns a stop message at the configured threshold, refuses another call after termination, and supports reset.
- [`test_max_message_termination`](https://github.com/microsoft/autogen/blob/004749e6b7102c8fd317b9b1499ce5807223c278/python/packages/autogen-agentchat/tests/test_termination_condition.py) checks empty input, counting and event inclusion. This is not an exact-action approval mechanism.
- [Code license](https://github.com/microsoft/autogen/blob/004749e6b7102c8fd317b9b1499ce5807223c278/LICENSE-CODE): MIT, Microsoft copyright; [top-level license](https://github.com/microsoft/autogen/blob/004749e6b7102c8fd317b9b1499ce5807223c278/LICENSE): CC-BY-4.0. No code or documentation excerpts are incorporated into this implementation.

### CrewAI

Inspected commit `4f4573706ea4afee6c4da4c31cfb9622a4495ab7`:

- [`PlanningConfig`](https://github.com/crewAIInc/crewAI/blob/4f4573706ea4afee6c4da4c31cfb9622a4495ab7/lib/crewai/src/crewai/agent/planning_config.py) declares `max_steps` (default 20, at least 1), `max_attempts` (optional), and `max_replans` (default 3). Inspecting configuration alone is not proof that every model response obeys it.
- [MIT license](https://github.com/crewAIInc/crewAI/blob/4f4573706ea4afee6c4da4c31cfb9622a4495ab7/LICENSE) read before considering reuse.
- We retain whole-plan validation and reject more than four steps before effects; no model-generated planning loop or refinement dependency is introduced.

### LangGraph

Inspected commit `a24fc97778fca67cfac4cd3fc63e508ee1d29f59`:

- [`interrupt` implementation/interface](https://github.com/langchain-ai/langgraph/blob/a24fc97778fca67cfac4cd3fc63e508ee1d29f59/libs/langgraph/langgraph/types.py) raises a resumable graph interruption, surfaces a value, requires a checkpointer, and restarts the node on resume. That re-execution behavior needs careful handling around side effects; it is not permission to retry an uncertain external action.
- [Interruption tests](https://github.com/langchain-ai/langgraph/blob/a24fc97778fca67cfac4cd3fc63e508ee1d29f59/libs/langgraph/tests/test_interruption.py) inspect interrupt state and resume values, including response-schema handling.
- [MIT license](https://github.com/langchain-ai/langgraph/blob/a24fc97778fca67cfac4cd3fc63e508ee1d29f59/LICENSE) read. No graph runtime, persistent checkpoint, source snippet or dependency is imported.

OpenAI's current inspected head remained `64cd5dfc5a1579870dcbed0ea42b27aa84033fee`.
Pydantic AI's metadata/tree was refreshed at `19b1eafbbef19c8891666576c438ae9e0d90ef16`;
its earlier actual model/error implementation review was at
`b40096c4c91e4db361ee3f23b0e3f6b85569faa2`. No claim of re-auditing every intervening
Pydantic change is made. The existing comparison retains those exact earlier sources.

## New independent implementation: `plan`

```sh
python -m agent plan "goal: calculate 12 * 3; remember Practice Python; draft friend@example.test: Ready"
```

This prints the validated deterministic demo steps, positions, existing registry risk
classes and whether each draft requires exact review. It does not execute arithmetic,
read the clock, read/write memory, open/create a database, contact a model, create a
proposal, approve anything or send a message. It has no `--provider` switch. The whole
plan is validated using the same validation as `run`, including the four-step cap.
Unsupported demo text is labeled `unsupported`, not falsely represented as a useful plan.

This is **not** a port of a LangGraph interrupt, CrewAI planner or AutoGen termination
class. It is a small independently written inspect-before-execute interface suited to
this existing deterministic CLI. It is not general natural-language reasoning. Validation
checks argument shape, not whether a later calculation/file/database operation will succeed.
`run` plans and validates again: the preview is not a replay token or authorization, and
external drafts still require their exact existing expiring review. No new automatic
execution or uncertain-outcome retry is enabled.

No third-party source, tests, assets or dependencies were copied. All new runtime/tests
are standard-library code written for this project. The target MIT LICENSE is unchanged;
the pinned links credit the compared designs. Future substantial copying must preserve
its applicable notices and any component-specific obligations.

See [MYRA_REVIEW.md](MYRA_REVIEW.md) for the independently written opt-in local file
search and the MYRA licensing/provenance limitation, and [VERIFICATION.md](VERIFICATION.md)
for the executed test receipts. No framework's entire suite, live model or Android device
was tested by this review.
