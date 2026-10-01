# Architecture

## Implemented September 29, 2026

- `Sources/StageChaseCore/Domain.swift`: Sendable models and a pure command
  reducer. Independent project UUIDs, optimistic task revisions, durable runs.
  Confirmed automated moves create one run in the same transaction; moving to
  the current stage is a no-op. Reads never start agents. Tasks can move between
  columns while Codex runs; stage placement and completion are user-controlled.
- `Sources/StageChaseCore/Repository.swift`: actor-owned SwiftData/SQLite.
  Versioned schema V1 stores independently addressable project/task/run/event
  records. Only changed entities are encoded and looked up by unique key; saves
  are transactional. The UI reads an in-memory library. Initial load currently
  loads all history; pagination remains a future scaling improvement.
- `Sources/StageChaseUI/`: observable app model, board, task detail, project forms,
  activity, and settings. Task detail shows the latest run; Activity lists only
  active runs. Neither surface renders chronological event feeds, while activity
  records remain persisted. Mac opens saved Codex thread links directly. iPhone
  tries the same URL and offers a Mac continuation message plus session-ID copy
  when no handler accepts it. New Project and Edit Project are distinct routes.
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

With automatic invocation enabled globally and for the project, a confirmed
move to Next or Implementation resolves model settings, atomically writes the
task/run state, then starts a serial Codex turn. Public events and approvals
produce a verified run outcome; the task column never changes automatically.
Tasks are never automatically marked complete. With automatic invocation off,
task detail can prepare a manual Desktop handoff: StageChase saves task context,
opens a linked empty session, and copies the context without submitting a turn.
The user starts work in Codex Desktop. A user-initiated Refresh status reads the
linked session and updates only its run record.

The Mac app can expose an opt-in, loopback-only MCP server at
`Apps/StageChaseMac/MCPServer.swift`. It reads and mutates the same
`LibraryRepository` as the board; no second process opens the SQLite library.
Project/task reads are scoped by stable IDs. Create/move/complete writes use the
normal reducer, persist bounded operation receipts and advance the phone-sync
sequence in the same save. Existing-task updates require the current revision.
External session records have a distinct source; `begin_task`,
`report_task_update`, and `finish_task` only track work that Codex Desktop
already started. They store one bounded latest message on the task/run, never a
transcript or inferred thread ID. Restart marks an external active record stale
rather than interrupted or resumable by StageChase.
MCP stage moves pass no model configuration and never call `kickRunner()`,
regardless of automatic-invocation preferences. Stop the endpoint in Settings
to disconnect Codex Desktop; it binds to `127.0.0.1` and uses a per-install
secret path component. Task move and completion remain distinct.

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

The editable plan-format instruction is a bounded Mac-local `UserDefaults`
preference, separate from `Library` and run records. Missing or whitespace-only
text resolves to the built-in template. `CodexRunner.prompt` appends it only to
new planning turn input, under the fixed task, scope, approval, sandbox, and
structured-result requirements. It does not alter implementation prompts,
existing plan files, or an already-submitted turn; it is not an enforcement
boundary.

When a confirmed Mac action queues planning, the task stores its plan destination
in that same transaction. StageChase preserves an existing user-selected path;
otherwise it reserves `to-do/<lowercase task UUID>.md`. The planning prompt uses
that saved path, and retries reuse it. A path reservation does not mean the plan
exists: the planning run succeeds only after structured success and a readable,
non-whitespace file at the reserved destination. The task stays in its current
column. Mac Open plan and feedback controls require a readable file and are
available in any column. Phone stage moves do not reserve paths or enqueue work.

Implementation verifies the plan, then
uses a clean checkout or a detached HEAD worktree under Application Support/
StageChase/Worktrees when the checkout is dirty. Only the approved plan is copied;
other uncommitted changes stay in the original checkout. The working folder is
recorded and shown. Worktrees are retained, never auto-deleted.

## Plan feedback

Mac task detail appends typed or system-dictated feedback to a saved plan in any
task column. `PlanFileStore` resolves the Markdown target
inside its project folder, coordinates and serializes the append, retains the
original file bytes, and verifies the resulting file before reporting success.
Each append adds a `User feedback on the plan` heading followed by the raw text.
Failed writes keep the editor draft. This file action does not mutate the task,
create a run, or call the runner. Project plan paths are not part of phone sync;
the phone directs users to append feedback on Mac.

