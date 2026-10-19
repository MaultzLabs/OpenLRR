# Mac TEST Wine CPU sampling companion — read-only, local traces

The October 18 CPU-probe runs recorded 31 DirectDraw Blt calls longer than
one second in each baseline run, almost all with substantial reported
calling-thread CPU time. These measurements do NOT identify the exact
Wine function or macOS driver involved.

The new `scripts/macos/wine-cpu-sample.py` prepares the next discriminating
measurement: a short, opt-in native macOS `sample` capture of an **already
running Wine process** belonging to the isolated OpenLRR TEST game.

The tool does not start, terminate, install or modify any game. It finds
candidate process IDs ONLY from files open in the fixed TEST game directory,
checks each candidate's process command for Wine/Rock Raiders, and requires
exactly one match. It then re-verifies the same PID just before sampling.

Default execution does nothing:

```bash
python3 "$HOME/OpenLRR-Agent/scripts/macos/wine-cpu-sample.py"
```

To perform one opt-in read-only 3-second CPU sample, run while the explicitly
supervised TEST game is actually running:

```bash
python3 "$HOME/OpenLRR-Agent/scripts/macos/wine-cpu-sample.py" --capture
```

STOP/PAUSE disable the profiler. Sampling has a fixed 3-second duration,
20-ms requested sample interval, a subprocess timeout, output-size cap and
strict local file permissions. Failure leaves the local trace for inspection.

**Privacy:** a native macOS `sample` trace can reveal application paths and
stack addresses. It stays under
`~/.local/share/openlrr-agent/wine-cpu-profiles/` and is **never uploaded**
by this tool. The optional local JSON summary contains only names and counts
of recognized library-family mentions. Those counts are not CPU percentages,
do not prove driver blame and do not confirm actual displayed FPS.

The next integration will attach this profiler during an approved supervised
TEST run and align timing against the known long-blit cadence, without
launching any new AI-authored DLL. Mac profiling tool availability,
permissions and exact Wine process naming cannot be verified by GitHub CI.
