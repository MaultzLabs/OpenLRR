# Menu recovery: 3–6 bounded Mac sessions (no new game-system expansion)

**Scope:** Restore the original LEGO Rock Raiders main menu first. Preserve the
composer and native-port research without expanding them. This package uses
the existing TEST-only `diagnostic-one-shot.sh`, `lab-supervisor.py`,
`run-autobenchmark.sh`, `analyze-benchmark.py`, Wine CPU sampler and private
benchmark uploader. No unreviewed DLLs or source-generated patches run.

## Engineering audit

| Existing component | Reused now | Constraint |
| --- | --- | --- |
| Supervised macOS menu runner | Yes | TEST app only, 60 seconds per arm, verified exit receipt |
| Reviewed Win32 diagnostics artifact | Yes | Run 39184097578, fixed source + DLL hashes |
| SHA-checked temporary staging and rollback | Yes | Runner backs up TEST DLL; no force-kill on unresolved process |
| DirectDraw/CPU timing counters | Yes | Logical presentation, not displayed FPS |
| Local macOS Wine CPU profiler | Best-effort | Three-second sample, raw stack traces remain LOCAL |
| Private GitHub upload | Yes | Metrics and safe summaries only; uploader refuses public repository |
| Candidate A/B controller | Future source fix | Requires separately reviewed source revision and >=5 robust matched pairs |
| Screenshot/video and visual QA | **Not yet integrated** | Separate experimental branches exist; evidence remains MISSING in this release |
| Audio/input interaction tests | **Not yet integrated** | Do not claim menu works until separately checked |
| Secure OS/VM isolation | **Not verified** | Cannot run AI-generated DLLs unattended |

Known real Mac results from October 18: baseline at 3.59 and 4.08 **logical**
frame flips/s, 31 DirectDraw blits over 1s in each run and approximately 50s
of accumulated presentation time per 63s test. These values **do not**
establish actual visible FPS.

## Exact reviewed graphics artifact used by sessions 1 and 2

- GitHub Windows diagnostic workflow run: `39184097578`
- Source commit: `c3f8d2a81661a7626be0e8628d90c54898688c43`
- DLL SHA256: `1179323074e03caf22f89ecbf05b9234f8ef5e18f2c1d6b8d797c2cf31c5b4ff`

The one-shot downloader verifies the workflow, source revision, CI artifact
hash, and the **additional reviewed DLL SHA256**, then temporarily stages
only the reviewed binary/scripts. On exit it restores the prior Downloads
copies. The underlying benchmark runner independently saves/restores the
TEST DLL and mode markers once it has verified game process exit.

## One command for the first diagnostic session

Once this PR is **approved** and its exact tested Git commit is present in the
existing `~/OpenLRR-Agent` checkout, the command is:

```bash
python3 "$HOME/OpenLRR-Agent/scripts/macos/menu-diagnostic-session.py" --session 1 --run
```

Without `--run`, this is a no-game preflight. **Do not execute this command
against an unreviewed or untested checkout.** A final exact commit-pinned
checkout + execution command will be provided with the tested PR.

Session 1 performs *two identical 60-second baseline runs*, while optionally
attempting one **read-only, local-only** 3-second Wine CPU stack sample.
It records architecture, macOS version, best-effort Wine version, known
graphics markers, and external Wine drive names. It does **not** transmit
raw CPU stacks or personal Mac filesystem paths.

**Requirements:** existing isolated `OpenLRR Menu Test.app` and lab checkout,
the previously configured local Python venv, GitHub CLI authentication
authorized to the private `MaultzLabs/OpenLRR-Test-Results` repository,
macOS `lsof`, `shasum`, `git`, `python3`, and a windowed login session
that permits launching the TEST game. No new global install is performed.
The profiler may fail without macOS profiling rights; that is explicitly
recorded as unavailable. The package does not require Screen Recording
permission because it does **not yet perform screenshot/video capture**.

Estimated first session: **5–10 minutes**, depending on Wine startup,
GitHub download/upload, and exit detection. The bounded outer watchdog is
15m50s. If shutdown verification fails, the existing safety mechanism leaves
an unresolved lock and backup rather than forcibly terminating Wine or
starting another test.

Results:

- Local: `~/Downloads/OpenLRR Benchmark Runs/autobenchmark-*/`
- Session report: `~/.local/share/openlrr-agent/menu-diagnostic-sessions/session_*/report.json`
- Local-only log: same session directory, `runner-local-only.log`
- CPU sample (if available):
  `~/.local/share/openlrr-agent/wine-cpu-profiles/`
- Private telemetry: `MaultzLabs/OpenLRR-Test-Results/runs/`.

The report explicitly distinguishes evidence `missing` from `passed`.
Only the existing uploader transmits approved counter CSV, summary and
lifecycle receipt to the private repository. Local machine metadata,
screenshots/video, and raw stacks **are not automatically uploaded**.

## The six-session sequence and stopping gates

1. **Diagnose** (implemented): Two equal-mode baseline runs, local CPU sample
   if possible, lifecycle evidence. If the CPU sampler has no supported
   process/permission, record this rather than infer CPU functions.
2. **Compare** (implemented, only following Session 1 review):
   `--session 2 --run` invokes alternating
   baseline/nowait/baseline/nowait, equal duration, same reviewed DLL.
   The two A/B pairs are preliminary, NOT sufficient for a promotion claim.
   NOWAIT may skip presentation; visual quality must be checked.
3. **Repair** (BLOCKED pending evidence): Examine the CPU stack and graphics
   trace and produce a targeted code/config hypothesis. A new candidate
   requires human review, exact provenance and stronger execution controls.
4. **Refine** (BLOCKED): Repeat >=5 comparable pairs across independent tests;
   investigate crashes and measure input response and audio.
5. **Validate** (BLOCKED): Independent, temporally bound visual QA and
   regression comparisons, multiple session stability and audio/input review.
6. **Final verification** (BLOCKED): Independently time actual delivered display
   frames and confirm sustained >=60 **visible** FPS, menu completeness,
   responsive controls, working audio, and successful exits. Do not confuse
   DirectDraw present calls or logical frame flips with visible frames.

Not every session will be needed; more than six may be required. Advancing
the pipeline is evidence-driven, not automatic.

## Safe stop and recovery

To stop a running supervised TEST session:

```bash
touch "$HOME/.config/openlrr-benchmark/STOP"
```

This requests graceful shutdown. No worker should be restarted while a
supervisor/TEST lock exists or Wine has open TEST game handles. A failed
session is **not retried automatically**; inspect the TEST game's state and
the local backup before any manually authorized recovery.

**No working-game changes:** the scripts target only the literal fixed TEST
app directory. A path/symlink guard refuses ambiguous targets. The separate
Wine host-filesystem mapping audit still cannot attest to a true VM sandbox:
the existing previously reviewed diagnostic DLL is permitted, but no AI
generated executable is allowed in this package.