After restart, active/queued runs become Interrupted and require explicit retry.
Retry preserves run/session identity and working folder. Exactly-once execution
across a crash and remote service cannot be promised: inspect the session before
retrying an interrupted operation. Failure pauses the queue.

The app starts a dedicated stdio app-server, not the desktop's private database.
Requests time out, disconnects surface errors, and Stop closes the owned process.
Close Codex session can release a saved thread by interrupting its active turn
and waiting for the exact StageChase-owned process to exit. Other active work
blocks this action because the process can hold several threads. A close marks
unfinished work Interrupted while preserving its IDs, steps, and worktree; a
finished run keeps its saved outcome and summary. Close pauses queue draining
until a later confirmed stage action or Retry. Open in Codex is a separate
desktop deep link; continuation and result synchronization remain manual.
Shutdown uses a bounded asynchronous wait and reports timeout without claiming
release. Protocol source:
[OpenAI app-server](https://learn.chatgpt.com/docs/app-server); the installed CLI's
generated JSON schema was checked for exact request spellings.

## Experimental local Wi-Fi synchronization

`Sources/StageChaseCore/SyncProtocol.swift` defines versioned phone commands and
sanitized snapshots. Phone commands are a small allowlist (create/edit/move/
reorder) with expected task revisions; clients cannot submit runs, activity,
plan paths, project folders, rank values, or automation configuration. The Mac
`LibraryRepository` remains the only authoritative writer. It stores a library
identity, monotonic sequence, device high-water marks, and operation receipts in
the existing SwiftData metadata rows, committing accepted edits and receipts in
one save. A changed snapshot is returned when the phone cursor is stale; an
unchanged response avoids retransmitting the library every foreground poll.

The Mac app starts `NWListener` on port 47928 only after the user enables local
sync from Settings → Connection. That explicit choice is remembered, so the
listener restarts when the Mac app opens; disabling sync clears the choice. The
iPhone enters the Mac's local address and short-lived
pairing code; entering the code automatically registers the phone without
desktop confirmation. The code is a short-lived bearer credential, so anyone
who obtains it during its validity can pair. Random device keys and pairing
material are stored in Keychain. The framed TCP payloads use
AES-GCM authenticated encryption at the application layer. The transport is
limited to a trusted local Wi-Fi network; it is not HTTPS/TLS and is not
intended for public or untrusted networks. The phone's direct local-network use
is declared in its privacy usage string. Pair attempts, connection count, and
message size are bounded.

Both apps have a Connection view with current request state, last result,
pending count, saved endpoint, and a persistent, bounded exchange journal. The
journal records timestamps, direction, framed request/response byte counts,
elapsed time, endpoint, and outcome; it never records message bodies, task text,
or credentials. Since transport uses one short TCP connection per request,
phone status reports the most recent reachability check rather than a permanent
socket. The phone can update its saved Mac address without unpairing or dropping
queued changes.

The phone's Mac replica is stored in a separate non-recovering SwiftData store,
so loading remote runs does not interrupt them. Its independent on-device
library is preserved. Pending commands are stored in a private, bounded,
atomic outbox file and overlaid on the cached replica. Automatic foreground
refresh runs every three seconds by default and can be disabled in the phone's
Connection tab. Sync Now and board pull-to-refresh always perform an explicit
sync; with automatic sync disabled, phone edits remain queued until then.
Polling itself never invokes the runner. The Mac must be awake with StageChase
open. Phone completion, deletion, undo, project configuration, and Codex run
controls are hidden while paired. Phone stage moves do not include automation
configuration and never enqueue or invoke Codex. Automatic Codex confirmation
and manual Desktop handoff remain Mac-only.

This path is still experimental. Unit and build checks pass, but pairing and
task propagation have not yet been visibly verified between Mac and iPhone.
Do not describe it as supported until that acceptance is complete.

## Migration and recovery

Prototype JSON is decoded/validated before import. Project/task IDs, folders,
content, stages, completion, and revisions survive. Original JSON and a backup
remain intact, including legacy history not shown in the new timeline. Migration
leaves automation off. A metadata record prevents repeated import. Corrupt data
fails closed. Export/empty-library restore is tested; restore disables automation
and interrupts imported active runs.

## Not implemented or not yet verified

Visible device-level pairing, add/edit/move/order propagation, outage recovery,
and conflict resolution remain unverified. Phone-side automation confirmation
and dependent-command conflict resolution are not implemented. Tailscale,
HTTPS, public hosting, multi-user sync, multiple Macs, background delivery,
project archival, multi-process writers, history pagination, and rich
interactive Codex questions are outside this surface.
