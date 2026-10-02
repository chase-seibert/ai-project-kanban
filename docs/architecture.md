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
  app-server fixture for progress, completion, blocked work, permission profiles, and stop.

Xcode synchronized source groups compile shared files directly into each app.
SwiftPM exposes StageChaseCore for tests. App targets do not import it separately.

## Runner lifecycle

With automatic invocation enabled globally and for the project, a confirmed
move to Planning or Implementing resolves model settings, atomically writes the
task/run state, then starts a serial Codex turn. Public events and approvals
produce a verified run outcome; the task section never changes automatically.
Planning completion sets Ready, implementation completion sets Review, and only
the user's explicit sign-off sets Done and the existing completion flag. With
automatic invocation off, task detail separates actions the user runs in Codex
from actions StageChase runs. **Run with StageChase** confirms the resolved
model and queues only that task for the Mac runner, without changing its section
or requiring either automation setting. **Plan with StageChase** queues a
planning run from any task section, reserves the plan path, and leaves placement
unchanged. Both use the project's saved execution profile. The user-run actions
**Launch Codex** and **Plan in Codex** open Codex Desktop with generated prompts
without submitting turns.
External `begin_task` records accept an optional `activity_kind` of `planning`,
`implementation`, or `task`; old clients default to `task`. Because prompt
opening does not return the Desktop thread ID, task detail offers an explicit
same-project session picker. Choosing a session calls `thread/resume` to join
that exact thread and observe notifications; `thread/read` alone is a snapshot,
not a subscription. StageChase shows the card spinner and a short latest-message
caption only while a confirmed turn is busy. Waiting, idle, or stale states stop
the spinner. Linking does not submit, interrupt, or close an external turn.
Prompts for Desktop handoff use stable project/task IDs and a readable
project-relative plan path when available, and start with the exact task title.
Runner-created planning
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

The paired iPhone uses sync protocol v3 for revision-checked completion and
deletion commands. Deletion passes through the normal reducer, which rejects an
active run; the phone confirms before enqueueing the command. A visible board
Refresh calls the existing manual refresh flow, which sends queued edits before
applying the latest snapshot and preserves the queue on failure. V2 clients are
rejected with an unsupported-version result rather than partially applying v3
commands.

Phone Git status and writes are authenticated direct requests to the Mac and
never enter the offline edit queue. Requests contain project/task IDs and an
operation ID; GitService resolves the configured project folder or the task's
recorded worktree on the Mac. The response includes bounded status fields and
action text, never filesystem paths. The Mac persists receipts for successful
commit and deployed-revision requests so a replay with the same operation ID
returns its original result. Project deployed hash/time continue to travel in
the existing replica fields. No external Codex URL contract for selecting a
remote host/workspace is defined in the official documentation; phone task
context remains copyable instead of constructing an unsupported remote URL.

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
transcript or inferred thread ID. A selected thread identity is stored only
after the user chooses it. On restart, saved activity is unknown until the user
refreshes/relinks and StageChase resumes that exact thread; disconnection marks
the live state stale and stops the spinner.
An explicit fresh `begin_task` supersedes an active StageChase-owned run for
that same task, keeps its history, and becomes the latest run. This replaces
tracking only: it does not stop the underlying runner process. Updates from a
superseded runner are ignored, while a second active Codex Desktop record still
conflicts.
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

Each project stores a Mac-runner execution profile: workspace-write with no
approval prompts, or `danger-full-access` with no approval prompts. Old project
records default to workspace-write. Queued `AgentRun` records snapshot the
effective profile, and retries keep it even if project settings later change.
The profile is included in library exports and phone replicas as informational
project data; iPhone has no runner controls and cannot start or manage Mac Codex
work. Thread start/resume receives the sandbox mode, and each turn receives its
matching `sandboxPolicy`; both use `approvalPolicy: never`. Full access removes
filesystem and network isolation, so its picker states that scope explicitly.
Quota, sign-in/device authorization, unavailable service, interactive input,
blocked work, and task failures remain visible failure or input states.

Runner turns request plain-text final responses. Only a response beginning
`Completed:` can succeed, and planning additionally requires its readable,
nonempty reserved plan. `Blocked:` and unmarked responses remain failed and
retryable; no uncertain response becomes success.

