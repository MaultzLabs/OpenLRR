# Investigate multiple writable TEST telemetry owners

Observed on **October 19, 2026**: the TEST Mac run returned
`unavailable_multiple_writable_test_owners`. The game benchmark, source hash,
lifecycle check and private upload succeeded; no CPU stack was captured.

The optional profiler now distinguishes a uniquely named
`LegoRR.exe` process among multiple Wine/helper processes that inherited
a writable descriptor to the exact verified TEST `menuperf.csv`.
It does **not** select the smallest PID, a random Wine name, an
unsupported descendant, or a read-only file observer. Two plausible
game-executable owners or only Wine-generic owners still fail closed.

A new opt-in **inspect-only** command produces sanitized category counts
and `unique_target_verified` or `ambiguous_or_unrecognized`. No PIDs,
commands or paths are emitted; it never launches a game or calls `sample`.
It only works while the isolated TEST game is running and its telemetry
file is open. If it is not, it fails closed without touching the game:

```sh
python3 "$HOME/OpenLRR-Agent/scripts/macos/wine-cpu-sample.py" --inspect-writers
```

Offline GitHub mock tests cannot prove Mac process-role naming, availability
of `lsof` fields, or success of macOS `sample`. The 60+ visible FPS target,
audio and input also remain unverified. No gameplay or graphics changes.
