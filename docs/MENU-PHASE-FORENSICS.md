# OpenLRR frame-presentation phase forensics (read-only)

The main-menu benchmark's full-run average mixes different stages. This tool distinguishes the opening `movie_update` phase from an explicitly **unverified** steady post-movie proxy, excluding the first two zero-movie telemetry groups as a transition. It never claims the menu was visually verified.

It counts each completed flush group by the last `window_blt_slow_low_cpu` metric, **not by the `seconds` field** (elapsed interval time can repeat). It summarizes slow DirectDraw call counts, their latency range and cadence, and time spent presenting vs outside flip. It intentionally does not infer per-frame distributions from interval maxima, actual visible FPS, or a root cause.

Example using existing local measurements, without launching the game:

```sh
python3 scripts/macos/menu-phase-forensics.py \
  "$HOME/Downloads/OpenLRR Benchmark Runs/autobenchmark-2026-10-19_09-14-28/menuperf.csv" \
  "$HOME/Downloads/OpenLRR Benchmark Runs/autobenchmark-2026-10-19_09-15-53/menuperf.csv"
```

This is an **independent offline research tool**, not called by existing supervisors. It launches no Mac game, modifies no graphics configuration, accesses no network/credentials, and writes no files. It accepts only the reviewed instrumented CSV schema. Existing TEST game safety boundaries remain unchanged. Results inform a later focused experiment, not a promotion or 60-visible-FPS claim.
