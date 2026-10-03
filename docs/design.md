# Design

Mac sidebar and iPhone Projects tab are the main entry points. New Project opens
a blank form with a fresh identity; Project Settings edits the chosen project.
Switching projects clears task selection and search.

The Mac project header has two compact rows: project name, open-task count,
and a dedicated blue **Add task** button; then Make, a repository summary,
automation/model information, and Project settings. Add task uses the focused
section, matching Command-T. The generic toolbar plus is removed; lane capture
and menu/keyboard commands remain. The slogan and verbose automation banner
are no longer shown on the Mac board.

Project Settings stores an ordered list of favorite Make targets. Running a
favorite opens a native output sheet with project, target, status, Copy output,
Stop, and Close. Closing or pressing Escape leaves the process running. Make
keeps a compact result in the header and offers Show output to reopen it.
The service retains a bounded output tail and labels truncation. Failure does
not reopen a dismissed sheet. Settings and execution remain Mac-only;
favorites travel in project snapshots so phone refreshes preserve them.

The board has three sections in order: Inbox, Planning, and Implementing. Mac
shows them as three side-by-side columns with independently vertical-scrolling
task lists; iPhone keeps horizontally paged columns. Each card shows one
colored, icon-led task-status capsule; plan and Codex run details stay out of
cards, with saved plans and the latest run available in task detail and run
history in Activity. Status capsules use the same styling on Mac and iPhone.
Waiting, Error, Quota, and Review sort ahead of ordinary statuses in that order,
then priority and the user's stable rank decide order. Priority labels and the
normal detail picker are hidden; stored priority, sorting, and menu/keyboard
commands remain available.
Mac section headers keep named + buttons and inline multiline capture. On
iPhone, one blue **Add task** toolbar button creates a task in the currently
focused section; per-lane + buttons are removed to avoid a second Add task
control. There is no extra Add task row at the bottom of a lane. Cards drag between sections or onto
another card to reorder within a section. On Mac, a single click on a card title
opens task detail and a double-click starts inline title editing; the card
menu's **Edit title** action remains available. On iPhone, a single title tap
opens task detail and a double tap starts inline title editing. Other card
content opens task detail. The title editor stays multiline and only one card
can be edited at a time; opening another title saves and closes the prior editor
when its draft is nonempty and changed. Return saves through the
revision-checked task edit, while Escape or Cancel discards the draft. A failed
save leaves the current editor open with its draft intact. Drag and reorder
behavior is unchanged. Task detail keeps its primary actions focused on launch,
planning, and user sign-off.
Lane capture accepts a pasted Apple Notes checklist when every nonblank line is
an unchecked `- [ ] item` entry (also `* [ ]`, `+ [ ]`, `☐`, and `□`). It creates
one task per checklist entry and strips the checkbox marker; ordinary text still
creates one task. When automatic invocation is enabled for Planning or Implementing,
bulk capture is directed to Inbox so each later move retains its explicit run
confirmation.

iPhone uses the native tab bar to switch between Inbox, Planning, and
Implementing, with one readable lane per tab rather than five squeezed desktop
columns. The system tab bar supplies the current iOS material and appearance.
Generated launch configuration enables the full display rather than iOS
compatibility framing.
On iPhone, the selected project name in the navigation bar opens a project
switcher. The native bottom tabs select Inbox, Planning, or Implementing and
stay in sync with the focused section used by Add task. The overflow menu contains
completed items, **Refresh from Mac**, Connection, Activity, Settings, and
Project Git and Project settings. Project Git status and the confirmed project
commit action route through the paired Mac. Pull-to-refresh also remains
available. Task details have no Git or deployment controls on either platform.

