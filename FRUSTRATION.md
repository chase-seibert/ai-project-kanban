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

- `make run` used to reopen a stale StageChase process, and `open` sometimes
  returned `kLSNoExecutableErr` even when the rebuilt executable was present.
  `make relaunch` now requests graceful termination of all StageChase instances,
  waits for them to exit, and opens the exact built bundle. On this host, `open`
  still returns `kLSNoExecutableErr`; launching the exact checkout through the
  desktop app controller works. Running the bundle executable directly exits
  with status 134, so keep launching the app bundle. Check Activity before
  relaunching: wait for Mac-runner Codex turns to finish; Codex Desktop launches
  do not block it.
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
  available. Before relaunching, check Activity and defer only while a Codex run
  is owned by the Mac runner; Launch Codex sessions continue independently in
  Codex Desktop. Paired-device checks remain unverified when simulator services
  are unavailable and physical deploy is outside the task authorization.

## 2026-10-03

- A standalone SwiftUI preview compiled with an ad hoc `swiftc` command hit the
  documented SwiftData macro sandbox failure although allowed Make targets passed.
  Approved host compilation produced an isolated in-memory preview, allowing UI
  checks without restarting the main app during unrelated active work.

## 2026-10-18

- The desktop UI tool returned `cgWindowNotFound` for Device Hub and StageChase
  while `simctl` could still build, launch, and capture a booted simulator.
  Isolated `--preview-library` launch fixtures support screenshot review in this
  state, but do not establish taps, navigation gestures, editing, or VoiceOver
  acceptance. Do not treat those captures as interactive verification or
  relaunch the Mac app without checking Activity. Preview task routing also
  needs to ignore the asynchronous project-selection path reset.

## 2026-10-24

- `make sim-launch` could not complete its simulator build/launch path after
  CoreSimulatorService refused connections. A preceding `make sim-build` passed,
  so retain the compile result but report Simulator launch and interaction as
  unverified until the service is available.
- `make relaunch` failed before launch because the requested `Mac Development`
  certificate private key was unavailable, even though a preceding `make build`
  completed with the configured Apple Development identity. Treat the relaunch
  as unverified and do not infer launch from the successful build.

## 2026-10-26

- `make relaunch` again could not sign with the configured `Mac Development`
  identity. `make build` succeeded with the available Apple Development
  identity, and the rebuilt bundle launched directly. `make sim-build` passed,
  but `make sim-launch` could not rebuild reliably after CoreSimulatorService
  disconnected; SwiftData macro compilation then failed with
  `sandbox_apply: Operation not permitted`. Treat Simulator interaction as
  unverified when this environment failure recurs.

## 2026-10-27

- `make relaunch` again stopped while signing with the missing `Mac Development`
  private key. `make build` succeeded with the available Apple Development
  identity; a graceful UI quit followed by direct launch of the built app
  bundle worked for interaction checks.
