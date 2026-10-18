# Diagnostic-only DirectDraw wall/CPU probe

Purpose: distinguish a windowed `DirectDrawSurface::Blt` call that consumes CPU
from one that spends most of its wall time blocked or descheduled.

The new `MenuPerf::WindowBltCpuScope` is active **only** when
`menuperf.enable` exists inside the isolated TEST game's working directory.
It samples `GetThreadTimes` before and after the existing Blt call. Rendering
flags, surfaces, error handling and output remain unchanged. No network access,
new game assets, arbitrary commands or auto-deployment.

The existing `menuperf.csv` format is preserved and includes four additional
operation rows:

- `window_blt_thread_cpu`: thread CPU time over successfully sampled calls
- `window_blt_slow_thread_cpu`: thread CPU time for calls whose wall duration
  exceeds 1,000 milliseconds
- `window_blt_cpu_unavailable`: count of calls whose thread timing was unavailable
- `window_blt_slow_low_cpu`: count of >1,000-ms wall calls with <=20% thread CPU

The analyzer enforces that successful and unavailable sampling counts sum to
all windowed DirectDraw Blt calls. Missing CPU samples are `null` means
**unknown**, never zero CPU. The observer receives only these sanitized numbers.

**What it can tell us:** many >1-second calls with little thread CPU time
support a wait/descheduling hypothesis; high CPU time favors active processing.
**What it cannot tell us:** which Wine function, compositor, host driver or GPU
operation is responsible, or whether a frame reached the physical screen.

This build should be tested only via the isolated `OpenLRR Menu Test.app`,
using the existing SHA256-pinned `diagnostic-one-shot.sh` and the supervisor's
STOP/PAUSE, process-exit and upload checks. It is not a game repair and should
not be auto-installed on the working game.
