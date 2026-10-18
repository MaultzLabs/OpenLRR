# Supervisor-to-controller automatic handoff

The supervised Mac benchmark now supports a post-run decision handoff using
the existing verified run receipts and the reviewed experiment_controller.

To activate this option on a local Mac *after updating the trusted checkout*,
add --coordinate to an explicitly requested two-run plan:

    python scripts/macos/lab-supervisor.py \
      --approved-sha FULL_REVIEWED_SHA256 \
      --plan baseline,nowait \
      --seconds 60 --run --coordinate

The second mode may instead be gdi. This flag is opt-in; running a single
baseline does not create a pretend A/B report.

After BOTH supervised runs close and the required lifecycle and private-upload
checks pass, the supervisor:

1. Rechecks both summaries, game-exit receipts, matching DLL and graphics modes.
2. Writes a bounded local experiment manifest with the true benchmark run IDs.
3. Invokes experiment_controller.py using the local, pinned Python environment.
4. Records the decision in a locked, deduplicated local ledger.
5. Saves the decision JSON under
   ~/.local/share/openlrr-agent/experiments/ .

The handoff sends no credentials to the controller subprocess, does not
invoke OpenAI, does not fetch or run new DLLs, and does not automatically
schedule another experiment. An incomplete single pair can be classified
needs_more_data; no blind repeats are started.

An unset, missing or outdated controller fails closed. STOP/PAUSE at handoff
prevents progression. The working installation is never targeted.

### Still required to run unattended

The user has not enabled a secure experimental candidate executor on the Mac.
This postprocessing feature doesn't automatically accept or benchmark cloud
candidates; it only closes the **supervised test -> verified research decision**
link when used with the explicit --coordinate flag. GitHub private feedback,
cloud research dispatch, safety validation and notification delivery still
require integration and verified test coverage.
