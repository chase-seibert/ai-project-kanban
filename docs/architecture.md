# Architecture

## Project deletion and restoration

Projects have an optional `deletedAt` timestamp and a `deletionRevision` counter.
Old JSON payloads decode as active with revision zero; the existing SwiftData
V1 per-record payload storage needs no schema migration. Deletion and restoration
change only the project marker/revision and append an activity record. Projects,
tasks, runs, attachments, read markers, settings, and repository files are retained
and remain included in backups. A stale project-settings draft cannot overwrite
the deletion state. Deletion is rejected while any project run is active.

## Project ordering

Each project record stores an optional `projectOrder` value in its existing
per-record JSON payload. Older records receive a deterministic creation-date and
UUID order on load, then that order is written back without a SwiftData schema
migration. The shared sidebar uses this order on Mac and iPhone. New projects
append after all active and deleted projects. Reordering changes the active
project identities in their existing slots, so deleted projects retain their
positions and restore predictably.

Sync protocol v16 includes `projectOrder` in `SyncProject` snapshots and accepts
an explicit phone reorder command carrying a digest of the current ordered
project identities and deletion states. A stale digest conflicts; the phone
reconciles to the authoritative Mac snapshot. Commands use the existing durable
offline outbox, and snapshot polling never changes order by itself. Protocol
v15 and earlier clients must update before syncing. This repository has no web
client or web persistence service, and no web source of truth or API contract is
documented here. Web synchronization remains dependent on identifying that
existing system; this implementation does not add a backend.

Active project lists, board selection, and Recent Tasks exclude deleted projects.
The shared sidebar/projects list opens Deleted Projects, whose Restore controls
return the original project. Local changes and incoming snapshots reconcile a
deleted selection to another active project, or to the no-project state. Deleted
projects reject task edits, new tasks, run scheduling, and project Git/Make actions.

Sync protocol v10 carries deletion timestamps and lifecycle revisions in
`SyncProject` and permits explicit `setProjectDeleted` commands. The envelope's
expected revision is the project's deletion revision for these commands; stale
commands conflict instead of being rebased with task edit timestamps. Commands use
the existing durable phone outbox and transactional Mac operation receipts. Both
deleted and active project records remain in snapshots; Mac paths stay private.
Versions 9 and earlier require both apps to be updated before syncing. Real paired
device behavior remains a separate acceptance check from builds and fixtures.

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
  Project sidebar counts derive from open tasks and their status. Project Git status
  is transient presentation data, read locally on Mac and through direct paired-Mac
  requests on iPhone; it is never persisted or included in snapshots.
  Model configuration is a global Mac preference with optional project/task
  overrides; queued runs save the resolved model, effort, policy, and source.
  The Mac Projects List and `MenuBarExtra` show Codex usage, backed by a Mac-only
  observable `CodexUsageService`. Shared quota presentation logic colors the
  remaining-capacity bars and combines session and weekly status into one menu
  bar light using the less favorable status. Weekly status uses pacing against
  the reset-anchored expected remaining amount. It reads the existing Codex auth file or
  `Codex Auth` Keychain item, refreshes usage every five minutes while the app
  is active, and retains the last successful snapshot after failures. Tokens
  remain in Codex's own credential stores. Only the sanitized, timestamped
  quota snapshot is sent to paired phones and cached in the phone/widget App
  Group; it contains no auth material or task/library data.
- `Apps/StageChaseMac/`: one singleton `Window` scene for the board and its
  in-window sheets/inspectors, native commands, `AgentConnection` protocol,
  JSONL `CodexConnection`, and `CodexRunner` coordinator. The standard Settings
  command routes to the Settings sheet rather than a separate scene.
- `Apps/StageChasePhone/`: iPhone scene using the shared UI and repository.
- `Apps/StageChaseWidget/`: WidgetKit home- and Lock Screen usage widget. It
  reads only the latest phone App Group snapshot and never contacts Codex or the
  Mac directly.
- `Tests/`: reducer/persistence regressions and an offline process-level
  app-server fixture for progress, completion, blocked work, permission profiles, and stop.

