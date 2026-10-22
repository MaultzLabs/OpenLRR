#!/usr/bin/env python3
"""Enumerate actual PE imports and missing Windows DLL loads for a local EXE.

Diagnostic only: this script never launches the game, installs DLLs, or
retrieves proprietary files. Run on disposable Windows CI machines.
"""
from __future__ import annotations
import argparse
import ctypes
import json
from pathlib import Path
import sys

def imported_modules(path):
    import pefile
    pe = pefile.PE(str(path), fast_load=True)
    pe.parse_data_directories(directories=[
        pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_IMPORT"],
        pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_DELAY_IMPORT"]
    ])
    names = []
    for prop in ("DIRECTORY_ENTRY_IMPORT", "DIRECTORY_ENTRY_DELAY_IMPORT"):
        for row in getattr(pe, prop, []):
            name = row.dll.decode("ascii", errors="replace")
            if name.lower() not in (x.lower() for x in names):
                names.append(name)
    return sorted(names, key=str.lower)

def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", type=Path)
    args = parser.parse_args(argv)
    path = args.executable.resolve(strict=True)
    rows = []
    names = imported_modules(path)
    if sys.platform == "win32":
        ctypes.windll.kernel32.SetDllDirectoryW(str(path.parent))
    for name in names:
        row = {"name": name}
        if sys.platform != "win32":
            row["load_status"] = "not-tested-nonwindows"
        else:
            try:
                ctypes.WinDLL(name)
                row["load_status"] = "loaded"
            except OSError as exc:
                row["load_status"] = "missing-or-dependent-dll-error"
                row["error"] = str(exc)
        rows.append(row)
    print(json.dumps({
        "executable_name": path.name,
        "direct_import_modules": rows,
        "note": "A successful direct import load does not prove the EXE runs; delay-loaded or runtime-loaded modules may still be missing.",
    }, indent=2))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