Mac task detail is an inspector; iPhone pushes a task screen in its navigation
stack. The system back button and edge-swipe gesture return to the board. Title, task context, saved
plan, status, and manual completion share the model. Plans and Codex run state do
not restrict section placement. Title and model drafts require Save; ordinary
task context saves automatically. Stale revisions
produce an error. Task detail and the Activity screen show compact
Codex run status and progress instead of a long chronological event timeline.
The user can complete or reopen a task from task detail at any time, including
while a Codex run is Waiting or active. Run outcomes never complete a task or
overwrite its Done status; unsaved detail drafts remain available to save.
On iPhone, completion and reopening use revision-checked queued edits. Task
deletion requires an explicit confirmation and the Mac rejects deletion while
a run is active.
On iPhone, the title stays first. **Reopen**, **Launch in Codex**, **Plan in
Codex**, and **Copy prompt** appear before secondary details. Launch and Plan
are explicit, revision-checked requests to start the selected Codex action on
the paired Mac; a tap is the user's confirmation. Copy prompt produces a
StageChase-aware task prompt for pasting into another Codex chat. Saved-plan
review remains available inside collapsed details. Task context and other
details start collapsed.
The Activity screen lists active runs. Task detail merges planning, implementation,
and external runs into one newest-first history. Only the latest run starts
expanded; older runs are individually expandable. A new run expands and collapses
the previous latest, while ordinary status updates preserve expansion choices.
Switching tasks resets the disclosure defaults. Attention rows expose older runs
that need input or failed without expanding all history. Full
event records remain stored; open a run in Codex on Mac to inspect its session.
On iPhone, a run with a linked Codex thread ID shows **Open in Codex**. StageChase
tries the Codex thread URL and, if no app can open it, directs the user to
continue on Mac and lets them copy the session ID. Runs without a linked ID do
not show the action. The phone cannot manage the Mac runner.
Mac and paired iPhone Project settings expose a per-project Codex execution profile. The safe
default uses workspace-write and disables approval prompts. Full access is an
explicit choice with filesystem and network scope explained beside the picker.
Runs save the selected profile and retries reuse that snapshot. Profile values
travel in project replicas. Phone changes affect future runs only; each new run
still uses the Mac's existing confirmation. Final runner summaries use ordinary
readable prose.

For an incomplete Planning task with a saved plan, the same context field accepts
typed or system-dictated plan feedback. Leaving the field appends feedback;
StageChase adds a `User feedback on the plan` heading, preserves the wording, and
keeps a failed draft available for retry.
Project plan paths stay out of phone snapshots. A paired iPhone can request the
bounded Markdown file on demand and display it inline in task detail.

When the Mac-wide automatic invocation setting and the project automation
setting are both enabled, moving into Planning or Implementing saves the new
placement first, then asks for confirmation before starting Codex and shows the
usage cost. Cancelling or failing to prepare the run leaves the task in its new
column. The Mac setting can turn off automatic turns globally;
task detail then offers Launch Codex using a StageChase
MCP prompt. It starts with the exact task title and contains stable project/task IDs and a readable project-relative
plan path when available. Runner-created planning sessions are named
`Plan: <task title>`; implementation and generic task handoff sessions use
`Code: <task title>`. The colon and following space separate the prefix from
the unchanged task title. Launch opens a new Codex Desktop thread without
submitting a turn. That URL flow returns no thread ID, so StageChase cannot
rename prompt-launched threads; Codex Desktop controls their displayed names.
After success, that prompt directs Codex to move the task to
Review through MCP while preserving its current completion flag. Enabling automation alone
never starts work.
Mac task detail also offers **Plan in Codex** or **Review plan in Codex**
actions. They use the plan-only prompt, include the Mac plan-format
preference, and open a new thread without submitting a turn. The labels identify
whether Codex will create a first plan or review and revise a readable attached plan. New
plans use a normalized task-title slug plus the full lowercase task UUID under
`to-do/`; revisions retain the attached path. Plan prompts also start with the
exact task title. Codex attaches the saved Markdown plan through MCP and sets
the status to Ready while preserving task completion. Launching the
action does not itself change task state.
Mac task detail has a fixed title-first header above a scrolling body. Launch in
Codex and Review plan in Codex are blue primary actions. Completed tasks have a
blue Reopen button beside status; open tasks have Complete in the same position.
Existing-thread access, Open plan, Refresh, and prompt-copy actions are secondary.
Long titles can expand. Context and plan feedback, StageChase run controls, and
additional metadata are initially collapsed. Save failures reveal the context
editor; collapse and focus changes must not append feedback twice. The iPhone
shares title-first detail and collapsible history/context, retaining its native
phone-specific actions. Completion remains explicit and independent of run state.

