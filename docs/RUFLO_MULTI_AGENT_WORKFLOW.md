# Ruflo-inspired bounded workflow

This is an original, small adaptation inspired by Ruflo’s role-based orchestration ideas. Ruflo is an MIT-licensed Node/TypeScript harness; this branch does not copy its code or runtime. Its Claude Code/Codex team orchestration, vector memory and federation do not drop into the Flutter Android client.

## What the first version does

From Skills & actions, the owner can enter one task and review the request, configured OpenAI-compatible endpoint host and model before starting. After approval, the app makes four sequential requests to that same configured model: Planner, Specialist, Reviewer and Synthesizer. Each later pass receives the task and the earlier model outputs as untrusted text. The result remains on the screen until it is left; it is not added to chat or saved by the app.

This is a bounded multi-role workflow, not a parallel swarm, independent models, durable agent memory or a background runner. Offline Gemma and the private FastAPI service are not supported in this first version. The workflow has no tool definitions and no code path for MCP invocation or external actions. It gets no chat history, saved memories, files, accounts or device data. It does not execute its suggestions.

## Review, privacy and limits

The owner must tap through a review that describes all four passes and shows the exact task. The first request sends the task plus fixed role instructions; subsequent requests also include prior pass output. The configured API key is sent only as the provider’s authorization header, not in the prompt. Provider API use may incur account charges or provider retention. There are no automatic retries. The owner can stop the run; an already-sent request may still finish at the provider. An individual pass is capped at 6,000 response characters, and a task at 4,000 characters. Provider output is unverified text; the workflow does not browse or validate factual claims.

A future genuinely distributed or heterogeneous agent team would need a separate architecture for provider selection, bounded task delegation, shared-data minimization, cancellation, trust boundaries and per-action review. This implementation does not claim that larger capability.

## Tests

`mobile/test/multi_agent_workflow_test.dart` uses only mock HTTP clients. It verifies explicit approval, refusal of offline/private-service modes, endpoint/task validation before transmission, four ordered calls with maximum concurrency one, no tool definitions or history in requests, prior outputs marked untrusted, and no retry or provider-body leakage on failure. UI tests verify the entry point and disabled initial state when an online provider is not configured. No live provider request is part of the tests.
