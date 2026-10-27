# Changelog

## 2026-10-27

- Require a user-entered title when creating a task from a shared photo; keep
  the source filename as attachment display metadata.
- Add optional project emoji identity to Mac and iPhone project settings and
  shared project rows, preserving the SF Symbol fallback. Carry emoji through
  project snapshots and add a stale-value-checked phone update in sync protocol 17.

## 2026-10-26

- Automatically save task title, notes, and task model edits on Mac and iPhone
  with debounced revision checks, visible save status, and draft-preserving retry.
- Keep Mac inline title edits local while typing, then save and close the
  plain-text editor after focus leaves it or a click lands elsewhere on the
  board, including another task. Command-Return also saves and closes the edit.
- Keep iPhone sync incomplete when task-image uploads remain pending, including
  full refreshes, and verify the Mac confirms the uploaded file in its snapshot.
- Clear a stale missing-image warning on Mac when a later task update confirms
  the attachment file is present.

## 2026-10-24

- Add an iOS photo Share Extension with a project-aware new-task composer. Stage
  the image and request in the App Group, then import it into the phone library
  as an Inbox task with a stable ID and the existing attachment upload flow.
  Enable the App Groups capability on the Share Extension target so its signing
  profile can include the shared container entitlement.
- Give the Share Extension a nonempty display name so iOS accepts its embedded
  bundle during device installation.
- Keep Cancel and Add task pinned at the top of the photo composer, place project,
  title, and compact description controls first, and show the shared photo below.
- Remove the redundant composer heading and ready hint, leaving only text Cancel
  and primary Add task actions at the top.
- Prefill the editable task title from the shared photo filename, with a Photo
  task fallback, so Add task is available as soon as the photo loads.
- Show only the possible next Codex quota reset date; remove the interval and
  early-reset details from the Mac panel and widget.
- Make iPhone task prompt copies explicit: the primary copy follows the task's
  planning or implementation state, with a clearly labeled choice for the other
  intent. Use the shared plan-only and implementation prompt builders.

## 2026-10-21

- Add a Mac GitHub project-management view with upstream status, ahead counts,
  per-project Push, and Push All with separate project results. Group it between
  New Project and Deleted Projects in the sidebar.
- Replace the High, Medium, Plan Approved, Building, In Progress, and Reviewing
  workspaces with All and Active. All includes every task in active projects;
  Active combines the previous status-based task collections. Keep Favorites and
  Recently Completed, and use the same workspace order on Mac and iPhone.

## 2026-10-20

- Add native task search to the iPhone board and workspace views, matching task
  titles and notes and matching project names in cross-project workspaces.
- Reorganize Mac Settings into Appearance, Codex, Prompts, Backup, Mobile, and
  MCP tabs; open local Wi-Fi exchange diagnostics from Mobile on demand.
- Follow system Light and Dark appearance across Mac and iPhone, with a local
  System / Light / Dark choice, semantic status colors, and adaptive shared
  surfaces.
- Add iPhone Home Screen quick actions for the first four active projects in
  saved order, routing launch and warm selections through the existing project
  selection and board navigation flow.
- Add persistent project ordering to the shared Mac and iPhone sidebar, including
  direct drag-and-drop, accessible move actions, deterministic legacy ordering,
  deleted-project position retention, and revision-checked phone sync. The web
  integration remains pending identification of its existing client and data
  source.

## 2026-10-19

- Add a Building workspace on Mac and iPhone for unfinished Building tasks across
  projects. Move unfinished tasks into Implementing with Building status when
  Codex execution starts, including Desktop MCP tracking and Mac-runner retries.
  Preserve planning placement and completion; queued work and Desktop handoffs
  do not trigger this transition.

- Refine the iPhone task-list and task-detail hierarchy from screenshot review:
  expose the board overflow directly in the toolbar, remove the project dropdown,
  add spacing around filters and above the floating section bar, and reduce task
  detail to one primary Codex action with grouped secondary actions. Show
  favorites as a star and expand context and More details by default.
- Refine the iPhone board filters to All, Favorites, and Plan Approved, keep the
  lane canvas consistent through the filter gap, collapse task context by
  default, expand attached images with inline previews, and move large Complete/Reopen and
  separate Delete actions to the bottom of task detail.

