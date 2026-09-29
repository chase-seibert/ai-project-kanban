# Build and verification notes

## 2026-09-29

- Sandboxed SwiftPM/Xcode invocation cannot run compiler macro plugins on this host. This first appeared as unrelated SwiftData PersistentModel errors. Rerunning the same build/test targets with host access fixes the environment; do not remove SwiftData macros to work around it.
- Swift 6 disallows sending JSON dictionaries containing Any through a continuation. The app-server transport now passes immutable JSON Data across the continuation and decodes on the main actor.
- Approval requests originally raced progress notifications, allowing Running to overwrite Needs Approval. Both now share a serial queue, covered by the offline fixture.
- The old iOS target lacked launch-screen configuration and used a letterboxed compatibility viewport. Generated UILaunchScreen/scene settings restore full-screen rendering, verified in screenshots.
- This Xcode installation has DeviceHub under Contents/Applications, not Simulator.app. The Makefile resolves that location instead of assuming an app named Simulator.
- Mac screen locking intermittently blocks UI control. Do not claim a PID proves visible UI or substitute an imagined screenshot.