Paired iPhone mode displays the Mac replica, sync status, pending count, and
last successful refresh. A separate Connection tab on phone and in Mac Settings
shows progress, the saved endpoint, and timestamped framed exchange sizes and
results without recording payloads. It offers supported task edits, stage moves,
ordering, and project Codex profile/model edits. Task detail can explicitly ask
the Mac to prepare a planning or task run; both actions use the existing Mac
confirmation before Codex starts. Background refresh remains read-only with
respect to Codex.
Automation-triggering moves show a Continue on Mac explanation. Local Wi-Fi pairing is present but still awaiting visible
device-level verification; the unpaired phone library remains separate.

The Mac's Settings exposes a StageChase-wide Codex model and reasoning pair.
Project and task forms can inherit or override the pair. A run confirmation
shows the actual resolved model, effort, and source; run history keeps that
snapshot visible after settings change. The built-in preference is Latest Luna
with High reasoning. Catalog discovery is a Settings/confirmation action and
does not start a turn. The iPhone loads the desktop catalog when project settings
are opened and can change the project's inherited or overridden model.

Project Settings exposes model and worktree preferences; the header shows a
compact effective-model summary with no worktree toggle. Model precedence remains
task → project → global. Worktrees default off; when enabled, dirty implementation
runs use an isolated checkout. Existing run snapshots and retry folders do not
change when preferences change.

The Mac repository summary opens a project popover with current branch, HEAD,
change counts, refresh, project commit, and result/error feedback. Task detail
has no Git block. Deployment tracking is retired on Mac and phone; legacy stored
hash/time values are inert compatibility metadata and are not displayed.

The project header's **Commit all project changes** action stages changes only
in the configured project folder. Its message comes from the most recently
completed task in the same project, so later edits to an older completed task
do not change which title is selected. It is disabled while another Git action
for that project is running and reports the resulting commit or the reason it
could not commit.

Mac Settings also exposes a multiline **Plan format prompt** editor with a
reset-to-default action. Its default asks plans to start with user-story
requirements, then cover architecture and data-model changes, basic test cases,
and high-level implementation details. The bounded preference is stored on
this Mac and affects future planning runs only; it does not change existing
plans or implementation prompts.

Use native SwiftUI controls, SF Symbols, semantic colors/fonts, NSOpenPanel,
NSPasteboard, NSUndoManager, and Settings. Cmd-N adds a task; Shift-Cmd-N adds a
project; Shift-Cmd-A opens activity; Cmd +/-/0 adjusts persisted semantic text
size. Cmd-Z/Shift-Cmd-Z undo/redo manual task creation, edits, moves, completion,
and deletion without agent history. Agent side effects are never undone or
restarted. Reordering currently has no undo action. Deletion requires confirmation.

The macOS app uses one primary StageChase window. The project board, task detail,
activity, project editors, and Settings remain in that window; transient editors,
detail, and Settings use sheets or in-window inspectors. The standard Settings
menu command and Command-comma open the Settings sheet. The primary window remains
resizable with its existing minimum and default sizes. The iPhone app retains its
own navigation and scene behavior.

Mac Settings → Connection also exposes the Codex Desktop MCP endpoint. It
starts automatically when the app opens by default; stopping it in Connection
settings persists that choice, and the Start button re-enables startup. It lists
and reads project tasks and supports task creation, explicit stage moves, and
completion changes through the Mac library. The endpoint binds to loopback;
task moves do not prompt for or launch automated runs.