## 2026-10-18

- Redesign the iPhone board with wider title-first task cards, compact section
  headers, larger filter/status touch targets, and useful filtered empty states.
  Make task detail a single scrolling page with a status/completion row, one
  primary Codex action, a context preview, a visible saved-plan entry, and grouped
  images and secondary details. Preserve existing task and sync operations.

## 2026-10-14

- Open saved plans on iPhone in a dedicated full-screen Markdown reader with a
  keyboard-aware multiline feedback editor. Saving feedback explicitly appends
  it to the Mac plan and starts one revision-checked, retry-safe planning run;
  the reader reloads the revised plan when the run succeeds. Advance paired
  sync protocol to version 15.

## 2026-10-13

- Show local sync loopback verification in the Mac project sidebar header with neutral, green, and red states. Recheck every five minutes while enabled and open Connection settings directly from the icon.
- Place the local sync status icon in the window toolbar beside the sidebar toggle so app-wide connection state remains visible with the sidebar hidden.
- Show the weekly Codex quota's scheduled reset weekday, date, and time. Record
  bounded Mac-local quota history, distinguish observed scheduled, extra, and
  ambiguous refills from the API schedule, and show a qualified date-range
  estimate for consistent extra-refill history. Share only recent event
  summaries and the credential-free estimate with the phone and widgets.
- Sort Inbox tasks by creation time, newest first. Sort Planning and Implementing
  with Waiting, Error, Quota, and Reviewing first in that order, then Plan
  Approved, then other statuses; sort within each status by most recent update
  and use task IDs to break timestamp ties.

## 2026-10-09

- Update the iPhone workspace list to Favorites, Plan Approved, Reviewing, and
  Recently Completed, using the same task filters as Mac. Show each workspace
  day in one full-width column on iPhone while keeping the three-column Mac view.
  Hide completed tasks from Favorites on both platforms and from High/Medium on Mac.
- Extend the loopback StageChase MCP with task image metadata, verified image
  retrieval, and revision-checked screenshot attachment. Return retrieved images
  as MCP image content, validate base64 uploads with the existing size, type,
  dimension, and integrity rules, and support bounded image-sized HTTP requests.

## 2026-10-08

- Add task favorites and High/Medium model tags on Mac and iPhone, with board
  quick filters and cross-project workspace views. Keep those tags separate
  from task priority and run model configuration; sync edits with revision
  checks using protocol v14. Keep card controls in the context menu and show
  favorite/tag indicators only when set.
- Add manual status changes to task-card context menus, clickable status badges,
  and task detail on Mac and iPhone. Add a persistent status filter to Recent
  Tasks. Sync phone status changes with revision checks, and share only plan
  availability metadata so a saved Mac path is not exposed to the phone.
- Advance the strict paired sync protocol to version 13 and remove unread
  markers, clear-on-open behavior, and synchronization of read acknowledgments.
- Replace unread badges with compact per-project open-item, plan-review,
  code-review, and Git change counts. Reuse blue Plan Approved, green Reviewing,
  and orange Git treatments; use a dash when Git status is unavailable. Echo
  review counts in matching board columns and changed-file counts in the project
  header.
- Keep Waiting, Error, and Quota out of manual status choices, and remove the
  duplicate section and status row from task detail while retaining completion.
- Replace the Recent Tasks status selector with cross-project workspace views
  ordered Plan Approved, In Progress, Reviewing, and Recently Completed. Plan
  Approved shows tasks ready to execute; Reviewing combines pending plan
  approval with code review; In Progress requires a queued or running plan/build
  run; Recently Completed sorts by completion time.
- Keep workspace cards in three equal-width columns even when a day has only
  one or two cards.

## 2026-10-07

- Simplify task statuses: planning remains Planning until manually approved,
  Plan Approved also means ready, and successful implementation moves directly
  to Reviewing. Keep completion as an independent boolean. Add the manual plan
  approval action to Mac and iPhone task detail, synchronize phone approvals
  with revision checks, distinguish status colors, and reject MCP moves from
  Implementing back to Planning. Advance the strict sync protocol to version 11.
- Defer the iPhone navigation reset after the selected project changes so
  deleting its active row does not update the project list and navigation path
  in the same UI transaction.
