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
move, and manual completion share the model. Dirty drafts require Save; stale
revisions produce an error. Activity includes statuses, public progress, plan
steps, approvals, errors, command output, session links, and working folders.

Automated Next/Implementation actions require confirmation including usage cost.
Manual mode is labeled prominently. Enabling automation alone never starts work.
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

Use native SwiftUI controls, SF Symbols, semantic colors/fonts, NSOpenPanel,
NSPasteboard, NSUndoManager, and Settings. Cmd-N adds a task; Shift-Cmd-N adds a
project; Shift-Cmd-A opens activity; Cmd +/-/0 adjusts persisted semantic text
size. Cmd-Z/Shift-Cmd-Z undo/redo manual task creation, edits, moves, completion,
and deletion without agent history. Agent side effects are never undone or
restarted. Reordering currently has no undo action. Deletion requires confirmation.
