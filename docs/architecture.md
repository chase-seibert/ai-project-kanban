# Architecture

## Implemented September 29, 2026

- `Sources/StageChaseCore/Domain.swift`: Sendable models and a pure command
  reducer. Independent project UUIDs, optimistic task revisions, durable runs.
  Confirmed automated moves create one run in the same transaction; moving to
  the current section is a no-op. Reads never start agents. Tasks can move
  between sections while Codex runs; section placement and completion are
  user-controlled. Persisted `WorkflowStage` remains as a compatibility field
  for older JSON payloads and MCP clients.
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
  Move and completion activity is tagged for unread badges; local read timestamps
  are tracked independently for each project and task on each device.
  Model configuration is a global Mac preference with optional project/task
  overrides; queued runs save the resolved model, effort, policy, and source.
- `Apps/StageChaseMac/`: one singleton `Window` scene for the board and its
  in-window sheets/inspectors, native commands, `AgentConnection` protocol,
  JSONL `CodexConnection`, and `CodexRunner` coordinator. The standard Settings
  command routes to the Settings sheet rather than a separate scene.
- `Apps/StageChasePhone/`: iPhone scene using the shared UI and repository.
- `Tests/`: reducer/persistence regressions and an offline process-level
  app-server fixture for progress, completion, blocked work, approvals, and stop.

Xcode synchronized source groups compile shared files directly into each app.
SwiftPM exposes StageChaseCore for tests. App targets do not import it separately.

## Runner lifecycle

With automatic invocation enabled globally and for the project, a confirmed
move to Planning or Implementing resolves model settings, atomically writes the
task/run state, then starts a serial Codex turn. Public events and approvals
produce a verified run outcome; the task section never changes automatically.
Planning completion sets Ready, implementation completion sets Review, and only
the user's explicit sign-off sets Done and the existing completion flag. With
automatic invocation off,
task detail offers a Launch Codex action using the generated prompt with
stable project/task IDs and a readable project-relative plan path when
available. Prompts start with the exact task title. Runner-created planning
sessions use `Plan: <task title>`; implementation and generic task handoff
sessions use `Code: <task title>`. Launch opens `codex://threads/new` with the project folder and
prompt without submitting a turn. That prompt directs Codex to move successful
implementation to Review through MCP after successful work, using the latest
revision, while preserving the current completion flag. Completion and
reopening are user actions in StageChase. Legacy
linked sessions can still be refreshed explicitly to update their run record.

## Consolidated sections and task status

`WorkItem.section` stores Inbox, Planning, or Implementing independently from
`WorkItem.status`. The status flow is Inbox/Triage → Planning → Ready → Building
→ Review → Done. Waiting and Error represent blocked or failed runs; Quota is
selected for quota-specific failure messages. Runner updates derive Building,
Waiting, Error, and Quota from `AgentRun`; a successful plan sets Ready, and a
successful implementation sets Review. Only an explicit user completion action
sets Done and the legacy `completed` flag. Waiting, Error, Quota, and Review sort
first within a section in that order, followed by priority and stable rank.
The shared board card renders one status capsule from an exhaustive
`TaskStatusBadgeStyle` mapping. Saved-plan details and Codex run outcomes remain
in task detail, with run history also in Activity, rather than appearing on cards.

Legacy `stage` values remain encoded for the local MCP and older phone clients:
Inbox maps to Inbox/Triage; Next maps to Planning/Planning; Planned maps to
Planning/Ready; Implementation maps to Implementing/Ready; Review maps to
Implementing/Review. Decoding old JSON payloads fills the new fields from this
mapping without changing task identity, revision, rank, completion, plan, or run
history. Sync snapshots carry optional section/status values so older snapshot
readers can ignore them and newer readers can map old snapshots. The Mac board
presents the sections as three side-by-side columns with independently
vertical-scrolling task lists; iPhone keeps the three sections horizontally paged.

Mac task detail also has a task-scoped Refresh action. It rereads the authoritative
SwiftData library without crash recovery or writes, then rechecks the attached
project-relative plan and explicitly reads an existing linked Codex thread when
available. The latest turn summary is stored on the run record; refresh does not
append duplicate activity events or change task stage/completion. Unsaved task
edits remain in the detail draft and are flagged as potentially stale. Missing
sessions, unreadable plans, and thread-read failures are reported while preserving
the last saved run/error state. Refresh is user-triggered and never starts,
retries, stops, or approves a Codex turn.

