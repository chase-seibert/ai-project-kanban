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

`DEVELOPMENT_TEAM` defaults to `96NAC4VTEN` for Mac and iPhone signing, matching
Sideline Save, CalorieTracker, and StrengthLog. `PHONE_DEVELOPMENT_TEAM`
defaults to the same team and can be overridden independently. `DEVICE_ID`
selects the previously paired iPhone and can be overridden. The iOS app and
widget both require `group.com.cseibert.StageChase`; Xcode must have that App
Group enabled for both bundle identifiers before it can create matching device
profiles. `phone-build` signs for generic iOS so its build does not depend on
device discovery; `phone-deploy` then installs and launches on `DEVICE_ID`
sequentially. Run `make phone-verify` to inspect Xcode's device destinations and
CoreDevice discovery, following Sideline Save's preflight. Simulator builds skip
signing. The launcher supports traditional Simulator locations and this Xcode's
DeviceHub.

### Codex build permissions

On this host sandboxed SwiftPM manifests and SwiftData/SwiftUI compiler macros
can fail with `sandbox_apply: Operation not permitted`. Run build and check
targets with approved host access from the first invocation. In Codex's
`exec_command`, request `sandbox_permissions: "require_escalated"` and use a
single target with the literal checkout path, for example:

```sh
make -C /Users/cseibert/projects/ai-project-kanban build
make -C /Users/cseibert/projects/ai-project-kanban test
```

The project `.codex/config.toml` keeps workspace sandboxing as the default.
`.codex/rules/apple-build.rules` permits `build`, `sim-build`, `lint`, `test`,
`sync-test`, `runner-test`, and `codex-check` to run with host access in this
trusted checkout. Setup, cleanup, launch, provisioning, installation, and
deployment still use normal approval. Restart Codex after installing or
changing these rules. Existing sessions may still require ordinary approval;
managed restrictions take precedence. If host execution is denied, report the
check as blocked rather than retrying through another mechanism.

Rules match command prefixes, so these permissions trust the Makefile and the
code/scripts its targets execute with host access. Use one listed target per
command without appended options or variable overrides. Other invocations need
separate review. The rules intentionally name this checkout's absolute path:
worktrees and relocated clones need approval for their own path, and must never
redirect their builds into the original checkout. `make format` and ordinary
file edits remain under workspace permissions.

See the [Codex rules documentation](https://learn.chatgpt.com/docs/agent-configuration/rules)
for loading rules and the [configuration documentation](https://learn.chatgpt.com/docs/config-file/config-basic)
for precedence and project trust.

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
   Settings → Plan format prompt edits the structure for future planning runs
   on this Mac; Reset to default restores the built-in format.
4. Move an Inbox task to Next and confirm the displayed model and effort.
5. Watch Activity; approve only commands you understand.
6. Inspect the plan, then explicitly move to Implementation and confirm.
7. Review and verify changes. Mark complete yourself.

Leave the Codex executable override blank for automatic detection. StageChase
does not store API keys. **Close Codex session** releases a saved session from
StageChase; if it is active, StageChase interrupts the turn and marks it
Interrupted while preserving the session ID, working folder, and files. A
finished run keeps its result. Close is unavailable while another run owns the
shared app-server. It pauses queued work until a confirmed stage action or
Retry. Worktrees and conversation history are retained. After close, choose
**Open in Codex** to open the same `codex://threads/<id>` route and continue
manually in the desktop app; Copy Session ID remains available as a fallback.
Opening the link alone does not release the StageChase connection or confirm
that desktop continuation succeeded.

## Experimental iPhone pairing

Both devices must be on the same trusted Wi-Fi network. On the Mac, open
Settings → Mobile → **Enable local Wi-Fi sync**. Copy the displayed
`stagechase://` address and five-minute pairing code to the iPhone Connection tab,
enter a device name, and request pairing. Entering the temporary code pairs the
phone automatically; no desktop approval step is required. Anyone who obtains
the active code can pair, so share it only with the intended phone.
The Mac app must stay open and awake. After local sync has been explicitly
enabled once, its listener starts again on future Mac app launches. Foreground
refresh runs about every three seconds; each sync uses a short TCP connection,
not an always-open socket. The app does not provide internet, background, or
always-on delivery.

The Mac Mobile settings probe `127.0.0.1:47928` and verify a nonce plus a
per-instance identifier before saying this StageChase instance receives its
own port. A response from another service or another StageChase instance is
reported as a registration mismatch. Use **Verify this instance owns the port**
to repeat the check.

The listener is local-network TCP with AES-GCM-encrypted application messages;
it is not TLS and must only be used on a trusted local network. The phone stores
its pairing key in Keychain, caches the Mac library separately from its local
library, and retains supported offline edits in a bounded outbox. Paired mode
hides restore and Mac-only task controls. Automated moves that could start
Codex, completion, deletion, and retry remain on the Mac.

The Connection tab on both apps shows sync state and a bounded log of timestamped
exchanges, framed request/response sizes, durations, and results. The phone lets
you edit the saved Mac address without unpairing; a queued edit stays on the
phone while you change it. The log stores metadata only and omits task contents
and credentials.

This implementation has passed package and target builds but has not completed
visible Mac–iPhone acceptance. Treat pairing and propagation as experimental
until the verification report is updated.

Unpaired Mac and iPhone libraries remain independent. The global model
preference is saved locally on the Mac and is not included in library exports.
Project/task overrides and run model snapshots are part of library records.
Retry uses its run's saved model and effort; legacy runs ask for a choice before
retry.
