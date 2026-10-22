# Cross-platform OpenLRR evidence bridge

**Status: offline comparison adapter.** This does not claim the 1999 game has
run in GitHub-hosted Windows. The other laboratory's
`lab-windows-virtual-playtest-v1` branch has verified a **synthetic** Win32
fixture, but its private original-game test still requires an interactive
Windows GUI machine and game files.

## Why this exists

The Apple Silicon Mac and the Windows GUI controller produce fundamentally
different evidence. This bridge lets both environments feed the porting lab
without claiming independently captured clicks occurred at the same instant,
or that two identical inputs produced the same internal game result.

Mac producer:
`native/macos-menu/tools/gameplay-capture/index_clips.py`
- `analysis-index.json`: relative video times, mouse/key action records,
  game command/NERPs IDs, and (where instrumentation is present) Wine events.
- Absolute host clock is an *approximate* video origin, not an exact video frame
  presentation timestamp.

Windows producer (developed independently):
`lab/windows-playtest/playtest.py` on
`lab-windows-virtual-playtest-v1`
- `report.json`: bounded scenario step actions, timestamps at one-second
  precision, window screenshot records, and optional measured visual changes.
- **Current Windows reports do not record which key was pressed**, do not
  expose NERPs/internal game state, and do not attest that a run was made on
  the original game rather than a synthetic fixture.

## Run locally on an authorized, private pair of reports

```bash
python3 lab/evidence-bridge/compare.py \
  --mac-index "/path/to/recovered-clips/analysis-index.json" \
  --windows-report "/path/to/windows-playtest/report.json" \
  --out "/path/to/private/comparison.json"
```

The destination must not already exist. It is created with file mode 0600.
The bridge reads only the two JSON files, never screenshots, movies, game
assets, Wine logs, or source binaries. It never uploads anything.

The produced `openlrr-cross-platform-evidence-v1` schema includes:
- Source-specific coverage: recordings, input actions, menu/NERPs function IDs,
  and measured Windows visual changes.
- Ordered input-token overlap, labeled as **exploratory only**. A screenshot
  comparison, controller "passed" status, and click/key overlap are not
  proof that gameplay is equivalent.
- Missing-evidence gates for authentic Windows game execution, actual
  game-state effects, and matched scenario playback.

## Next independent integration work

1. Have Windows report each actual key name, input coordinates normalized
   to client bounds, screenshot timestamps with subsecond precision, and
   authentic game identity evidence. Its owner can implement these on the
   Windows playtest branch without editing the Mac capture branch.
2. Let both laboratories record the **same bounded scenario** with agreed
   checkpoints (menu item selected, NERPs state, terrain, resources).
3. Link frame fingerprints and screenshot similarity in a separate, strictly
   window-scoped visual-QA worker. A numeric mean pixel difference inside one
   Windows run does not measure *cross-platform* visual fidelity.
4. Compare actual internal-state transitions before reporting functional
   parity, using timestamps relative to each local recording and explicit
   anchors, never cross-machine wall-clock equality.

Synthetic tests (no Mac or real game needed):

```bash
python3 -m unittest discover -s lab/evidence-bridge/tests -v
```
