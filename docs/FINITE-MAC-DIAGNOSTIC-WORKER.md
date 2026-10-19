# Finite opt-in Mac diagnostic worker — first unattended execution milestone

This component is a **narrow, bounded unattended worker**, NOT a ready-to-use
general autonomous game fixer. It will only re-run a **specific diagnostic
binary that has already been reviewed and tested in the isolated Mac game**:

- Source workflow: OpenLRR Menu Diagnostics Win32, run `39184097578`
- Source commit: `c3f8d2a81661a7626be0e8628d90c54898688c43`
- Reviewed DLL SHA256:
  `1179323074e03caf22f89ecbf05b9234f8ef5e18f2c1d6b8d797c2cf31c5b4ff`
- Execution target: **OpenLRR Menu Test.app only**.
- Frequency: at most one attempt each UTC day, **two total attempts maximum**,
  with user enrollment automatically expiring after seven days.

The worker delegates its single fixed command to the existing SHA-pinned
`diagnostic-one-shot.sh`, which runs two 60-second baselines and uploads
their clean-exit receipts to the private GitHub results repository. There is
no arbitrary job intake, model-authored command, downloaded unreviewed
candidate, code update, or production game replacement.

## What you must do on the Mac (one-time, when ready)

No remote chat can install or enable a launchd service on your Mac. First
review and update the **lab** checkout; keep the working game separate. Close
the TEST app and inspect STOP/PAUSE/leftover locks. Then explicitly opt in:

```bash
bash "$HOME/OpenLRR-Agent/scripts/macos/install-approved-diagnostic-worker.sh" \
  --explicitly-enroll-fixed-diagnostic
```

This command **enrolls, but does not launch Wine immediately**; it registers
a user-scoped launchd agent with `RunAtLoad=false` and 24-hour intervals.
The enrollment binds every relevant trusted local script digest plus the
checkout commit, so modifying/updating the lab checkout after enrollment
stops the worker rather than silently executing new code.

**Before opting in:** test the isolated wrapper's process lifecycle
interactively and confirm Wine does not have unsafe host-file mappings. This
worker is a finite continuation of already-validated diagnostic execution.
It is not a hardened VM sandbox for untrusted DLLs.

Dry-run the registered worker logic without starting a game:

```bash
"$HOME/.local/share/openlrr-agent/venv/bin/python" \
  "$HOME/OpenLRR-Agent/scripts/macos/approved-diagnostic-worker.py"
```

Safety stop, effective on the next check:

```bash
touch "$HOME/.config/openlrr-benchmark/STOP"
```

To disable scheduling:
```bash
launchctl bootout "gui/$(id -u)" \
  "$HOME/Library/LaunchAgents/com.maultzlabs.openlrr-approved-diagnostic.plist"
```

A failed/aborted process retains a lock and a consumed attempt. This is
intentional: investigate the TEST app's Wine processes and backup state
before any recovery. Never delete a lock just to force a restart.

## Not solved yet

- AI-authored candidate DLL execution is **forbidden** by this worker.
- Full macOS/VM containment and trusted guest lifecycle attestation remain
  prerequisites for general unattended experiments.
- The wrapper may expose the host filesystem via Wine drive mappings.
  Run `wine-isolation-audit.py` before deploying a general autonomous worker.
- CI can exercise local worker state and recovery logic, but cannot verify
  a Sikarugir GUI wrapper exit from a GitHub Ubuntu/Windows runner.
- Some Mac login/background GUI contexts may require launchd-specific
  troubleshooting; the new service has **not** been installed on the user Mac.
- No observed FPS improvement is established by repeating the known baseline.
