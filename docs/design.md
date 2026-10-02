# Design

Mac sidebar and iPhone Projects tab are the main entry points. New Project opens
a blank form with a fresh identity; Project Settings edits the chosen project.
Switching projects clears task selection and search.

The board has three sections in order: Inbox, Planning, and Implementing. Mac
shows them as three side-by-side columns with independently vertical-scrolling
task lists; iPhone keeps horizontally paged columns. Each card shows one
colored, icon-led task-status capsule; plan and Codex run details stay out of
cards, with saved plans and the latest run available in task detail and run
history in Activity. Status capsules use the same styling on Mac and iPhone.
Waiting, Error, Quota, and Review sort ahead of ordinary statuses in that order,
then priority and the user's stable rank decide order.
Section headers offer named + buttons and inline multiline capture. Cards drag
between sections or onto another card to reorder within a section. Click a card
title to edit it inline, or use the card menu's **Edit title** action; other card
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

iPhone uses a horizontally paged board and section strip: one readable lane plus
a hint of its neighbor, not five squeezed desktop columns. Generated launch
configuration enables the full display rather than iOS compatibility framing.

Mac task detail is an inspector; iPhone uses a sheet. Title, task context, saved
plan, status, and manual completion share the model. Plans and Codex run state do
not restrict section placement. Title and priority drafts require Save; ordinary
task context saves automatically. Stale revisions
produce an error. Task detail and the Activity screen show compact
Codex run status and progress instead of a long chronological event timeline.
The Activity screen lists active runs; task detail keeps the latest run. Full
event records remain stored; open a run in Codex on Mac to inspect its session.
On iPhone, StageChase tries the Codex thread URL and, if no app can open it,
directs the user to continue on Mac and lets them copy the session ID. The phone
cannot manage the Mac runner.
For an incomplete Planning task with a saved plan, the same context field accepts
typed or system-dictated plan feedback. Leaving the field appends feedback;
StageChase adds a `User feedback on the plan` heading, preserves the wording, and
keeps a failed draft available for retry.
The phone directs the user to the Mac because project plan files are not synced.

When the Mac-wide automatic invocation setting and the project automation
setting are both enabled, moves into Planning or Implementing require confirmation
including usage cost. The Mac setting can turn off automatic turns globally;
task detail then offers Launch Codex using a StageChase
MCP prompt. It starts with the exact task title and contains stable project/task IDs and a readable project-relative
plan path when available. Runner-created planning sessions are named
`Plan: <task title>`; implementation and generic task handoff sessions use
`Code: <task title>`. The colon and following space separate the prefix from
the unchanged task title. Launch opens a new Codex Desktop thread without
submitting a turn. That URL flow returns no thread ID, so StageChase cannot
rename prompt-launched threads; Codex Desktop controls their displayed names.
After success, that prompt directs Codex to move the task to
Review through MCP and leave it incomplete. Enabling automation alone
never starts work.
Mac task detail also offers **Plan in Codex** or **Revise plan in Codex**
actions. They use the plan-only prompt, include the Mac plan-format
preference, and open a new thread without submitting a turn. The labels identify
whether Codex will create a first plan or revise a readable attached plan. New
plans use a normalized task-title slug plus the full lowercase task UUID under
`to-do/`; revisions retain the attached path. Plan prompts also start with the
exact task title. Codex attaches the saved Markdown plan through MCP and sets
the status to Ready while leaving it in Planning and incomplete. Launching the
action does not itself change task state.
Paired iPhone mode displays the Mac replica, sync status, pending count, and
last successful refresh. A separate Connection tab on phone and in Mac Settings
shows progress, the saved endpoint, and timestamped framed exchange sizes and
results without recording payloads. It offers supported task edits, stage moves, and
ordering, while project creation/configuration, completion, delete, restore,
and Codex controls stay on Mac. Automation-triggering moves show a Continue on
Mac explanation. Local Wi-Fi pairing is present but still awaiting visible
device-level verification; the unpaired phone library remains separate.

The Mac's Settings exposes a StageChase-wide Codex model and reasoning pair.
Project and task forms can inherit or override the pair. A run confirmation
shows the actual resolved model, effort, and source; run history keeps that
snapshot visible after settings change. The built-in preference is Latest Luna
with High reasoning. Catalog discovery is a Settings/confirmation action and
does not start a turn. The iPhone preserves saved overrides and run snapshots
but does not expose Mac model controls or discover models.

The Mac project board header exposes that project's effective model and a
compact override editor, plus a **Use worktrees** toggle. The model follows
task → project → global precedence. Worktrees default off for new projects and
for projects decoded from older library data. When enabled, a dirty repository
uses a managed worktree for a new implementation run; when disabled, the run
uses the project folder directly. Clean repositories and planning runs use the
project folder either way. A confirmed run records its selected worktree
setting; a retry reuses its saved working folder. Preference changes affect
future confirmed runs and do not alter saved run snapshots.

The Mac project header shows the current Git branch, `HEAD`, working-tree
change count, and recorded deployed revision, with explicit refresh and
deployment-recording controls. Task detail shows its latest run's working
folder status when available, or shared project status otherwise, alongside a
direct **Commit all changes for this task** action. It stages every repository
change in that working folder and uses the task title as the commit message,
without a file selection or message editor. The detail copy makes clear that
shared checkout files are not mapped to individual tasks. Git actions remain
unavailable on iPhone.

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
