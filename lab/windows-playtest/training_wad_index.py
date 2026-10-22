#!/usr/bin/env python3
"""Read-only catalog of original training text within privately owned WWAD files.

Does not upload, extract, or print any original tutorial contents; discovers paths and
their byte lengths so a subsequent local training parser can use exact assets.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import struct

class InvalidWad(ValueError):
    pass

def entries(data):
    if len(data) < 8 or data[:4] != b"WWAD":
        raise InvalidWad("Not a LEGO Rock Raiders WWAD archive")
    count = struct.unpack_from("<I", data, 4)[0]
    if not (0 <= count <= 100000) or count > len(data) // 18:
        raise InvalidWad("Invalid file count")
    cursor = 8

    def cstring():
        nonlocal cursor
        end = data.find(b"\0", cursor, min(cursor + 8193, len(data)))
        if end < 0 or end == cursor:
            raise InvalidWad("Invalid or overlong WWAD filename")
        value = data[cursor:end].decode("latin1")
        cursor = end + 1
        return value

    names = [cstring() for _ in range(count)]
    for _ in range(count):
        cstring()  # source build paths
    table_end = cursor + count * 16
    if table_end > len(data):
        raise InvalidWad("Truncated WWAD entry table")
    for i, name in enumerate(names):
        flag, stored, unpacked, offset = struct.unpack_from("<IIII", data, cursor + i * 16)
        if offset < table_end or offset > len(data) or stored > len(data) - offset:
            raise InvalidWad("Invalid WWAD payload offset/length")
        if not flag & 2 and stored != unpacked:
            raise InvalidWad("Mismatched stored/uncompressed size")
        yield {"path": name, "flags": flag, "packed_bytes": stored, "unpacked_bytes": unpacked}

def catalog(data):
    found = []
    for e in entries(data):
        path = e["path"].replace("\\", "/").lstrip("/").lower()
        # Can be nested in 'levels/tutoriallevels' or 'levels/traininglevels'
        suffixes = {".txt", ".npl", ".nrn", ".nrm", ".ol", ".map", ".bmp"}
        in_training_folder = ("/tutoriallevels/" in f"/{path}" or
                              "/traininglevels/" in f"/{path}")
        if in_training_folder and any(path.endswith(ext) for ext in suffixes):
            ext = "." + path.rsplit(".", 1)[-1]
            kind = ("compiled-script" if ext == ".npl" else
                    "source-script" if ext in {".nrn", ".nrm"} else
                    "object-placements" if ext == ".ol" else
                    "level-map" if ext == ".map" else
                    "message-or-text" if ext == ".txt" else
                    "graphic")
            found.append({
                "path": e["path"], "bytes": e["unpacked_bytes"],
                "category": kind, "uncompressed_in_wad": not bool(e["flags"] & 2)
            })
    return sorted(found, key=lambda e: e["path"].lower())

def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("wad", type=Path, help="Path to your local LegoRR1.wad")
    parser.add_argument("--output", type=Path, help="Optional LOCAL JSON output (no text contents)")
    args = parser.parse_args(argv)
    result = {"source": args.wad.name, "training_text_files": catalog(args.wad.read_bytes())}
    content = json.dumps(result, indent=2)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(content, encoding="utf-8")
    else:
        print(content)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
