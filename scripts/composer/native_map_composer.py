#!/usr/bin/env python3
"""Generate a reproducible, isolated LEGO Rock Raiders native MAP *draft pack*.

This is the first binary game-composer backend, NOT an automatically playable
mission: a complete level still requires real game assets, level configuration,
objects, and possibly NERPs/PTL content. Never modifies the working game.
"""
from __future__ import annotations

import argparse
from collections import deque
import hashlib
import json
import os
from pathlib import Path
import random
import re
import struct
import sys

MAX_AXIS = 48
MIN_AXIS = 12
MAX_BYTES = 2_000_000
SYMBOLS = frozenset("#.dhrco")
TERRAIN = {"#": 1, ".": 4, "d": 4, "h": 2, "r": 3, "c": 10, "o": 8}
DIGGABLE = frozenset(".dhrco")
MAP_NAMES = {
    "dugg.map": "predug",
    "surf.map": "terrain",
    "high.map": "surface",
    "cror.map": "cryore",
    "path.map": "path",
}
MAP_CONFIG = (
    ("PredugMap", "dugg.map"),
    ("TerrainMap", "surf.map"),
    ("SurfaceMap", "high.map"),
    ("CryoreMap", "cror.map"),
    ("PathMap", "path.map"),
)
SAFE_NAME = re.compile(r"^[A-Za-z][A-Za-z0-9_-]{2,39}$")


def neighbors(x: int, y: int, w: int, h: int):
    for xx, yy in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
        if 0 <= xx < w and 0 <= yy < h:
            yield xx, yy


def validate_blueprint(blueprint: dict):
    if type(blueprint) is not dict or set(blueprint) != {
        "schema_version", "name", "width", "height", "seed",
        "crystal_goal", "start", "rows", "native_install_authorized",
    }:
        raise ValueError("Invalid or unauthorized level blueprint")
    w, h = blueprint["width"], blueprint["height"]
    if (type(w) is not int or type(h) is not int
            or not MIN_AXIS <= w <= MAX_AXIS
            or not MIN_AXIS <= h <= MAX_AXIS):
        raise ValueError("Unsupported map dimensions")
    if (type(blueprint["name"]) is not str
            or not SAFE_NAME.fullmatch(blueprint["name"])
            or type(blueprint["seed"]) is not int
            or not 0 <= blueprint["seed"] < 2**32
            or blueprint["native_install_authorized"] is not False):
        raise ValueError("Unsafe identity, seed or installation authority")
    rows = blueprint["rows"]
    if (type(rows) is not list or len(rows) != h
            or any(type(r) is not str or len(r) != w
                   or not set(r).issubset(SYMBOLS) for r in rows)):
        raise ValueError("Invalid native map tiles")
    start = blueprint["start"]
    if (type(start) is not list or len(start) != 2
            or any(type(v) is not int for v in start)):
        raise ValueError("Invalid starting tile")
    x0, y0 = start
    if not (0 <= x0 < w and 0 <= y0 < h) or rows[y0][x0] != ".":
        raise ValueError("Starting tile must be exposed cavern")
    if (any(v != "#" for v in rows[0] + rows[-1])
            or any(row[0] != "#" or row[-1] != "#" for row in rows)):
        raise ValueError("All edges must be solid rock in draft composer")
    goal = blueprint["crystal_goal"]
    crystals = sum(row.count("c") for row in rows)
    if type(goal) is not int or not 1 <= goal <= crystals <= 100:
        raise ValueError("Crystal objective exceeds reachable crystal resources")

    exposed = {(x0, y0)}
    frontier = deque([(x0, y0)])
    while frontier:
        x, y = frontier.popleft()
        for xx, yy in neighbors(x, y, w, h):
            if (xx, yy) not in exposed and rows[yy][xx] == ".":
                exposed.add((xx, yy))
                frontier.append((xx, yy))
    if len(exposed) != sum(row.count(".") for row in rows):
        raise ValueError("Disconnected predug caverns are not approved")
    # A mineral must be reachable after a sequence of excavations from the
    # initial cavern without tunneling through undiggable solid rock.
    accessible = {(x0, y0)}
    frontier = deque([(x0, y0)])
    while frontier:
        x, y = frontier.popleft()
        for xx, yy in neighbors(x, y, w, h):
            if (xx, yy) not in accessible and rows[yy][xx] in DIGGABLE:
                accessible.add((xx, yy))
                frontier.append((xx, yy))
    if any((x, y) not in accessible
           for y in range(h) for x in range(w) if rows[y][x] == "c"):
        raise ValueError("Crystal seam unreachable through diggable terrain")
    return {"width": w, "height": h, "crystals": crystals,
            "exposed_tiles": len(exposed), "reachable_tiles": len(accessible)}


