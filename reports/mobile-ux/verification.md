# iPhone task UX implementation and verification

2026-10-18 · Task f542e834-6e94-49f2-a6be-e1d76af8d7ef

Implementation is present; interactive acceptance is blocked. No task completion
or reopening was performed. The existing attached plan was read and left unchanged.

## Design decisions

The baseline nested a padded lane around padded cards and repeated task notes.
Only about two complete tasks were visible. The redesigned phone lane removes
that enclosure and subtitle, gives titles more horizontal space, and moves notes
to detail. Four complete tasks are now visible in the matched Inbox capture.
Status remains a named, icon-led control, with ID and optional tags beneath the
title. Single-tap opening, double-tap inline editing, long-press menus, native
section tabs, project switching, and revision-checked mutations keep their
existing handlers. Explicit accessibility actions open details or edit the title.

Task detail now scrolls as one page. Status and Complete/Reopen sit together;
controls stack at accessibility text sizes. Plan in Codex is primary in Inbox
and for unapproved Planning tasks; Launch in Codex is primary otherwise. The
alternate action stays in More actions and Copy prompt stays visible. Existing
loading, active-run, section, completion, and paired-Mac request checks remain.
Context has a short preview; a saved plan has a dedicated row. Images and
secondary task properties use disclosure groups. Existing save, plan reader,
attachment, attention-run, and delete-confirmation paths are reused.

## Screenshot evidence

All captures use an isolated in-memory `--preview-library`, not the user's Mac
library. Device: iPhone 17 Pro, iOS 26.5, 1206 × 2622 pixels (402 × 874 points).
Baseline and matched after captures use Dark appearance and Large text size.
Fixture IDs/timestamps are regenerated per launch; task titles and counts match.
These are rendered-state comparisons, not evidence of taps or live sync.

| State | Before | After |
| --- | --- | --- |
| Inbox | [baseline](before-inbox.png) | [redesigned](after-inbox.png) |
| Planning, favorite + High | [baseline](before-planning.png) | [redesigned](after-planning.png) |
| Implementing | [baseline](before-implementing.png) | [redesigned](after-implementing.png) |
| Favorites with no matches | [baseline](before-empty.png) | [redesigned](after-empty.png) |
| Active task detail | [baseline](before-detail.png) | [redesigned](after-detail.png) |

Additional rendered states: [long title and attention](after-long-attention.png),
[completed task](after-completed.png), [saved-plan row](after-saved-plan.png),
[large-text detail](after-detail-large-text.png),
[large-text Planning](after-planning-large-text.png),
[light Inbox](after-inbox-light.png), and [light saved-plan detail](after-saved-plan-light.png).
Large-text captures use `accessibility-extra-large`; controls reflow without
horizontal overlap. Auxiliary detail captures preceded the final notes-alignment
refinement; the final dark saved-plan/detail captures include that refinement.
The final light Inbox capture includes the explicit grouped lane background,
added after screenshot review caught the system tab background merging cards.
Simulator appearance and text size were restored to Dark and Large afterward.

Reproduce with `make sim-launch`, then launch the installed app through simctl
with `--preview-library --preview-board` or `--preview-library --preview-task
--preview-active-task`. Board variants: `--preview-planning`,
`--preview-implementing`, `--preview-empty`. Detail variants:
`--preview-long-title`, `--preview-attention`, `--preview-saved-plan`,
`--preview-inbox-task`; omit `--preview-active-task` for completed detail.
Use `xcrun simctl io DEVICE screenshot OUTPUT.png` to capture rendered output.

## Verification

- `make sim-launch`: passed for the baseline; app built, installed, and launched.
- Final `make sim-build`: passed; final app installed and launched for captures.
- Final `make build`: passed for the Mac target; phone-only layout is gated by iOS.
- `make test`: all 99 shared-model tests passed, including task state, completion,
  revisions, run disclosure, storage, and sync behavior. No core-model changes.
- Final `make lint`: passed across Sources, Apps, and Tests.
- `git diff --check`: passed.
- Screenshot review: matched board/detail states plus long title, attention,
  empty filtering, completed rendering, saved-plan visibility, large text, and
  light appearance inspected. Rendering alone does not verify interaction.

Interactive simulator checks through Device Hub passed task opening from Inbox
and Implementing, back navigation, Planning/Implementing section switching,
the High-filter empty state and Clear filters, Task context and More details
disclosures, double-tap inline title editing, and canceling both inline editing
and a new-task draft. Counts and titles remained unchanged. These checks used
the isolated `--preview-library` fixture.

VoiceOver, project selection, saved-plan/image opening, and paired-Mac behavior
remain unverified. No real Codex action or physical-device deployment occurred.
The StageChase task remains in Implementing with `completed=false`. A fresh
StageChase progress run could not be opened because the server reports an
existing active session; no run ID was exposed for a safe update or finish.

## Changed files

- `Sources/StageChaseUI/BoardViews.swift`: phone layout, filters, cards, empty states,
  and accessible title actions.
- `Sources/StageChaseUI/DetailViews.swift`: phone hierarchy and adaptive controls.
- `Sources/StageChaseUI/RootView.swift`: isolated screenshot fixture variants and
  fix for preview routing being reset by asynchronous project selection.
- `docs/design.md`, `CHANGELOG.md`: resulting phone behavior.
- `FRUSTRATION.md`: reusable simulator-control limitation.
- `reports/mobile-ux/`: screenshot evidence and this verification record.

The four original-resolution Inbox/detail before-and-after PNGs were attached to
StageChase. Final task readback: revision 14, stage `implementation`,
`completed=false`, four available attachments. The external run was recorded as
failed because interactive acceptance remains blocked, despite passing builds,
model tests, lint, and rendered-state review.
