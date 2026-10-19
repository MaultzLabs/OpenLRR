# Integrated opt-in Wine CPU stack sampling during a supervised TEST benchmark

The fixed test supervisor (`scripts/macos/lab-supervisor.py`) now supports
`--profile-wine-cpu` in combination with `--run`. This starts a bounded,
read-only macOS `sample` sidecar after the supervised GAME benchmark has
begun, in the **existing TEST run**. It does not start another game.

Example, after updating and validating the lab checkout and staging an
explicitly SHA256-reviewed diagnostic DLL:

```bash
"$HOME/.local/share/openlrr-agent/venv/bin/python" \
  "$HOME/OpenLRR-Agent/scripts/macos/lab-supervisor.py" \
  --approved-sha "$REVIEWED_64_HEX_DIGIT_SHA256" \
  --plan baseline --seconds 60 --run --profile-wine-cpu
```

The profiler waits roughly 20 seconds into the benchmark wrapper, identifies
one Wine PID using the TEST game's open file handles, and captures three
seconds of CPU stack samples. Inability to sample produces a separate
`wine_cpu_profile_local_only` audit event, not a fictitious positive
performance result. The profiler may cause CPU overhead, so **do not**
compare a profiled run with an unprofiled run as if the test workloads were
identical.

The raw native stack trace stays on the Mac in
`~/.local/share/openlrr-agent/wine-cpu-profiles` under private directory
permissions. No raw stack logs are uploaded by the sampler or supervisor.
STOP/PAUSE disables sampling and existing game stop/close rules remain
unchanged. No unapproved DLL, model-generated script, shell command or
production-game change is authorized by this flag.

The GitHub test suite covers that a launch without `--run` rejects profiling,
that a supervised run can start one fixed local sampler, and that model/API
credentials are not inherited. Real native macOS `sample` permissions and
the wrapper's exact process naming remain to be tested on the user's Mac.

Follow-on improvement: correlate the sampled function families with the
DirectDraw 1-second Blt timestamps and use that data to produce a falsifiable
Wine/driver optimization hypothesis, not a blind performance patch.
