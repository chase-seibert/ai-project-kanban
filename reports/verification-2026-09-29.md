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
the Mac locked. The experimental Mac–iPhone sync implementation is documented
in Settings and on the iPhone board; visible device acceptance remains open.

## Experimental Mac–iPhone local Wi-Fi sync increment

- `make test` passed all 24 core tests, including sync protocol, snapshot
  sanitization, remote command receipts, revision conflicts, and restart replay.
- `make sync-test` passed all six focused sync tests, including bounded,
  persistent exchange-journal metadata.
- `make runner-test` passed the offline runner integration fixtures; no real
  agent turns were started.
- `make lint`, `make build`, and `make sim-build` passed. The Simulator product
  includes `NSLocalNetworkUsageDescription` for the direct local connection.
- Follow-up pairing UX shows in-progress status and connection diagnostics;
  endpoint parsing accepts the plain `IP:port` displayed by the Mac. Pairing is
  automatically accepted by the temporary code without desktop confirmation.
- Phone and Mac now have dedicated Connection views, a persistent 200-entry
  metadata-only exchange log, framed request/response byte counts, and elapsed
  time. The phone can edit the saved endpoint while retaining its queued edit.
  Previously enabled Mac sync resumes on app launch; explicit disable stays off.
- Final focused verification passed: `make test` (24 tests), `make sync-test`
  (6 tests), `make runner-test`, `make lint`, `make build`, and `make sim-build`.
  The runner fixture uses isolated preferences so a saved app listener setting
  cannot start networking during the in-memory test.
- Live Mac-to-phone pairing was not exercised, so the network path and the
  phone's displayed connection error still need device-level confirmation.
- The secret scanner reported generic-secret-assignment matches for credential
  model/property names; inspection found no literal secret values in source.
- Pairing, visible project/task propagation, offline recovery, and conflict
  resolution have not been exercised between a running Mac app and iPhone.
  Device acceptance remains open. Automated transitions from the phone stay on
  Mac until explicit phone confirmation context is implemented.

The experimental listener uses encrypted application messages over local TCP;
it is not TLS and is intended only for a trusted local Wi-Fi network. No device
deployment or public service was performed during this verification.

## 2026-09-30 follow-up

- The user reported repeated `Network.NWError error 48 - Address already in
  use` listener failures on Mac. Read-only socket inspection found port 47928
  held by the StageChaseMac process running from this checkout.
- Mac listener startup now guards overlapping starts, app loading reuses an
  existing server object, and address-in-use errors explain that another
  StageChase listener may own the port.
- `make lint`, `make build`, and `make runner-test` passed after the fix.
- The Mac app was relaunched with the fix. Read-only socket inspection showed
  the new StageChaseMac process listening on port 47928, and the newest journal
  event was `Listener ready · Listening`; earlier bind failures remain as
  historical log entries.
- The iPhone was physically built, installed, and launched with
  `make phone-deploy` after the user's explicit request. The Mac app has not
  yet completed live phone-to-Mac sync verification.
