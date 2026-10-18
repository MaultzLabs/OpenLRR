# Menu performance diagnostic build

Experimental build for OpenLRR v0.0.0.7-hotfix1, targeting legacy DirectDraw menu latency on Wine/dgVoodoo/DXMT.

**Do not replace your functioning installation.** Duplicate the working OpenLRR.app wrapper and test only in the duplicate.

The patched DLL works normally without optional marker files. In the game's working directory, create either marker before launching:
- `menuperf.enable`: writes `menuperf.csv` with ~1-second timing aggregates for FLIC lock, decode, unlock, blit; image blit; frame presentation; movie update.
- `menuperf.optimize`: experimental skip of FLIC surface lock/unlock when no new animation frame is decoded. **Off by default.**
- Both: instrumented optimized experiment.

Always fully quit/restart after changing markers. Check actual Wine working directory if CSV does not appear. Timer overhead is modest but nonzero. This patch is **not a proven fix**. Compare at least one minute of slow main menu and one minute of smooth gameplay without enabling optimization; only test optimization after reading CSV results. Keep the known-good `dgVoodoo.conf`, including `FastVideoMemoryAccess = false`.

### Build
A GitHub Actions workflow builds **Release | x86** with Visual Studio 2019 v142 tools on windows-2022, validates 32-bit PE architecture, and uploads the resulting `openlrr.dll` as an artifact. GitHub Actions needs to be enabled for this fork. This exact Windows build has not yet been verified.

## Second-stage windowed presentation investigation

The first `menuperf.csv` measured 384 intervals / approximately 491 seconds. Windowed `frame_flip` occupied 471.8 seconds (96.1% of wall time), while image blits, FLIC decode and surface locks were negligible in comparison. At 640×480, the 2D main menu visibly stalled while 3D missions ran fast. The first-stage measurement surrounds the complete `DirectDraw_Flip()` body, which on windowed mode calls `DirectDraw_BlitBuffers()` and ultimately `IDirectDrawSurface4::Blt(..., DDBLT_WAIT, ...)`. These measurements strongly implicate **windowed frame presentation**, not FLIC decoding.

New CSV columns include `nowait` (0 by default). New metric rows:
- `window_coordinate`: window-coordinate conversion / window position calculation.
- `window_present_blt`: actual DirectDraw front-surface blit (blocking when `nowait=0`).
- `fullscreen_flip`: direct fullscreen Flip (if used).

With only `menuperf.enable`, the exact original blocking `DDBLT_WAIT` behavior remains active. No renderer settings change.

**Experimental alternate path:** add an empty marker `menuperf.nowait` to disable `DDBLT_WAIT` on the windowed present Blt. This can return `DDERR_WASSTILLDRAWING`, skipping frames; it may or may not cure stalls and is NOT enabled by default. Only attempt after the new diagnostic CSV confirms that `window_present_blt` accounts for most of `frame_flip`. Retest on the duplicated app only, and remove `menuperf.nowait` to restore the original operation. The `menuperf.optimize` flag for FLIC locks should remain off because FLIC locks are not dominant in the first log.
