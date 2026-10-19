# OpenLRR Game Composer: native MAP draft backend

The new `scripts/composer/native_map_composer.py` can generate **real binary
LEGO Rock Raiders MAP files** rather than just descriptive concept art.

The converter is grounded in the RRU Knowledge Base MAP specification:
- https://kb.rockraidersunited.com/Terrain_map
- https://rockraidersunited.com/topic/1819-how-to-add-custom-levels-in-game/

The MAP container starts with `MAP `, a little-endian 32-bit payload-size
field (file length minus eight), and two little-endian 32-bit dimension
values, followed by row-major unsigned 16-bit tile data. The stored values
are one greater than the visible playable tile dimensions.

## What it generates today

Five bounded layers for a reproducible draft level:

- `dugg.map` — exposed caverns and undiscovered walls.
- `surf.map` — terrain (solid rock, dirt, loose/hard rock, ore seams, crystal seams).
- `high.map` — conservative fixed terrain height.
- `cror.map` — safe one-crystal and one-ore deposits, never invalid crash-prone values.
- `path.map` — empty safe path layer.

It also outputs a structured JSON blueprint, an explicitly **review-only**
Lego.cfg configuration *fragment*, and SHA256 checksums. The independent
binary round-trip decoder validates exact size, dimensions, and cell count.

The validator checks deterministic seed bounds, map geometry, solid-rock
edges, connected exposed cavern, reachability of crystal deposits through
diggable tiles, available resource quantity, safe native tile values and a
non-executable / non-installation authority.

## Usage

No files or game processes created:

```bash
python3 scripts/composer/native_map_composer.py \
  --name CrystalFrontier --width 24 --height 20 \
  --seed 1989 --crystal-goal 12 \
  --out /tmp/CrystalFrontier
```

To actually emit a **draft** pack in a new, empty folder (not in the game):

```bash
python3 scripts/composer/native_map_composer.py \
  --name CrystalFrontier --width 24 --height 20 \
  --seed 1989 --crystal-goal 12 \
  --out /tmp/CrystalFrontier --compose
```

Output under `~/Applications` or `~/OpenLRR-Agent` is blocked, and existing
output cannot be silently overwritten.

## Not yet playable

These valid MAP *containers* are not proof that the game can load the entire
mission. A playable level still requires integration with an existing game's
level slot or a correctly provisioned new Lego.cfg level entry, and may require
objects, triggers, NERPs/NPL mission scripts, level objectives, preview and
other assets. This initial composer does not fabricate licensed assets,
modify the user's working installation, change Lego.cfg, or run the game.

The intended subsequent composer stages are: schema-based mission graph,
validated NERPs scripting, level-object placement, asset-provenance checking,
actual TEST-level loading, visual QA and gameplay simulation. Only after those
pass should generated content be considered ready for play.