Mac task detail also has a separate plan handoff. `PlanHandoffPrompt` builds
plan-only instructions for Plan in Codex and Revise plan in Codex, keeping implementation completion clauses
out of this flow. It includes the current Mac-local plan-format preference.
New plans target a normalized task-title slug with the full stable task UUID as
a collision-safe suffix under `to-do/`; an explicit saved path is preserved for
revisions and for reporting an unreadable attachment. The UI
labels revision actions only when that attached Markdown file is readable and
nonempty. Launch opens a new `codex://threads/new` URL and never submits a turn.
After saving a readable nonempty plan, the external Codex session finishes its
run, attaches the plan with the latest revision through `attach_task_plan`, and
sets the task's status to Ready in Planning with the returned
revision. Opening the prompt does not mutate task state; these actions are
Mac-only. Prompt-launched threads do not return a thread ID to StageChase, so it
cannot call `thread/name/set` for them; Codex Desktop controls their displayed
names. Naming calls for threads StageChase can address remain best-effort and do
not change run outcomes.

The Mac app can expose an opt-in, loopback-only MCP server at
`Apps/StageChaseMac/MCPServer.swift`. It reads and mutates the same
`LibraryRepository` as the board; no second process opens the SQLite library.
Project/task reads are scoped by stable IDs. Create/move and plan attachment
writes use the normal reducer, persist bounded operation receipts
and advance the phone-sync sequence in the same save. Existing-task updates
require the current revision. `attach_task_plan` accepts only a readable,
nonempty Markdown file resolved inside the project's folder; it does not move or
complete the task or invoke Codex. Completion and reopening are available only
through the user's StageChase controls; MCP exposes no completion write.
External session records have a distinct source; `begin_task`,
`report_task_update`, and `finish_task` only track work that Codex Desktop
already started. They store one bounded latest message on the task/run, never a
transcript or inferred thread ID. Restart marks an external active record stale
rather than interrupted or resumable by StageChase.
MCP stage moves pass no model configuration and never call `kickRunner()`,
regardless of automatic-invocation preferences. Stop the endpoint in Settings
to disconnect Codex Desktop; it binds to `127.0.0.1` and uses a per-install
secret path component. MCP can move tasks but cannot complete or reopen them;
the user controls those actions in StageChase.

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
otherwise it reserves `to-do/<task-title-slug>-<lowercase task UUID>.md`. The
planning prompt uses that saved path, and retries reuse it. A path reservation does not mean the plan
exists: the planning run succeeds only after structured success and a readable,
non-whitespace file at the reserved destination. The task stays in its current
column. Mac Open plan and feedback controls require a readable file and are
available in any column. Phone stage moves do not reserve paths or enqueue work.

Implementation verifies the plan, then
uses a clean checkout or a detached HEAD worktree under Application Support/
StageChase/Worktrees when the checkout is dirty. Only the approved plan is copied;
other uncommitted changes stay in the original checkout. The working folder is
recorded and shown. Worktrees are retained, never auto-deleted.

## Mac Git status, task commits, and deployed revision

`GitService` runs argument-based Git commands against the configured project
folder on a utility task. It derives the current branch, full `HEAD` hash, and
staged, unstaged, and untracked change counts from Git each time; these values
are transient and are never copied to the phone. This reflects commits made
outside StageChase as soon as status is refreshed. Task detail displays the
recorded working folder for that task's latest run when one exists; otherwise
it displays shared project status and says clearly that changed files are not
assigned to the task.

The explicit **Commit all changes for this task** action stages all non-ignored
working-tree changes (`git add -A`) in the task's recorded run folder (or the
project folder when no run folder is recorded), then commits them using the task
title as a single-line message. There is no file or message picker. The action is never
triggered by a Codex run, task transition, MCP request, or phone synchronization.
An empty repository or clean worktree cannot create an empty task commit.

The project header also offers an explicit **Commit all project changes** action.
It always targets the configured project folder, even when a task has a separate
recorded worktree, and uses the title of the most recently completed task in
that project as the normalized one-line commit message. Completion time is
stored separately from ordinary task edits. Older completed tasks without that
timestamp use `updatedAt` as a best-effort recency value, with the
lexicographically greatest task ID winning equal timestamps. A project without
a completed task cannot use this action. Git actions share per-project busy
state and feedback; Git status refreshes after success or failure. This remains
a Mac-only user action.

Each project optionally stores a deployed commit hash and recording timestamp
in its normal Codable record. The Mac project controls record the current `HEAD`
when the user confirms a deployment. This checkpoint is a manual reference;
it does not observe deployment systems and may become stale if deployment or
branch changes happen elsewhere. Older project records decode with no
checkpoint. The checkpoint is included in the phone's project replica, while
local repository paths and Git contents remain Mac-only.

## Plan feedback

The Mac task context field autosaves ordinary notes and, when a readable plan is
attached, appends typed or system-dictated feedback when focus leaves the field.
`PlanFileStore` resolves the Markdown target
inside its project folder, coordinates and serializes the append, retains the
original file bytes, and verifies the resulting file before reporting success.
Each append adds a `User feedback on the plan` heading followed by the raw text.
An identical retry at the end of the file is idempotent. Failed writes keep the
editor draft. This file action does not mutate the task,
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