- Recreate the iPhone project list when active project membership changes to
  avoid applying a stale UIKit collection-view diff during deletion or restore.
- Add reversible project deletion on Mac and iPhone, with a Deleted Projects
  link and Restore controls. Keep projects, tasks, runs, attachments, settings,
  and repository files; hide deleted projects from active lists and Recent Tasks.
  Reject deletion during active runs and new work in deleted projects. Synchronize
  delete/restore commands with lifecycle revisions and advance the strict paired
  sync protocol to version 10.

## 2026-10-06

- Add a Workspace **Recent Tasks** view with task cards grouped by update day
  in a newest-first, balanced three-column vertical stack across projects.
- Give every task a positive library-wide numeric ID allocated by the Mac.
  Keep UUIDs as machine identity, preserve the sequence after deletion, repair
  legacy/imported IDs deterministically, and sync the canonical number and
  allocator state to iPhone. Offline phone-created tasks show “ID pending”.
  Advance the strict sync protocol to version 9.
- Show a light-blue paperclip on task cards when a plan path is attached, on Mac
  and iPhone.

## 2026-10-05

- Add task image attachments on Mac and iPhone with native pickers, preview,
  removal, size/type/checksum validation, atomic file storage, and pending upload
  state. On Mac, also attach clipboard images with Paste. Keep image bytes outside
  task JSON, SQLite, and regular sync snapshots; transfer only on attach or when
  opening a preview. Add a versioned backup archive with separate image files
  and keep legacy JSON-only restore support.
  Advance the strict sync protocol to version 8.
- Add `make relaunch` to gracefully quit existing StageChase instances before
  opening the built Mac app; `make run` now uses the same flow. The agent
  workflow checks for active Mac-runner Codex turns first, while Codex Desktop
  launches remain safe to leave running.
- Match the Codex usage reference's red/yellow/green quota bars and weekly pace
  marker. Weekly green now begins 10 percentage points below pace, with the red
  cutoff at 30% of pace. The menu bar combines session and weekly status using
  the less favorable color while keeping both percentages visible. Add a
  refreshable usage panel, and move Mac refresh/last-updated controls to the
  panel's lower right.
- Show Codex session and weekly capacity in the Mac and iPhone Projects Lists,
  including reset times, weekly pacing, and reported flex credits. Refresh from
  the local Mac Codex login every five minutes while active, sync only the
  sanitized usage snapshot to paired phones, and share its last-good value with
  home- and Lock Screen widgets through an App Group. Credentials stay on Mac.
- Advance the strict sync protocol to version 7 for phone Codex usage snapshots.
- Add pull-to-refresh to the iPhone Projects List as a full refresh from the
  paired Mac; queued phone edits are reconciled before the local replica is
  replaced. Add the system-provided container background to Lock Screen widget
  families so they work in the widget gallery.
- Let users create projects from a paired iPhone. The project name is sent as
  an explicit queued sync command and created in the Mac library; advance the
  strict sync protocol to version 6.

## 2026-10-03

- Simplify the Mac project header with a dedicated blue Add task button, compact
  project controls, and project-only Git details in a popover. Keep worktree and
  model editing in Project settings; hide priority chrome on task cards/details.
- Put task titles and key actions first, promote Reopen and Codex launch/plan
  review in blue, collapse context and StageChase controls, and initially expand
  only the newest run across planning and execution history.
- Move Make output into a reopenable native modal. Dismissal keeps commands
  running; Stop is explicit and truncated output is labeled.
- Retire deployed-HEAD tracking on Mac and phone. Preserve inert legacy metadata
  while rejecting old deployment requests without mutation.
- Use the native iOS tab bar for Inbox, Planning, and Implementing, preserving
  the system's current tab-bar material. Keep one blue Add task action for the
  focused lane and move refresh and connection choices into the overflow menu.
- Put Launch in Codex, Plan in Codex, and Copy prompt beside Reopen in phone
  task details. Launch and Plan are explicit, revision-checked requests to the
  paired Mac; task context and saved-plan reading stay in collapsed details.
- Push phone task details onto the standard navigation stack with the native
  back button and swipe-back gesture. Add Project Git to the project menu so
  phone users can review status and confirm a paired-Mac project commit.

