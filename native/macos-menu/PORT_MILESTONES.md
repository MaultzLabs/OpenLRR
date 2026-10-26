# Native port acceptance ledger

Updated 2026-10-23. The earlier 80% completion estimate is withdrawn: there was no complete denominator or full-game acceptance run. Do not assign a completion percentage from source volume, passing parser tests, or a successful compile.

| Area | Evidence and status | Required acceptance |
| --- | --- | --- |
| Original menu | Native implementation exists | Original assets, transitions, input, exit and sustained visible frame timing on Mac |
| Terrain texture regression | PR #61 fixes Textures::Rock reference resolution; portable tests and ARM64 compile pass | Rock, Ice and Lava missions visibly use their correct textures |
| Menu/mission audio | PR #61 separates players and stops menu restart in missions; compile passes | Audible transitions with original audio; OGG conversion currently required |
| Movement and wall clearance | PR #61 exact destinations and swept footprint tests pass | Repeated in-level moves, wall/corner tests and mid-move retargeting on Mac |
| Raider models | Original AE/LWS/LWOB stand/walk integration in development | Original geometry, materials, hierarchy, pivots, heading and animation timing verified against retail |
| First-person | Not implemented in native port | Original selection, camera attachment, control and return to overhead |
| Excavation | Separate prototype PRs; not full retail behavior | Strength/timing, reveal, rubble, resources, sound and animation |
| Building/economy | Incomplete | Construction, power, ore/crystals, upgrades, dependencies |
| Vehicles and AI | Incomplete | Original models, boarding, navigation, tasks and collision |
| Mission scripts/objectives | Partial callback implementation | All mission and tutorial scripts plus completion/failure behavior |
| Saving/loading gameplay | Original save inspection exists; full native persistence incomplete | Round-trip a played mission without state loss |
| Full-game performance and fidelity | Not established | End-to-end campaign sessions and sustained Mac performance |

Next selected milestone: verify the original Raider model/material and stand/walk pipeline, then implement first-person camera/control on the same collision-aware movement foundation. Dynamic object/building collision, original movement speed and animation timing remain separate from static terrain clearance.

Daily reporting must name commits, tests actually run, user-visible results, remaining failures and the next chosen task. A day without validated advancement must be reported as such; no automatic 5% credit or five-day completion promise.


## Model materials and terrain follow-up — PR #66

Implemented original LWOB TIMG/TSIZ/TCTR/TFLG bitmap projection and UView v2
per-corner coordinates, preserving texture seams. Original BMPs resolve from
the component directory and configured shared texture directory. Dry exposed
terrain uses floor material; wall sides retain rock/seam material. Floor UVs
are aligned to map tiles on odd-sized levels.

Added an RRU ZIP music importer: audio-only Track00–98 extraction, local M4A
conversion, no Windows DLL installation, no overwrite of existing tracks.
Four local FFmpeg integration tests pass, including corrupt-track rollback,
path confinement and duplicate rejection. Swift regression/ARM64 CI remains
the authority for build status. No original asset visual/audio validation yet.
The actual RRU music ZIP download is pending the site's terms confirmation.
Next: real-asset material review and first-person camera/control.
