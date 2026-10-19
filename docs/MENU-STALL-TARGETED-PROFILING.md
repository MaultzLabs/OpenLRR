# OpenLRR Mac TEST: sample the stall, not the introduction

This is a **draft, isolated diagnostic change**. It is not a game fix.
No working game, Wine prefix configuration, DLL hash, or run-count is changed.

The existing two-baseline Session 1 now arms its one optional 3-second
native macOS `sample` capture **only after the same live TEST run reports
two consecutive, fully flushed one-second telemetry groups** with:

- zero `movie_update` operations (the intro is no longer active in telemetry)
- at least one `window_blt_over_1000ms` DirectDraw call in each group
- at least one completed `frame_flip` in each group

The code requires an exact CSV header, completed interval suffix,
bounds file size, rejects symlinks, and respects existing STOP/PAUSE and
macOS process identity checks. If no matching stall appears, it records
`unavailable_no_repeated_live_menu_stalls`. It **never** falls back to
sampling an arbitrary Wine process or unverified menu phase.

If sample succeeds, raw stack traces remain LOCAL. The new read-only
parser reports **only allowlisted component families** and their exclusive
leaf-stack observation counts. It accounts for macOS sample's
`+ | : !` call-tree guides to avoid naive whitespace-depth errors and
avoids double counting inclusive parent samples. These are **NOT CPU
percentages, wall-time fractions, proof of which Wine driver is loaded,
or verified visible frames per second**. Unsupported raw report formats
return `unrecognized_sample_format`; no raw symbol/address/path is emitted.

For an existing successful capture, without launching a game, the Mac can
later run:

```sh
python3 "$HOME/OpenLRR-Agent/scripts/macos/wine-cpu-sample.py" --summarize-latest
```

No new user action is requested now. GitHub fixture tests validate only
offline parsing, trigger selection, and safety boundaries. Mac process
sampling remains **unverified** until a separately approved TEST session.
