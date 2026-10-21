# Native Map3D port: original-engine implementation references

## Important source gap

The current `src/openlrr/game/world/Map3D.cpp` in this repository contains
only the fixed-address global `s_SurfaceMap_Points10` and commented function
prototypes. The paired `Map3D.h` maps functions such as `Map3D_Create`,
`Map3D_Update` and `Map3D_GetIntersections` to addresses inside 32-bit
Windows `LegoRR.exe`. **These are missing standalone source implementations,
not simply Windows system API imports.** They cannot be invoked from native
ARM64 macOS code.

A useful independent research reference is
[Project Reversio's reverse-engineered `map3d.c`](https://github.com/ProjectReversio/LegoRockRaiders/blob/master/src/LegoRR/map3d.c).
Unlike OpenLRR's stub, it contains approximately 1,500 lines implementing
creation, roughness, normals, coordinate transformations, hit-testing,
texture transitions, and visibility. Its accompanying
[`detail.c`](https://github.com/ProjectReversio/LegoRockRaiders/blob/master/src/LegoRR/detail.c)
explains original texture-atlas selection.

**Reuse policy:** Project Reversio's repository does not currently advertise
a license granting general code reuse. Treat those files as behavioral
research, **do not copy third-party implementation code** into our repository
without checking permissions; write independent testable native algorithms.

Another behavioral cross-check is
[Rock Raiders Web](https://github.com/Scarabol/rock-raiders-web), whose 3D
terrain meshes, detailed original ProMesh handling, autonomous jobs, UI,
pathfinding and scripts illustrate that a portable engine is feasible.
That repository likewise has no license identified in our audit; do not copy
its implementation without permission.

## Original Map3D behavior we can now reproduce independently

- Grid: original `high.map` contains vertices; world block dimensions are
  map width/height less one. Native `LevelWorld` already implements this.
- Origin: world terrain is centered, with default `BlockSize = 40`.
  The original flips its Y axis; the native viewer uses SceneKit X/Z.
- Height: the original uses a height sample times `RoughLevel` (default 6);
  the native meterless scene scales by `RoughLevel / BlockSize`.
- **Adaptive triangulation:** retail chooses between the two quad diagonals
  using the absolute difference between opposite corner height samples;
  ties preserve the default. Implemented and regression-tested in
  `NativeTerrainMesh.usesUpperLeftDiagonal`. Previous native code always
  chose the same diagonal.
- Texture atlas: original bitmap names append two hexadecimal digits
  representing the column and row of a 16×16 tile atlas. The signed texture
  enum is an **8-bit surface index**. The current
  `OriginalTerrainTextureCatalog` locates BMPs but still uses approximate
  wall-transition IDs and UVs.
- Detailed rock faces: original per-block `Detail` meshes and ProMesh
  assets are distinct from ordinary low-detail terrain quads. Current native
  raised cubes are **not an authentic replacement**. Mesh orientation,
  corner classification, proper world scaling, textures and lighting remain.
- Ray picking: the original uses terrain-aligned viewport rays and searches
  candidate blocks. SceneKit hit-testing is a temporary bridge, not identical.

## Rapid experiment queue (keep independently revertible)

1. Verify adaptive diagonals on actual `high.map` and compare with retail
   screenshots. Portable synthetic tests now cover both cases.
2. Load original per-block `World/ProMeshes` geometry via the existing
   `LightWaveObject` parser into a **toggleable** SceneKit diagnostic; avoid
   inventing boulder/rock shapes and preserve a quick fallback.
3. Resolve actual `Lego.cfg` texture-set descriptors into correct biome,
   mesh and atlas paths. Stop guessing from "rock" text when multiple sets
   exist.
4. Reproduce floor/wall/corner/recharge-seam geometry and UV rotations,
   then fog, roof, real camera orientation and selection outlines.
5. Keep mission logic a separate data/model layer; do not tie rock collisions
   and drilling to SceneKit node identity.
6. Reimplement executable-bound world, AI, UI and NERPs globals as owned
   native state instead of attempting any 32-bit memory-address call.

## Success criteria

A Mac compile and portable unit tests are necessary but **not sufficient**.
Do not label a level visually faithful until it is compared against actual
1999 Windows PC gameplay and rendered using the user's legally supplied
original WAD assets. No copyrighted source media is checked in.
