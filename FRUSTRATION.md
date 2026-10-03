# Build and verification notes

## 2026-09-29

- Sandboxed SwiftPM/Xcode invocation cannot run compiler macro plugins on this host. This first appeared as unrelated SwiftData PersistentModel errors. Use approved host execution for build/check targets from the first attempt; see the Codex build permissions section in `AGENTS.md` and `.codex/rules/apple-build.rules`. Do not repeat the failing sandboxed attempt or remove SwiftData macros to work around it.
- Swift 6 disallows sending JSON dictionaries containing Any through a continuation. The app-server transport now passes immutable JSON Data across the continuation and decodes on the main actor.
- Approval requests originally raced progress notifications, allowing Running to overwrite Needs Approval. Both now share a serial queue, covered by the offline fixture.
- The old iOS target lacked launch-screen configuration and used a letterboxed compatibility viewport. Generated UILaunchScreen/scene settings restore full-screen rendering, verified in screenshots.
- This Xcode installation has DeviceHub under Contents/Applications, not Simulator.app. The Makefile resolves that location instead of assuming an app named Simulator.
- Mac screen locking intermittently blocks UI control. Do not claim a PID proves visible UI or substitute an imagined screenshot.
- The standalone `runner-test` compile enumerates app sources instead of using the Xcode target, so adding a Mac service referenced by `AppModel` also requires adding it to that source list.

## 2026-10-01

- A rebuild/relaunch check found `make run` reused a stale StageChase process; the
  sandbox denied signaling it, and `open` then reported `kLSNoExecutableErr`
  even though the rebuilt executable was present. Closing the stale process
  with host access and launching the exact bundle through the desktop app
  controller worked. Improve the relaunch workflow so it reliably quits stale
  instances and opens the rebuilt bundle.
- A nested `codex exec` could not reach StageChase's loopback MCP endpoint from its sandbox, even after allowing workspace writes. The StageChase settings UI showed the listener as stopped on a later check; restarting it and making a direct local MCP request worked. Avoid repeated nested CLI attempts: verify the listener is active and use the MCP connection in the current session, or report that the tools are unavailable.

## 2026-10-02

- Recording the compiler sandbox failure here did not prevent repeated failed
  first attempts because setup instructions still said to retry afterward.
  At the time, `AGENTS.md` required approved host execution initially and
  project Codex rules allowed the listed Makefile targets after a restart.
  The current project instruction is to use normal workspace permissions and
  report blocked launch/simulator checks without escalating.
- `make lint` reports pre-existing `swift-format` indentation and line-break
  findings in untouched `DetailViews.swift` and `BoardViews.swift`. The files
  changed for sync pass targeted strict formatting; avoid broad unrelated
  reformatting while working on sync.
- With normal workspace permissions, `make test`, `make build`, and
  `make sim-build` completed. `make run` rebuilt the Mac app but Launch Services
  returned `kLSNoExecutableErr` even though the bundle executable exists and
  codesign validation passes. `make sim-launch` rebuilt the iPhone app but
  CoreSimulatorService returned connection refused, so no simulator was
  available. Do not terminate a currently running StageChase instance just to
  retry: it may recover unrelated active runs on relaunch. Paired-device checks
  remain unverified when simulator services are unavailable and physical deploy
  is outside the task authorization.