def generate(name: str, width: int, height: int, seed: int,
             crystal_goal: int) -> dict:
    if (type(width) is not int or type(height) is not int
            or not MIN_AXIS <= width <= MAX_AXIS
            or not MIN_AXIS <= height <= MAX_AXIS):
        raise ValueError("Unsupported level size")
    if (type(seed) is not int or not 0 <= seed < 2**32
            or type(crystal_goal) is not int or not 1 <= crystal_goal <= 100):
        raise ValueError("Invalid seed or crystal objective")
    rng = random.Random(seed)
    rows = [["#" if x in (0, width - 1) or y in (0, height - 1)
             else "d" for x in range(width)] for y in range(height)]
    cx, cy = width // 2, height // 2
    # Always create one navigable connected exposed cavern.
    for y in range(cy - 2, cy + 3):
        for x in range(cx - 2, cx + 3):
            rows[y][x] = "."
    for _ in range((width * height) // 40):
        x, y = rng.randrange(2, width - 2), rng.randrange(2, height - 2)
        if rng.random() < 0.3:
            rows[y][x] = "h"
        elif rng.random() < 0.5:
            rows[y][x] = "r"
    candidates = [(x, y) for y in range(1, height - 1)
                  for x in range(1, width - 1) if rows[y][x] != "."]
    rng.shuffle(candidates)
    if len(candidates) < crystal_goal:
        raise ValueError("Too many requested crystal seams for map geometry")
    for x, y in candidates[:crystal_goal]:
        rows[y][x] = "c"
    # Some ore but never at the expense of the guaranteed crystal goal.
    for x, y in candidates[crystal_goal:crystal_goal + max(1, crystal_goal // 2)]:
        rows[y][x] = "o"
    data = {
        "schema_version": 1, "name": name,
        "width": width, "height": height, "seed": seed,
        "crystal_goal": crystal_goal,
        "start": [cx, cy],
        "rows": ["".join(row) for row in rows],
        "native_install_authorized": False,
    }
    validate_blueprint(data)
    return data


def tilemap(blueprint: dict, kind: str) -> list[int]:
    validate_blueprint(blueprint)
    if kind not in MAP_NAMES.values():
        raise ValueError("Unknown native MAP layer")
    w, h = blueprint["width"], blueprint["height"]
    values = []
    for y in range(h + 1):
        for x in range(w + 1):
            symbol = blueprint["rows"][y][x] if x < w and y < h else "#"
            if kind == "predug":
                val = 1 if symbol == "." else 0
            elif kind == "terrain":
                val = TERRAIN[symbol]
            elif kind == "surface":
                val = 8  # modest flat ceiling clearance, no extreme heights
            elif kind == "cryore":
                val = 1 if symbol == "c" else (2 if symbol == "o" else 0)
            else:
                val = 0
            values.append(val)
    return values


def encode_map(width: int, height: int, values: list[int]) -> bytes:
    # RRU's binary specification: 16-byte header (MAP , size, x, y);
    # X/Y are stored logical dimensions +1, each cell little-endian uint16.
    if (type(width) is not int or type(height) is not int
            or not MIN_AXIS <= width <= MAX_AXIS
            or not MIN_AXIS <= height <= MAX_AXIS
            or type(values) is not list
            or len(values) != (width + 1) * (height + 1)
            or any(type(v) is not int or not 0 <= v <= 0xFFFF for v in values)):
        raise ValueError("Unbounded or invalid native MAP payload")
    payload = struct.pack("<" + "H" * len(values), *values)
    size = 8 + len(payload)
    return b"MAP " + struct.pack("<III", size, width + 1, height + 1) + payload


def decode_map(blob: bytes) -> dict:
    if type(blob) is not bytes or not 16 <= len(blob) <= MAX_BYTES:
        raise ValueError("Unbounded native MAP")
    if blob[:4] != b"MAP ":
        raise ValueError("Invalid MAP magic")
    remaining, x, y = struct.unpack("<III", blob[4:16])
    if (remaining != len(blob) - 8 or not MIN_AXIS <= x - 1 <= MAX_AXIS
            or not MIN_AXIS <= y - 1 <= MAX_AXIS
            or len(blob) != 16 + x * y * 2):
        raise ValueError("Native MAP has inconsistent dimensions or size")
    values = list(struct.unpack("<" + "H" * (x * y), blob[16:]))
    return {"width": x - 1, "height": y - 1, "cells": values}


def safe_output(root: Path) -> None:
    full = root.expanduser().absolute()
    if root.exists() or root.is_symlink():
        raise ValueError("Existing output must never be replaced")
    if any(parent.is_symlink() for parent in full.parents):
        raise ValueError("Output path traverses a symlink")
    home = Path.home().resolve()
    forbidden = (
        home / "Applications",
        home / "OpenLRR-Agent",
    )
    if any(full == path or path in full.parents for path in forbidden):
        raise ValueError("Composer may not write to an installed game or source checkout")
    if not SAFE_NAME.fullmatch(root.name):
        raise ValueError("Output folder name must be an approved level ID")


def write_pack(root: Path, blueprint: dict) -> dict:
    info = validate_blueprint(blueprint)
    safe_output(root)
    root.mkdir(parents=True, mode=0o700)
    contents: dict[str, bytes] = {}
    for name, kind in MAP_NAMES.items():
        contents[name] = encode_map(info["width"], info["height"],
                                    tilemap(blueprint, kind))
        decoded = decode_map(contents[name])
        if len(decoded["cells"]) != (info["width"] + 1) * (info["height"] + 1):
            raise RuntimeError("Native MAP roundtrip failed")
    contents["blueprint.json"] = (
        json.dumps(blueprint, indent=2, sort_keys=True) + "\n"
    ).encode("utf-8")
    contents["LEVEL-CONFIG-SNIPPET.txt"] = (
        "; REVIEW-ONLY: not a complete Lego.cfg level. Do not install automatically.\n" +
        "".join(
            f"{property_name} Levels\\GameLevels\\{blueprint['name']}\\{filename}\n"
            for property_name, filename in MAP_CONFIG
        ) +
        "; Full mission still needs level slot, objectives, objects and NERPs/PTL as applicable.\n"
    ).encode("utf-8")
    for filename, raw in contents.items():
        target = root / filename
        with os.fdopen(os.open(target, os.O_WRONLY | os.O_EXCL | os.O_CREAT, 0o600),
                       "wb") as stream:
            stream.write(raw)
            stream.flush()
            os.fsync(stream.fileno())
    hashes = {name: hashlib.sha256(raw).hexdigest() for name, raw in sorted(contents.items())}
    with (root / "SHA256SUMS.json").open("x", encoding="utf-8") as stream:
        json.dump(hashes, stream, indent=2, sort_keys=True)
        stream.write("\n")
    return {
        "schema_version": 1, "draft_output": str(root), **info,
        "generated_files": sorted([*contents.keys(), "SHA256SUMS.json"]),
        "native_map_binary_roundtrip_validated": True,
        "complete_playable_mission": False,
        "game_executed": False,
        "working_game_modified": False,
        "automatic_install_allowed": False,
    }


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--name", required=True)
    p.add_argument("--width", type=int, default=24)
    p.add_argument("--height", type=int, default=24)
    p.add_argument("--seed", type=int, default=1989)
    p.add_argument("--crystal-goal", type=int, default=12)
    p.add_argument("--out", type=Path, required=True)
    p.add_argument("--compose", action="store_true",
                   help="Write binary native MAP drafts, NEVER install into the game")
    args = p.parse_args(argv)
    proposal = generate(args.name, args.width, args.height,
                        args.seed, args.crystal_goal)
    result = write_pack(args.out, proposal) if args.compose else {
        "schema_version": 1, "mode": "dry_run",
        "tiles": args.width * args.height,
        "resource_goal": args.crystal_goal,
        "native_map_will_be_generated": False,
        "game_executed": False, "working_game_modified": False,
    }
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, ValueError, OSError) as exc:
        print("GAME COMPOSER STOPPED:", exc, file=sys.stderr)
        raise SystemExit(2)