- Carry linked Codex thread IDs in read-only phone run snapshots so iPhone can
  open existing sessions from task detail using the existing Mac-continuation
  and copy-ID fallback. Advance the strict sync protocol to version 5. Guard
  the Mac-only Make target editor helper from the phone build.

## 2026-10-02

- Add project-specific favorite Make targets to Mac Project Settings and an
  explicit project-header run menu with Stop, bounded output, and final status.
  Favorite names remain backward-compatible and round-trip through phone
  snapshots; Make execution stays separate from tasks, Codex, and Git commits.
- Rename the explicit StageChase task action to **Execute Task** and make it
  queue an implementation run from Planning or Implementing. Keep plan creation
  and revision on the separate planning action.
- Add project Codex command rules and build instructions that request approved
  host execution initially for Apple builds/checks, avoiding repeated known
  compiler sandbox failures while keeping workspace sandboxing as the default.
- Increase phone and Mac sync request timeouts to 60 seconds.
- Track manually started Codex Desktop planning and execution in separate task
  detail sections. Let the user link an exact same-project Desktop thread and
  observe its live turn state and latest message; show a card spinner/caption
  only for a confirmed busy turn, and stop it on waiting, idle, or disconnect.
- Let `begin_task` accept the exact current Codex Desktop `thread_id` and link
  the run immediately when supplied. Update shared MCP and generated handoff
  instructions to pass the ID when available, never guess, and report when
  manual linking is still needed.
- Verify the Mac sync listener over loopback with a nonce and per-instance ID,
  and show whether this StageChase instance successfully receives requests on
  its registered port.
- Resolve stale paired-phone task edits by latest edit time, acknowledge stale or
  rejected outbox operations after applying the latest Mac snapshot, and drain
  queued changes without leaving a conflict marker after successful sync.
- Make **Refresh everything from Mac** replace the phone replica and discard all
  pending local changes after the full snapshot succeeds; failed refreshes keep
  the outbox.
- Make a single click on a Mac task title open task detail and a double-click
  start inline title editing, matching the iPhone board interaction.
- Treat paired-phone Run with StageChase and Plan with StageChase taps as the
  user's confirmation, starting the selected task on Mac without opening a
  second desktop confirmation.
- Decode saved iPhone action queues with the same ISO-8601 date strategy used
  when writing them, preserving queued edits across app relaunches.
- Highlight unread task changes with a subtle light-blue card background and
  sort Planning and Implementing tasks by most recent update on Mac and iPhone.
- Sync task and project unread read-through markers in protocol v4. Phone
  acknowledgments apply optimistically, stay queued through failed exchanges and
  full refresh, and cannot move the shared marker backward.
- Use neutral text styling for Low, Medium, and High priority labels.

- Add paired iPhone completion/reopening and confirmed task deletion through
  revision-checked sync protocol v3 commands. Add a visible board Refresh button
  with sync progress/result feedback, while keeping pull-to-refresh.
- Expose project/task Git status, confirmed commits, and deployed-revision
  recording on iPhone. Git runs on the paired Mac through online-only direct
  requests; commit receipts prevent replayed operation IDs from creating another
  commit, and responses omit repository paths.
- Keep Codex remote URL handoff as a copy-context fallback: official Codex
  documentation describes Remote inside ChatGPT mobile but does not specify a
  supported external URL contract for selecting its host/workspace.
- Let an explicit Codex Desktop `begin_task` replace an active StageChase run
  for the same task, retain the old record as Superseded, and ignore late writes
  from that runner while preserving idempotent MCP operation receipts.
- Resolve stale phone task edits and moves by their queued edit time, acknowledge
  superseded outbox operations, and add an unconditional **Refresh everything
  from Mac** action that preserves local state if the full refresh fails.
- Route each iPhone lane's + button to the shared Add Task sheet, remove the
  phone overflow Add Task command and bottom lane capture row, and make task
  title single taps open detail while double taps edit inline.
- Add explicit paired-phone actions to request a confirmed planning or task
  run on the Mac; show saved plan Markdown in
  task detail and expose per-project Codex profile/model settings on iPhone.
  Direct requests use sync protocol v2 and remain separate from background
  polling and the offline board-edit queue.