Xcode synchronized source groups compile shared files directly into each app.
SwiftPM exposes StageChaseCore for tests. App targets do not import it separately.

## Mac Codex usage

`Sources/StageChaseCore/CodexUsage.swift` contains the fixture-testable response
mapper, quota windows, flex-credit conversion, and reset-anchored weekly pacing.
The weekly window keeps the API-reported `resetsAt` as the scheduled reset, shown
with its weekday, date, and time in the viewer's locale. The Mac usage service
also records successful weekly remaining-capacity observations in a versioned
Application Support JSON history. It retains up to 18 months, keeps five-minute
samples for the newest week, and compacts older observations to hourly samples
with refill boundary samples preserved. A refill requires a 25-point increase.
Its event stores the observation interval, the quota levels on either side, and
the schedule associated with the samples. An event is scheduled when its
observation interval contains the API reset, ambiguous within two hours of it
or when the observation gap exceeds 12 hours, and unscheduled otherwise.
Expected scheduled reset dates are retained as upcoming, observed, not observed,
or ambiguous, so a due schedule stays distinguishable from a refill. Only three
recent scheduled/refill event summaries and a forecast are included in the shared
snapshot; raw observations remain Mac-local. Forecasts require three consistent
unscheduled events with 3-to-60-day cadence, low interval uncertainty, and a
recent last event. Sparse, stale, irregular, or ambiguous histories show a
collecting state. The estimate is a date range and is labeled as an inference,
not an API-provided reset. Invalid or unsupported history is left untouched and
suppresses the estimate. Optional snapshot fields preserve compatibility with
older clients and do not change the strict sync protocol version.
Shared quota presentation keeps the session cutoffs at 30% red and 65% green.
For weekly windows, green starts 10 percentage points below expected remaining
capacity and red ends at 30% of that expected amount.
The Mac-only provider keeps HTTP transport and auth-file/Keychain access
injectable, refreshes OAuth credentials with compare-before-save protection,
and reports safe status text for missing login, API-key-only login, expired
login, rate limiting, and network/schema failures. A failed refresh leaves the
last successful reading visible as stale. Refresh runs only while the Mac app
is active; neither board loading nor the phone replica waits on it, and no Codex
turn is started or managed. Mac and iPhone Projects Lists use the same quota
summary. On the phone, the read-only `usage` sync response refreshes this small
snapshot without retransmitting the unchanged task library. The WidgetKit
extension displays the phone's last-good snapshot in home-screen and circular
or rectangular Lock Screen families; opening the phone app and syncing with a
paired Mac is required to refresh it.

## Runner lifecycle

With automatic invocation enabled globally and for the project, a confirmed
move to Planning or Implementing resolves model settings, atomically writes the
task/run state, then starts a serial Codex turn. Public events and approvals
produce a verified run outcome; the task section never changes automatically.
Planning completion sets Ready, implementation completion sets Review, and only
the user's explicit sign-off sets Done and the existing completion flag. With
automatic invocation off, task detail separates actions the user runs in Codex
from actions StageChase runs. **Execute Task** confirms the resolved model and
queues an implementation run from Planning or Implementing through the Mac
runner, without changing the task's section or requiring either automation
setting. **Plan with StageChase** queues a planning run from any task section,
reserves the plan path, and leaves placement unchanged. Both use the project's
saved execution profile. The user-run actions
**Launch Codex** and **Plan in Codex** open Codex Desktop with generated prompts
without submitting turns.
External `begin_task` records accept an optional `activity_kind` of `planning`,
`implementation`, or `task`; old clients default to `task`. Clients may also
pass the exact current Codex Desktop app-server `thread_id`. StageChase validates
and resumes that thread after recording the run, then observes its live events.
The run is still recorded if linking fails; the tool response reports
`thread_linked: false`, and task detail offers an explicit same-project session
picker as a fallback. Clients must not guess a thread ID or substitute an MCP
session identifier. Because prompt opening does not return the Desktop thread
ID, generated prompts instruct clients to pass it only when the exact ID is
available to them. Choosing a session from the picker calls `thread/resume` to
join that exact thread and observe notifications; `thread/read` alone is a
snapshot, not a subscription. StageChase shows the card spinner and a short
latest-message caption only while a confirmed turn is busy. Waiting, idle, or
stale states stop the spinner. Linking does not submit, interrupt, or close an
external turn.
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

