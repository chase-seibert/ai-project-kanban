# StageChase rewrite verification — 2026-09-29

## Confirmed

- `make lint` passed.
- `make test` passed all 13 workflow, migration, SQLite persistence, restart,
  project-isolation, undo, revision, and reorder tests.
- `make runner-test` passed against the offline JSONL fixture: planning and
  verified stage change; blocked result preserved its stage; approval stayed in
  Needs Approval until answered; stop preserved the current stage; retry reused
  the run/session; NSUndoManager add/undo/redo worked; and a dirty Git checkout
  used an isolated worktree while preserving the original uncommitted edit.
- `make codex-check` initialized the installed Codex app-server, confirmed an
  existing sign-in, and read the session list. It intentionally started no turn.
- Signed Mac build passed with the Apple Development certificate for team
  `96NAC4VTEN`.
- Signed iPhone build and installation passed for device
  `00008150-000E41422E40401C`.
- The actual migrated Mac library opened in the new board UI. The prior
  “Sideline Save 2” project and its task contents remained intact. The final
  signed Mac app was relaunched against that library, and the visible board
  showed its existing tasks. A separate in-memory preview demonstrated
  independent project creation and column quick capture without touching that
  library.
- Captured Simulator screenshots after the full-screen launch configuration:
  [iPhone projects](iphone-projects.png) and [iPhone board](iphone-board.png).

## Remaining device and end-to-end checks

The iPhone install completed, but iOS denied launch because the device was
locked. It must be unlocked once before the app can be opened there. The Mac
screen also locked during intermediate UI checks, but the final check closed
the preview and relaunched the signed production app against the real library.

No real model-driven planning or implementation turn was started; runner
behavior was verified with offline fixtures and the read-only Codex handshake.
Drag gesture and session deep-link navigation were not fully rechecked after
the Mac locked. Mac–iPhone pairing and synchronization remain unimplemented and
are called out in Settings and on the iPhone board.