- Add a confirmed **Run with StageChase** task action that starts only the
  selected task through the Mac runner, independent of automatic-run settings;
  keep **Launch Codex** as the separate Desktop handoff.
- Add **Plan with StageChase** as a confirmed planning action from any task
  section, and group the four run/planning actions into full-width task-detail
  sections with Refresh below them.
- Replace the iPhone app tab bar with bottom Inbox, Planning, and Implementing
  controls; add project switching from the navigation title, move Connection to
  the top bar, and keep Activity and Settings in the overflow menu.
- Remove the iPhone board status card and add a Project Chase preview fixture
  based on the visible task titles in the supplied board screenshot.
- Add per-project Codex execution profiles with a safe workspace-write default,
  explicit full-access opt-in, and per-run retry snapshots. Keep approval
  prompts disabled for both profiles while leaving quota, sign-in, device,
  service, input, and task failures visible.
- Replace JSON-constrained runner outcomes with readable plain-text final
  responses; only explicit `Completed:` messages and valid planning files can
  finish successfully.
- Keep manual task completion and reopening available while a Codex run is
  Waiting or active, and remove completion changes from MCP. Run updates
  preserve a user's Done state and manually selected column.
- Save manual column moves before optional Codex setup, keep moved tasks placed
  if setup fails or is cancelled, and allow card drops across priority groups.

## 2026-10-01

- Prefix runner-created Codex sessions with `Plan: ` for planning and `Code: `
  for implementation and generic task handoffs. Prompt-launched Desktop threads
  remain titled by Codex Desktop because StageChase receives no thread ID to rename.

- Unified board-card status into one colored, icon-led capsule shared by Mac and
  iPhone, and removed the separate Codex run badge from cards. Run history stays
  visible in task detail and Activity.
- Set Ready and Review to green, Done to blue, and Quota to orange.

- Added inline task-title editing from board cards. Click the title itself or
  choose **Edit title** from the card menu, type in the multiline focused field,
  and press Return to save; Escape or Cancel discards the draft. Opening another
  title resolves and closes the current editor. Other card content opens task
  details.
- Consolidated the macOS app into one resizable primary window. Settings and the
  existing board tools now stay in that window, and the standard Settings menu
  command and Command-comma open the in-window Settings sheet.
- Consolidated the board into Inbox, Planning, and Implementing sections, with
  independent task statuses, attention-state sorting, three-column Mac layout
  with vertical task lists, and horizontal iPhone sections. Legacy stages and task payloads still decode and
  remain available to MCP and phone compatibility paths; plan and implementation
  outcomes now set Ready and Review, while only user sign-off sets Done.
- Corrected generated manual task prompts to move successful implementation work
  to Review and leave it incomplete for user review.
- Generated plan filenames now use readable normalized task-title slugs with
  full task-ID suffixes; planning, implementation, and manual prompts start
  with the task title.
- Added Mac Git status in project headers and task details, including the
  current branch and commit hash, plus a task action that stages all project
  changes and commits with the task title as its message. Added an optional
  per-project deployed-revision checkpoint recorded from current `HEAD`.
- Added a project-header action to commit all changes in the configured
  project folder using the most recently completed task title. Tasks now retain
  a backward-compatible completion timestamp so later edits do not change
  which task supplies that message.
- Added unread badges for task column and completion changes. Project badges count
  changed tasks, while task badges clear independently when a task is opened.
- Added Mac-only Copy plan prompt and Plan in Codex task-detail actions. Their
  shared plan-only prompt carries the plan-format preference, preserves the
  selected path, and attaches successful plans without completing the task.
- Lane quick capture now turns pasted Apple Notes unchecked checklist entries
  into separate tasks, while preserving explicit Codex confirmation for later
  moves into automated stages.
- Start the loopback-only Codex Desktop MCP listener automatically on app launch
  by default, with a persistent Stop/Start choice in Connection settings.
- Added Mac project-header controls for a per-project managed-worktree toggle
  and model override. Worktrees default off for existing and new projects;
  project-folder runs with local changes are explained in the UI.
- Added an opt-in, loopback-only MCP task server for Codex Desktop. It lists
  projects/tasks, reads tasks, creates Inbox tasks, and supports explicit,
  revision-checked stage and completion changes through the local library.