The editable plan-format instruction is a bounded Mac-local `UserDefaults`
preference, separate from `Library` and run records. Missing or whitespace-only
text resolves to the built-in template. `CodexRunner.prompt` appends it only to
new planning turn input, under the fixed task, scope, permission-profile, and
plain-text completion requirements. It does not alter implementation prompts,
existing plan files, or an already-submitted turn; it is not an enforcement
boundary.

When a confirmed Mac action queues planning, the task stores its plan destination
in that same transaction. StageChase preserves an existing user-selected path;
otherwise it reserves `to-do/<task-title-slug>-<lowercase task UUID>.md`. The
planning prompt uses that saved path, and retries reuse it. A path reservation does not mean the plan
exists: the planning run succeeds only after an explicit plain-text `Completed:` response and a readable,
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
create a run, or call the runner. Project plan paths stay out of phone snapshots;
the phone can request the bounded Markdown contents when the user opens a plan,
while plan feedback remains a Mac action.

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
sanitized snapshots. Queued phone edits remain a small allowlist (create/edit/
move/reorder/complete/delete) with expected task revisions. Each command carries
the phone edit timestamp captured when queued and the device's monotonic client
sequence. A stale task edit is rebased only when its source timestamp is newer
than the Mac task timestamp. Exact timestamp ties favor the Mac; ties between
phone writes use device ID and then client sequence. Phone timestamps more than
five minutes in the future are capped at that boundary. Accepted phone timestamps
are retained with task sync metadata so a later queued edit can be ordered; a
subsequent Mac task mutation clears that phone marker. Older writes receive a
durable superseded receipt and the current snapshot, so the outbox advances.
Unresolvable task, reorder, active-run, or project-setting conflicts resolve to
the current Mac snapshot and consume the queued operation. After a successful
sync exchange, the phone acknowledges every command that was applied, superseded,
or rejected and replaced by the authoritative snapshot. Network failures keep
the durable outbox intact. A separate authenticated request
path is used only after a visible phone action: it updates a project's Codex
profile/model with compare-before-write values, reads a bounded saved plan,
refreshes the desktop model catalog, or requests a plan/run action. These
requests never enter background refresh or the offline edit queue. The Mac
checks task revisions before acting; planning and run requests open the matching
existing Mac confirmation before the runner starts. Plan
reads resolve relative paths inside the configured project folder and return
Markdown without exposing a Mac filesystem path. The Mac `LibraryRepository` remains the only authoritative writer. It stores a library
identity, monotonic sequence, device high-water marks, and operation receipts in
the existing SwiftData metadata rows, committing accepted edits and receipts in
one save. A changed snapshot is returned when the phone cursor is stale; an
unchanged response avoids retransmitting the library every foreground poll.
The explicit **Refresh everything from Mac** action requests an unconditional
full snapshot without submitting queued edits. After the snapshot is received
and applied, it discards the phone's entire local outbox and any saved conflict
marker. If the Mac cannot complete the refresh, the cached replica and outbox
remain intact.

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

When the listener becomes ready (or reports a bind/network problem), the Mac
opens a framed TCP connection to `127.0.0.1:47928`. The probe carries a fresh
nonce; the listener returns that nonce and the `SyncServer` instance UUID. The
Connection settings report successful port registration only when both values
match, distinguishing this app instance from another service or StageChase
instance responding on the port. The check can also be started manually from
Settings.

Both apps have a Connection view with current request state, last result,
pending count, saved endpoint, and a persistent, bounded exchange journal. The
journal records timestamps, direction, framed request/response byte counts,
elapsed time, endpoint, and outcome; it never records message bodies, task text,
or credentials. Each phone exchange and Mac request connection has a 60-second
timeout. Since transport uses one short TCP connection per request,
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
open. Paired-phone completion/reopening and confirmed task deletion use direct,
revision-checked commands. Phone stage moves do not include automation
configuration and never enqueue or invoke Codex. Tapping Run with StageChase or
Plan with StageChase on the phone is the user's confirmation; the Mac resolves
its saved model and starts the requested run without a second desktop prompt.
Project settings on phone can update the execution profile and model for future
runs. Plan content is read from the Mac only when the user opens the plan in task
details and is rendered as Markdown on the phone.

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

Visible device-level pairing, add/edit/move/order propagation, explicit Codex
requests, profile/model edits, on-demand plan reads, outage recovery, and conflict
resolution remain unverified. Codex actions remain unavailable to background
polling and replica updates. Tailscale,
HTTPS, public hosting, multi-user sync, multiple Macs, background delivery,
project archival, multi-process writers, history pagination, and rich
interactive Codex questions are outside this surface.
