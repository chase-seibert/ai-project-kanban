# Architecture

## Implemented September 29, 2026

- `Sources/StageChaseCore/Domain.swift`: Sendable models and a pure command
  reducer. Independent project UUIDs, optimistic task revisions, durable runs.
  Confirmed automated moves create one run in the same transaction; moving to
  the current stage is a no-op. Reads never start agents. Active tasks cannot be
  edited/deleted/moved until stopped.
- `Sources/StageChaseCore/Repository.swift`: actor-owned SwiftData/SQLite.
  Versioned schema V1 stores independently addressable project/task/run/event
  records. Only changed entities are encoded and looked up by unique key; saves
  are transactional. The UI reads an in-memory library. Initial load currently
  loads all history; pagination remains a future scaling improvement.
- `Sources/StageChaseUI/`: observable app model, board, task detail, project forms,
  activity, and settings. New Project and Edit Project are distinct routes.
  Model configuration is a global Mac preference with optional project/task
  overrides; queued runs save the resolved model, effort, policy, and source.
- `Apps/StageChaseMac/`: native scene/commands, `AgentConnection` protocol,
  JSONL `CodexConnection`, and `CodexRunner` coordinator.
- `Apps/StageChasePhone/`: iPhone scene using the shared UI and repository.
- `Tests/`: reducer/persistence regressions and an offline process-level
  app-server fixture for progress, completion, blocked work, approvals, and stop.

Xcode synchronized source groups compile shared files directly into each app.
SwiftPM exposes StageChaseCore for tests. App targets do not import it separately.

## Runner lifecycle

Confirmed user action → catalog refresh and model resolution → atomic task/run
write including the exact model and reasoning effort → serial runner → persisted
session ID → Codex turn with explicit model/effort → serialized public
events/approvals → verified outcome → Planned or Review. Tasks are never
automatically marked complete.

Model precedence is task override, project override, then the Mac's global
StageChase preference. The built-in default is Latest Luna with High reasoning.
Latest Luna resolves from visible stable Luna IDs in the connected app-server
catalog using numeric version ordering. Unsupported efforts and ambiguous or
missing choices fail visibly. Model discovery uses `model/list` and never starts
a turn. Confirmed runs freeze the concrete model and effort; settings edits
affect only future runs. Retry resumes the saved run configuration. A legacy
run without a model snapshot asks for explicit confirmation before adopting a
choice. The global preference is local to this Mac and is not part of library
export/restore; project/task overrides and run snapshots are included.

Planning writes `to-do/<task UUID>.md`. Implementation verifies the plan, then
uses a clean checkout or a detached HEAD worktree under Application Support/
StageChase/Worktrees when the checkout is dirty. Only the approved plan is copied;
other uncommitted changes stay in the original checkout. The working folder is
recorded and shown. Worktrees are retained, never auto-deleted.

After restart, active/queued runs become Interrupted and require explicit retry.
Retry preserves run/session identity and working folder. Exactly-once execution
across a crash and remote service cannot be promised: inspect the session before
retrying an interrupted operation. Failure pauses the queue.

The app starts a dedicated stdio app-server, not the desktop's private database.
Requests time out, disconnects surface errors, and Stop closes the owned process.
The runner uses the selected model from the StageChase snapshot. Protocol source:
[OpenAI app-server](https://learn.chatgpt.com/docs/app-server); the installed CLI's
generated JSON schema was checked for exact request spellings.

## Migration and recovery

Prototype JSON is decoded/validated before import. Project/task IDs, folders,
content, stages, completion, and revisions survive. Original JSON and a backup
remain intact, including legacy history not shown in the new timeline. Migration
leaves automation off. A metadata record prevents repeated import. Corrupt data
fails closed. Export/empty-library restore is tested; restore disables automation
and interrupts imported active runs.

## Not implemented

Authenticated Mac API, Tailscale pairing, Keychain pairing credentials, iPhone
offline outbox, and synchronization remain separate work. Phone actions do not
reach the Mac. Project archival, multi-process writers, history pagination, and
rich interactive Codex questions are also outside the implemented surface.