Each `WorkItem` keeps its UUID for persistence, task/run relationships, MCP,
and sync operations, plus an optional positive numeric `shortID` for people.
The Mac `LibraryRepository` assigns IDs serially when it accepts task creation,
ignores incoming candidates, and stores a library-wide high-water mark so
deletion and restore do not reuse a number. Legacy libraries and imports repair
missing, invalid, or duplicate values in creation-time/UUID order while
preserving valid unique values. Paired-phone snapshots carry both the canonical
IDs and high-water mark; an offline phone task has no number until Mac
acceptance, then converges by UUID. Sync protocol v9 carries this contract.

`WorkItem.section` stores Inbox, Planning, or Implementing independently from
`WorkItem.status`. Active statuses are Triage, Planning, Plan Approved, Building,
Waiting, Error, Quota, and Reviewing. A successful planning run saves the plan
but leaves the task in Planning. The user can explicitly mark a Planning task
with a saved plan as Plan Approved from Mac or iPhone; this status also means
ready for implementation and does not move its section or start Codex. A
revision-checked phone command carries this status change to the Mac. Starting
an implementation or generic task execution moves unfinished tasks into Implementing
with Building status. This happens when a Mac-owned run first changes from queued
to running, or atomically when MCP `begin_task` records execution in an already-open
Desktop session. Planning starts preserve placement; planning progress stays
Planning. Queuing, preparing a Desktop handoff, and later observer/progress updates
do not move placement. Execution starts preserve completion, plan attachments,
and identity, increment the task revision when changed, and add visible activity.
A successful implementation sets Reviewing immediately. Waiting and Error represent
blocked or failed runs; Quota is
selected for quota-specific failure messages. The `completed` boolean is
independent from status and section; completion and reopening do not replace the
status. Legacy `done` status values decode as Reviewing while preserving the
completion flag. The shared board card renders one status capsule from an
exhaustive `TaskStatusBadgeStyle` mapping: Triage is gray, Planning and Building
share bright purple, Plan Approved is blue, and Reviewing is green. Waiting,
Quota, and Error use yellow, orange, and red. Waiting, Error, Quota, and
Reviewing sort first within a section in that order, followed by priority and
stable rank. Saved-plan details and Codex run outcomes remain in task detail,
with run history also in Activity, rather than appearing on cards.

`WorkItem.isFavorite` and optional `WorkItem.modelTag` (High or Medium) are
revisioned task fields. Missing fields decode to false and nil for older
libraries. The paired snapshot carries both fields, and protocol v14 adds
revision-checked phone commands that change only the requested field. Board
filter selection stays local to each device. Neither model tags nor favorites
change task priority or the model and effort captured by a Codex run.

The direct MCP `move_task` operation rejects a move when a task is in
Implementing and the destination stage is `.next` or `.planned` (Planning). It
returns a validation error before applying the move, recording activity, or
considering any Codex invocation. User-controlled board moves remain separate.

Legacy `stage` values remain encoded for the local MCP and older phone clients:
Inbox maps to Inbox/Triage; Next maps to Planning/Planning; Planned maps to
Planning/Plan Approved; Implementation maps to Implementing/Plan Approved;
Review maps to Implementing/Reviewing. Decoding old JSON payloads maps legacy
`ready`, `review`, and `done` status values to Plan Approved or Reviewing without
changing the separate completion flag. Sync protocol v11 adds revision-checked
phone plan approval plus saved-plan availability metadata without exposing the
Mac filesystem path. Sync protocol v12 adds revision-checked task status changes
from iPhone. Older sync protocol versions are rejected. The Mac board
presents the sections as three side-by-side columns with independently
vertical-scrolling task lists; iPhone keeps the three sections horizontally paged.

