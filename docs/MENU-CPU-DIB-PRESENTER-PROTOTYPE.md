# OpenLRR TEST-only CPU DIB window presenter candidate

## Narrow hypothesis

The full-run benchmarks show ~30 calls >1 second per minute in windowed
`IDirectDrawSurface4::Blt(front, back, DDBLT_WAIT)`, with calling-thread CPU
time close to the call's wall time. This is an *unverified hypothesis*: a
software pixel-copy presentation may avoid the slow DirectDraw primary-surface
translation path. It could instead be **slower**, fail to map the 3D backbuffer,
or produce a visible regression.

The earlier `menuperf.gdi` path called **DirectDraw backbuffer GetDC** and
stalled; this experiment instead tries **backbuffer Lock (read-only)** followed
by Win32 `StretchDIBits` to the client HWND. It does not call backbuffer
GetDC. It accepts only packed, top-down RGB565, RGB555, or XRGB8888 with
strict matching pitch, masks, dimensions and no palette. Unsupported/error
paths unlock and fall through to the original blocking DirectDraw Blt.

## Control, containment, and telemetry

This path is opt-in ONLY when `menuperf.dib` exists in the **TEST game's**
working directory. Normal rendering is byte-for-byte algorithmically
unchanged when the marker is absent. This branch does **not** change the Mac
runner or approved DLL hash and does **not** install any DLL or marker. It
doesn't authorize an automatic run.

The instrumentation adds discrete `dib_window_attempt`,
`dib_backbuffer_lock`, `dib_stretchdibits`, `dib_backbuffer_unlock`,
`dib_present_accepted`, and `dib_present_fallback` counters. The older
8-column CSV schema and final interval marker are preserved. The analyzer
uses these counters to distinguish DIB from DirectDraw presentation and to
reject partial/inconsistent logs, without confusing source-mode flags. It
reports DIB time + fallback time, and does not claim verified visible FPS.

## Proposed later validation (not performed)

1. Obtain a reviewed Win32 x86 DLL from GitHub CI; never use it in the
   normal game. Preserve hashes and backup/restore for the TEST DLL.
2. Compare **one original baseline vs one explicitly opt-in DIB candidate**
   with identical wrapper/window/input settings. Abort on lock stalls,
   unverified lifecycle, malformed telemetry, unstable input/audio or visual
   corruption; never silently promote.
3. Inspect screen output independently because telemetry calls can be
   accepted without displaying a frame.
4. Reject the candidate unless both speed **and visible correctness** improve.

The test methodology requires a distinct reviewed Mac plan; existing
`menu-diagnostic-session.py` remains baseline-only (or existing nowait A/B).
No claim that this code runs under Apple Silicon Wine has yet been made.
