# Setup and installation

Xcode 27 / Swift 6; macOS 14+ and iOS 17+. No external packages required.

```sh
make test
make runner-test
make codex-check
make run
make sim-launch
make phone-deploy
```

`DEVELOPMENT_TEAM` defaults to the existing personal team `96NAC4VTEN`.
`DEVICE_ID` selects the previously paired iPhone and can be overridden. Mac
builds are Apple Development signed. Device deployment builds, installs, then
launches sequentially, even with parallel make. Simulator builds skip signing.
The launcher supports traditional Simulator locations and this Xcode's DeviceHub.

On this host sandboxed compiler invocations can block SwiftData/SwiftUI macros.
Retry the same target with approved host access before treating it as a source
error. Codex's runtime workspace sandbox remains enabled independently.

## Data

New installations start empty. Existing `store.json` imports into Application
Support/StageChase/Library-v2.sqlite, preserving the original and a pre-v2 copy.
Never delete existing data to fix an import error. Settings exports JSON backups;
restore refuses to overwrite a nonempty library.

Launch with `--preview-library` for isolated in-memory screenshot fixtures; add
`--preview-board` on iPhone to open its sample board. Relaunch without flags to
return to real data. Preview mode blocks automation.

## Codex

1. Project Settings → choose the repository folder → enable Codex.
2. Settings → Check Codex connection. Sign in using Codex itself if needed.
3. Settings → Default Codex model → refresh available models. The built-in
   setting is Latest Luna · High; choose another visible model or effort if
   needed. Project and task settings can inherit or override this pair.
4. Move an Inbox task to Next and confirm the displayed model and effort.
5. Watch Activity; approve only commands you understand.
6. Inspect the plan, then explicitly move to Implementation and confirm.
7. Review and verify changes. Mark complete yourself.

Leave the Codex executable override blank for automatic detection. StageChase
does not store API keys. Open in Codex uses the desktop `codex://threads/<id>`
route; Copy Session ID is a fallback for versions without that route.

Mac and iPhone libraries remain separate. Phone moves do not start Mac work.
The global model preference is saved locally on the Mac and is not included in
library exports. Project/task overrides and run model snapshots are part of
library records. Retry uses its run's saved model and effort; legacy runs ask
for a choice before retry.
