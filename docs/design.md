# Design

Mac sidebar and iPhone Projects tab are the main entry points. New Project opens
a blank form with a fresh identity; Project Settings edits the chosen project.
Switching projects clears task selection and search.

Five fixed, color-accented lanes fill the available height from the top. Mac fits
all five when possible, otherwise scrolls horizontally. Lanes scroll vertically,
have named + buttons, and offer inline multiline capture. Cards drag between
stages or onto another card to reorder within a stage. Context menus and detail
move menus provide an accessible alternative.

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
MCP prompt. It contains stable project/task IDs and a readable project-relative
plan path when available. Launch opens a new Codex Desktop thread without
submitting a turn. After success, that prompt directs Codex to complete the
task through MCP while leaving its column unchanged. Enabling automation alone
never starts work.
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

Mac Settings → Connection also exposes an opt-in Codex Desktop MCP endpoint.
It lists and reads project tasks and supports task creation, explicit stage
moves, and completion changes through the Mac library. The endpoint binds to
loopback; task moves do not prompt for or launch automated runs.