Task status can be changed independently of section and completion from the
task-card context menu or status badge menu. Waiting, Error, and Quota remain
system-set and cannot be selected manually. Task detail omits section and status
because the selected board column and card already show them. Workspace
navigation provides All, Active, Favorites, and Recently Completed on Mac and
iPhone. All includes tasks from active projects, including completed tasks, and
supports task and project-name search. Active unions unfinished Plan Approved
tasks, Building tasks, Planning and Building tasks with queued or running work,
and Reviewing tasks. Reviewing also includes saved, unapproved plans (Planning
with no active run). Recently Completed filters by the independent completion
flag and groups by `completedAt`, newest first.

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
plan-only instructions for Plan in Codex and Review plan in Codex, keeping implementation completion clauses
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
commit requests so a replay with the same operation ID returns its original
result. Legacy deployment requests are rejected before any mutation; direct
requests never enter the offline queue, so rejection is terminal. Existing
deployed hash/time replica fields remain inert for backward compatibility. No external Codex URL contract for selecting a
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

## Project Git status and commits

`GitService` runs argument-based Git commands against the configured project
folder on a utility task. The Mac header summary opens `ProjectGitStatusView`
in a popover with branch, HEAD, staged/unstaged/untracked counts, refresh, and
commit feedback. Task details no longer instantiate Mac or phone Git controls.
The existing task-worktree service/wire operations remain for compatibility,
but new task-detail UI has no commit action.

**Commit all project changes** targets only the configured project folder, using
the most recently completed task's normalized title. Completion time is independent
of edits; older records fall back to updatedAt, then task ID for ties. No completed
task means no project commit. Per-project busy state and refresh behavior remain.
Paired phones retain explicit project-level Git access through direct requests.

Deployment tracking has no active UI or local mutation entry point. The legacy
`recordDeployedRevision` wire case remains decodable but returns a retired-action
rejection without consulting Git or modifying the repository. Optional stored and
replicated deployed hash/time fields remain inert; no migration deletes them.

## Task inspector presentation

`TaskDetail` separates a fixed title/status/action header from its scrollable
body. `TaskRunDisclosureState` holds transient task/run IDs and expansion choices;
it is neither persisted nor synced. Runs sort by createdAt descending and stable
ID for ties, regardless of kind/source. Selection expands only the latest; a new
latest collapses its predecessor while routine updates preserve user choices.
Context and feedback use disclosure state with the existing draft/save bindings.
A synchronous submission guard prevents duplicate blur/collapse feedback requests.
The rail and phone task sheet are keyed by task ID to isolate drafts across selection.
Blue primary-action tint is explicit and does not change semantic stage colors.

## Favorite Make targets

Projects store an ordered, backward-compatible list of favorite Make target
names. `SyncProject` carries the list and older snapshots decode it as empty;
the phone can preserve the data but has no editor or execution command. The Mac
project editor trims names and rejects empty, duplicate, leading-dash, and
control-character values.

`MakeTargetService` resolves the latest project from the library by ID, checks
its configured directory, and launches `/usr/bin/make` directly with one target
argument and that directory as its working folder. It captures stdout and
stderr into a bounded in-memory buffer, keeps one app-wide process active, and
reports running, succeeded, failed, or stopped state compactly in the header.
`AppSheet.makeOutput` uses the shared presenter to display `MakeOutputSheet`.
The service outlives sheet dismissal; Show output reopens the retained result.
Output truncation is explicit in the sheet and copied text. Stop remains distinct
from Close/Escape. The original project/target identity belongs to the service,
not whichever board is currently selected.
This local action is separate from task placement/completion, Codex runs, Git
commits, and phone-triggered work.

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

## Project sidebar counts and Git state

The shared project list derives total, plan-review, and code-review counts from
open library tasks. `.planApproved` and `.reviewing` remain distinct and reuse
their status badge colors. Rows place four compact count badges to the right of
the project name: neutral total, blue plan review, green code review, and orange
Git changes. Missing or failed Git status uses a dash in the Git position. The
Mac project header echoes a changed-file count in orange. Main board columns
show blue and green review counts only when open tasks in that column have the
matching status. Project Git state is transient: Mac rows call the existing Git
service, while paired iPhone rows request status from the Mac. The sidebar
refreshes when rows appear and existing Git actions complete; it does not poll
in the background.

