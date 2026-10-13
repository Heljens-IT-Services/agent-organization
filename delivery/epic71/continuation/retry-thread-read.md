# Read-only retry thread observation: epic71-index-integration

Observed at: 2026-10-13T07:19:28Z

## Exact RPC result

- Request: `thread/read`, `threadId=01a13414-0085-77a2-a5db-9f0c312cb4dc`, `includeTurns=true`.
- Response: JSON-RPC id `2`, result returned; the complete response body is preserved in `retry-thread-read.json`.
- Matching turn: `01a13414-035d-7ec1-ba11-3d2309fcc8e2`.
- Exact server turn status: `interrupted`.
- Exact turn error: `null`.
- `completedAt`: `null`; `durationMs`: `null`.
- Returned turn item count: 8 (agentMessage=2, commandExecution=3, reasoning=2, userMessage=1).

## Transport and boundaries

A separate local `codex app-server --stdio` process was used. Requests sent were only `initialize`, `initialized`, and this authorized `thread/read`. No thread or turn was started, resumed, interrupted, or modified. The helper lived under its own temporary subdirectory. Its appserver process was closed after receiving the response.

The server reports this turn as `interrupted`. This is the exact terminal status returned by `thread/read`; it does not establish why interruption occurred, nor does it prove product behavior or acceptance. The original retry result path was not written or replaced. No source, Git, index, test, validator, browser, native UI, or other process was touched.

## Sources

- Prior correctly bound observation: `retry-observation.md/json` in this package.
- Direct response: `retry-thread-read.json` in this package, including the complete returned thread and matching turn.
- Read-only transport reference: `C:/Users/Tom-OliverMarek/AppData/Local/Temp/agent-org-filereplace-repair/worktree/scripts/delegation/Start-DelegatedCodexTask.ps1`, lines 611–736. Its general runner continues into `thread/start` and `turn/start`; it was not executed.