- Persisted bounded MCP operation receipts in the same save as task changes so
  retried writes are idempotent and visible to normal board/phone sync refresh.
- Added revision-checked MCP plan attachment for readable, nonempty Markdown
  files inside the project folder. Synchronized local and reusable agent
  instructions to attach plans and move successful planning tasks to Planned,
  and to complete tasks after successful implementation.
- Added a Connection settings control and Codex CLI setup command. MCP task
  operations never start StageChase's Codex runner. Added explicit external
  session bookkeeping and a bounded latest update visible in task detail.
- Added Copy prompt and Launch Codex actions to task details. Both use the
  same prompt with stable project/task IDs and a readable project-relative
  plan path when available; successful MCP-reported work marks that task
  complete without changing its stage.
- Added a task-detail Refresh action that rereads saved task state and plan
  availability, updates linked Codex status and latest turn activity, and
  preserves unsaved edits without changing task stage or completion.

## 2026-10-01

- Added optional task priorities, priority-first ordering within columns, sync
  snapshot support, and keyboard navigation and task actions on Mac. Added Task
  and Navigate menus that list shortcuts, plus shortcut hints on task actions.
- Opening a task no longer focuses its editable fields automatically, keeping
  board shortcuts available until a field is deliberately selected.
- Return now submits either task deletion confirmation dialog.

## 2026-09-30

- Added a Mac-wide automatic-invocation setting and task-level Codex Desktop
  handoffs that save/copy context, open a linked session, support manual status
  refresh, and allow retry/rerun from task detail.
- Made task columns independent of plans and Codex state; stage moves remain
  available during runs, and Codex outcomes no longer move tasks automatically.
- Reserve each confirmed planning run's task-relative plan path before the run
  starts, reuse it on retry, and require a readable nonempty file at that path
  before reporting planning success.
- Added an editable Mac-local plan format prompt with user requirements,
  architecture/data model, basic test cases, and high-level implementation
  sections, applied only to future planning turns.
- Added Mac-local Codex approval modes: Codex no-prompt policy by default,
  explicit Ask me decisions, and one-time automatic approval for supported
  command/file requests without widening workspace or network access.
- Added Mac task-detail feedback that appends typed or dictated raw text to the
  saved plan under a user-feedback heading, without starting Codex.
- Added Close Codex session for explicit desktop handoff, preserving saved
  results and workspaces while pausing the runner queue until a later action.
- Prevented concurrent Mac listener starts from binding twice to port 47928.
  Port conflicts now explain how to release the port before retrying.
- Added a saved phone automatic-sync toggle plus board pull-to-refresh and an
  explicit Sync Now action that work even when automatic syncing is off.
- Replaced long Mac and iPhone activity timelines with compact run details and
  Codex session handoff, retaining full event history in storage.

## 2026-09-29

- Replaced prototype code with independently identified multi-project boards.
- Rebuilt both native interfaces: top-aligned lanes, quick capture, drag/drop,
  card reordering, task detail, activity, and explicit project creation.
- Fixed iPhone compatibility-mode sizing with generated launch configuration.
- Added versioned SwiftData/SQLite, legacy import, preserved backups,
  export/empty-library restore, and manual-task undo/redo.
- Added Codex app-server integration with durable runs, progress, logs, approvals,
  session links, stop/retry, structured outcomes, and dirty-checkout isolation.
- Added Latest Luna · High model defaults, project/task overrides, model
  catalog validation, and saved model/effort snapshots for confirmed runs and retries.
- Added model/persistence regressions and offline runner integration fixtures.
- Added an experimental local Wi-Fi sync path: temporary-code pairing, encrypted
  protocol messages, authoritative Mac receipts, phone replica cache, and a
  durable phone outbox. Pairing is automatic from the temporary code. Added a
  Connection tab on phone and in Mac Settings with progress, editable endpoint,
  and bounded timestamped network-exchange logs. The Mac listener resumes on
  app launch after the user has enabled it. Device-level acceptance remains open.

## 2026-09-28

- Created the StageChase macOS and iOS SwiftUI app targets.
- Added the shared fixed-stage data model, local persistence, revisioned task
  transitions, activity history, and structured automation references.
- Added board/task editing interfaces for Mac and iPhone.
- Added Swift package tests and Makefile build/test/simulator/device targets.
