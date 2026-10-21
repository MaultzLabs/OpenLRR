# Opt-in NERPs call tracing — research branch only

**Not installed in the working OpenLRR game.** This feature is confined
to the source branch `lab-nerps-trace-optin-v1`.

## Why it is required

OpenLRR's Options > Logging menu controls normal debug/info/warning output,
but it does not emit complete internal NERPs function dispatch records.
The Cheat > No NERPs option explicitly *disables* mission scripts and
must remain unchecked for a real baseline.

`src/openlrr/game/mission/NERPsFile.cpp` contains an independent
implementation of the NERPs instruction interpreter. For its compiled
`.npl` bytecode, there are 294 possible named function signatures
in the original 32-bit `LegoRR.exe` function table.

## Compile and runtime gates

This trace is **off by default**. To enable it, *both* conditions must hold:

1. A dedicated 32-bit Windows TEST DLL has been compiled with
   `OPENLRR_LAB_NERPS_TRACE` defined. The normal compiled DLL does **not**
   gain this recorder.
2. That disposable TEST process has the `OPENLRR_NERPS_TRACE_PATH`
   environment variable explicitly set to an output filename in a private,
   writable location. If absent, **zero** NERPs trace files are opened.

This branch's GitHub Actions compiles the experimental instrumented
Windows x86 build for syntax/ABI testing only. **The resulting DLL is
never published or loaded in the user's existing working game**.

## Captured data and sample policy

- Function ID and sanitized name from the original 294-entry table
- Instruction index (program counter), script-update counter
- Action/predicate kind, up to 3 integer arguments and return value
- Windows/Wine UTC and monotonic tick stamps
- **Only executed actions** (never false branches)
- Repeated predicates sampled once per second per function ID or whenever
  their result changes, rather than every frame
- Hard stop at 100,000 records, buffered locally

No path, free-form argument text, chat content, Windows handles, pointers,
microphone recordings or desktop content is logged.

The Mac gameplay recorder's `--nerps-log` option follows an already
existing file passively. It does not inject or enable instrumentation, and
keeps the original game/Wine trace data local. It maps the verified
function name/ID, action or predicate, source clock, and numeric arguments
into the same session JSONL as the real video and key/mouse observations.

### Limitations

- The function-call timestamp is the Windows/Wine system clock, with
  separate *host log read* time recorded by the Mac supervisor; the clocks
  must be aligned using common events, not assumed frame-perfect.
- `GetTickCount64` and game `frame` IDs are not interchangeable with
  the video's output frame index.
- Predicate sampling may miss brief intermediate values. Action function
  execution is more important for Chief dialogue and mission progression.
- NERPs functions called from outside the instrumented interpreter, or by
  unmodified original executable code, are not necessarily visible.
- A passing compiler check is **not** permission to install the DLL in a
  working Wine prefix. Isolated local testing and exit cleanup checks first.
