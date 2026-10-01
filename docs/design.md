# Design

Mac sidebar and iPhone Projects tab are the main entry points. New Project opens
a blank form with a fresh identity; Project Settings edits the chosen project.
Switching projects clears task selection and search.

Five fixed, color-accented lanes fill the available height from the top. Mac fits
all five when possible, otherwise scrolls horizontally. Lanes scroll vertically,
have named + buttons, and offer inline multiline capture. Cards drag between
stages or onto another card to reorder within a stage. Context menus and detail
move menus provide an accessible alternative.
Lane capture accepts a pasted Apple Notes checklist when every nonblank line is
an unchecked `- [ ] item` entry (also `* [ ]`, `+ [ ]`, `☐`, and `□`). It creates
one task per checklist entry and strips the checkbox marker; ordinary text still
creates one task. When automatic invocation is enabled for Next or Implementation,
bulk capture is directed to Inbox so each later move retains its explicit run
confirmation.

iPhone uses a horizontally paged board and stage strip: one readable lane plus
a hint of its neighbor, not five squeezed desktop columns. Generated launch
configuration enables the full display rather than iOS compatibility framing.

Mac task detail is an inspector; iPhone uses a sheet. Title, notes, saved plan,
move, and manual completion share the model. Plans and Codex run state do not
restrict task placement. Dirty drafts require Save; stale revisions produce an
error. Task detail and the Activity screen show compact
Codex run status and progress instead of a long chronological event timeline.
The Activity screen lists active runs; task detail keeps the latest run. Full
event records remain stored; open a run in Codex on Mac to inspect its session.
On iPhone, StageChase tries the Codex thread URL and, if no app can open it,
directs the user to continue on Mac and lets them copy the session ID. The phone
cannot manage the Mac runner.
For an incomplete Planned task with a saved plan, Mac task detail also accepts
typed or system-dictated plan feedback. Append feedback explicitly; StageChase
adds a `User feedback on the plan` heading and preserves the user's wording.
The phone directs the user to the Mac because project plan files are not synced.

When the Mac-wide automatic invocation setting and the project automation
setting are both enabled, Next/Implementation actions require confirmation
including usage cost. The Mac setting can turn off automatic turns globally;
task detail then offers Copy prompt and Launch Codex using the same StageChase
MCP prompt. It starts with the exact task title and contains stable project/task IDs and a readable project-relative
plan path when available. The new session is named with the task title alone.
Launch opens a new Codex Desktop thread without
submitting a turn. After success, that prompt directs Codex to complete the
task through MCP while leaving its column unchanged. Enabling automation alone
never starts work.
Mac task detail also offers separate **Copy plan prompt** and **Plan in Codex**
actions. Both use the same plan-only prompt, include the Mac plan-format
preference, and open a new thread without submitting a turn. The labels identify
whether Codex will create a first plan or revise a readable attached plan. New
plans use a normalized task-title slug plus the full lowercase task UUID under
`to-do/`; revisions retain the attached path. Plan prompts also start with the
exact task title. Codex attaches the saved Markdown plan through MCP and moves a
successful plan to Planned while leaving the task incomplete. These actions are
Mac-only and do not change task state when copied or opened.
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

Mac Settings → Connection also exposes the Codex Desktop MCP endpoint. It
starts automatically when the app opens by default; stopping it in Connection
settings persists that choice, and the Start button re-enables startup. It lists
and reads project tasks and supports task creation, explicit stage moves, and
completion changes through the Mac library. The endpoint binds to loopback;
task moves do not prompt for or launch automated runs.