## Experimental local Wi-Fi synchronization

`Sources/StageChaseCore/SyncProtocol.swift` defines versioned phone commands and
sanitized snapshots. Protocol version 13 removes unread acknowledgment commands
and read-marker maps from snapshots; clients using earlier protocol versions are
rejected before replica or outbox state changes and must update before syncing.
The legacy acknowledgment command shape remains decodable only so a saved phone
outbox can be opened; sending one is rejected as retired. Old sync metadata keys
and old `Activity.taskChange` payload fields are ignored on decode and are not
written again. Ordinary activity messages remain available for audit history.
Protocol version 12 adds revision-checked task status changes; versions 11 and
10 add plan approval and reversible project deletion; version 9 adds task short
IDs; version 8 adds task attachment metadata and direct image requests; version 7
adds timestamped Codex usage snapshots; version 6 adds project creation; and
version 5 adds linked Codex thread IDs to read-only run snapshots. Queued phone
edits remain a small allowlist (project creation/delete/restore, task
creation/edit/move/reorder/complete/delete, and project Codex settings) with
expected task or project deletion revisions where applicable. Each command
carries the phone edit timestamp captured when queued and the device's monotonic
client sequence. Stale task edits are rebased only when their source timestamp is
newer than the Mac task timestamp. Exact timestamp ties favor the Mac; ties
between phone writes use device ID and then client sequence. Phone timestamps
more than five minutes in the future are capped at that boundary. Accepted phone
timestamps are retained with task sync metadata so a later queued edit can be
ordered; a subsequent Mac task mutation clears that phone marker. Older writes
receive a durable superseded receipt and the current snapshot, so the outbox
advances. Unresolvable conflicts resolve to the current Mac snapshot and consume
the queued operation. After a successful sync exchange, the phone acknowledges
commands that were applied, superseded, or rejected and replaced by the
authoritative snapshot. Network failures keep the durable outbox intact. A
separate authenticated request path is used only after a visible phone action.
It never enters background refresh or the offline edit queue. The Mac
`LibraryRepository` remains the only authoritative writer. It stores a library
identity, monotonic sequence, device high-water marks, and operation receipts in
the existing SwiftData metadata rows, committing accepted edits and receipts in
one save. A changed snapshot is returned when the phone cursor is stale; an
unchanged response avoids retransmitting the library every foreground poll. The
explicit **Refresh everything from Mac** action submits supported queued edits
then requests an unconditional full snapshot. A transport failure leaves
unaccepted operations in the outbox. Version 3 clients fail clearly rather than
exchanging a partial snapshot.

The Mac app starts `NWListener` on port 47928 only after the user enables local
sync from Settings → Mobile. That explicit choice is remembered, so the
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
Mobile settings report successful port registration only when both values
match, distinguishing this app instance from another service or StageChase
instance responding on the port. A transient explicit verification state drives
the Mac window toolbar's network icon beside the sidebar toggle: neutral while checking, green on
success, and red on failure. The listener checks at startup and every five
minutes while enabled, with one probe at a time and generation checks discarding
stale callbacks after stop, failure, or restart. Selecting the sidebar icon
opens Settings directly to Mobile, and it remains available with the sidebar
hidden; its full diagnostic remains the source for troubleshooting. The check
can also be started manually from Settings. Recent local Wi-Fi exchange events
are opened on demand from Mobile rather than shown inline. Codex Desktop MCP
listener controls are in a separate MCP tab.

Task images use a separate `TaskAttachment` metadata value and
`TaskAttachmentFiles` store. Files are validated as single-frame JPEG, PNG, or
HEIC images (4 MB and 8,192 pixels per side maximum), written atomically, and
checked against SHA-256 before preview. SQLite task payloads and sync snapshots
contain IDs, names, media types, sizes, checksums, and transfer state only. A
paired-phone attach uses one authenticated direct upload request; opening an
uncached preview requests only that image. Snapshot refresh does not download
image files. `BackupArchive` frames the library JSON and raw image files in a
versioned container, while old JSON-only backups with no image references remain
readable.

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
configuration and never enqueue or invoke Codex. Tapping Execute Task or
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
