# UX simplification verification

Date: 2026-10-03

Implemented the standalone plan at `to-do/simplify-project-header-and-task-detail.md`.

## Changes

- Compact Mac project header with a dedicated blue Add task button and repository popover.
- Title-first task inspector with blue Codex actions and Reopen, hidden priority, collapsed context and StageChase controls, and one newest-first run history.
- Make output in a native sheet with Copy output, explicit Stop, and dismissal independent of execution.
- Project-only Git UI on Mac and phone; phone project Git is accessible from Project settings.
- Deployment tracking retired, retaining inert legacy fields and rejecting legacy direct writes without mutation.

## Automated verification

- `make test`: all 61 Swift Testing tests passed, including run disclosure transitions, deterministic ordering, plan-only prompts, and legacy project decoding.
- `make runner-test`: offline integration checks passed, including Make success/failure/stop, commit scope, and repeated legacy deployment-request rejection without library mutation. No real Codex turns started.
- `make sync-test`: all 8 selected sync tests passed.
- `make lint`: passed.
- `make build`: passed with Apple Development signing.
- `make sim-build`: passed.
- `git diff --check`: passed.

## Mac UI verification

An isolated SwiftUI preview compiled from the project sources used an in-memory repository and a temporary Make fixture. The live app had unrelated active work and was not terminated.

Observed visually and through accessibility:

- Compact header and blue Add task; no header worktree toggle or deployed revision.
- Task title first, visible blue Reopen and Codex actions, and no task Git block or priority picker.
- Latest run expanded, two older runs collapsed; an older run expanded and collapsed independently.
- Reopen changed only the fixture task's completion/status and left its section unchanged.
- Add task opened the existing creation sheet in Inbox; cancellation created nothing.
- A harmless Make target opened the output sheet. Escape dismissed it while the header still showed Running. Show output reopened the successful result with both its initial and final output retained.

Final source review also tightened Make validation-error routing so a newly invalid request cannot display an older failed command's output. Neutral secondary styling, phone Project-settings Git access, and these final refinements passed compilation and lint; they were not separately re-inspected in the preview.

## Verification limits

- Follow-up after the Mac was unlocked: the user authorized a relaunch. The main app's Activity view reported zero active runs, then it was quit and relaunched from `build/Build/Products/Debug/StageChaseMac.app` through native app control. Relaunch succeeded, resolving the earlier `make run` / `kLSNoExecutableErr` verification limitation.
- The rebuilt main app was inspected with actual Project Chase data, both visually and through accessibility: compact header, dedicated Add task, project-only Git, title-first inspector, Launch in Codex / Review plan in Codex, latest run expanded, older run collapsed, and collapsed context, StageChase runs, and More details. No real task content or completion was changed. Additional disclosure clicks were not completed because computer-use detected concurrent user navigation; disclosure interaction and Make output behavior remain covered by the isolated preview checks above.
- `make sim-launch` built successfully but CoreSimulatorService refused the connection; simulator runtime and paired Mac–iPhone behavior remain unverified.
- The preview did not invoke real Codex sessions, commit real project changes, or change production task state. Comprehensive dark-mode, larger-text, resizing, and VoiceOver checks remain manual acceptance work.
