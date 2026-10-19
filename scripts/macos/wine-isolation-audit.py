#!/usr/bin/env python3
"""Read-only Wine TEST prefix host-filesystem escape audit.

An isolated app *folder* is not a Mac security sandbox. Wine drive mappings
may expose the whole host filesystem to an untrusted 32-bit Windows DLL.
This audit can identify obvious host mappings; it can NEVER certify runtime
sandboxing or authorize automatic execution.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import sys

DEFAULT_APP = (
    Path.home() / "Applications" / "Sikarugir" / "OpenLRR Menu Test.app"
)
REL_PREFIX = Path("Contents/SharedSupport/prefix")
REL_GAME = Path("drive_c/Program Files/Rock Raiders OpenLRR")
MAX_SCANNED_ENTRIES = 15000
MAX_REPORTED_ISSUES = 32


def beneath(child: Path, parent: Path) -> bool:
    try:
        child.relative_to(parent)
        return True
    except ValueError:
        return False


def inspect(test_app: Path) -> dict:
    if test_app.is_symlink() or not test_app.is_dir():
        raise ValueError("TEST app is absent or resolves through a symlink")
    app_real = test_app.resolve(strict=True)
    prefix = test_app / REL_PREFIX
    if prefix.is_symlink() or not prefix.is_dir():
        raise ValueError("Wine prefix is missing or symlinked")
    prefix_real = prefix.resolve(strict=True)
    if not beneath(prefix_real, app_real):
        raise ValueError("Wine prefix escapes isolated app")
    drive_c = prefix / "drive_c"
    if drive_c.is_symlink() or not drive_c.is_dir():
        raise ValueError("Wine C drive is missing or symlinked")
    c_real = drive_c.resolve(strict=True)
    if not beneath(c_real, prefix_real):
        raise ValueError("Wine C drive escapes its prefix")
    game = drive_c / REL_GAME.relative_to("drive_c")
    if game.is_symlink() or not game.is_dir():
        raise ValueError("Expected TEST game is missing or symlinked")
    game_real = game.resolve(strict=True)
    if not beneath(game_real, c_real):
        raise ValueError("TEST game directory resolves outside the Wine C drive")
    for name in ("LegoRR.exe", "openlrr.dll"):
        binary = game / name
        if binary.is_symlink() or not binary.is_file():
            raise ValueError("TEST game binary is missing or symlinked: " + name)
        if not beneath(binary.resolve(strict=True), game_real):
            raise ValueError("TEST game binary resolves outside game folder")

    issues = []
    dos = prefix / "dosdevices"
    if dos.is_symlink() or not dos.is_dir():
        raise ValueError("Wine dosdevices mappings are unavailable")
    dos_root = dos.resolve(strict=True)
    if not beneath(dos_root, prefix_real):
        raise ValueError("Wine drive-map directory escaped its prefix")
    c_link = dos / "c:"
    if not c_link.is_symlink() or c_link.resolve() != c_real:
        issues.append("Wine c: mapping does not point exactly to the isolated C drive")
    for node in dos.iterdir():
        if node.name == "c:":
            continue
        if not node.is_symlink():
            issues.append("Unexpected non-symlink Wine drive mapping")
            continue
        try:
            resolved = node.resolve(strict=True)
        except (FileNotFoundError, RuntimeError, OSError):
            issues.append("Broken/unresolvable Wine drive mapping: " + node.name)
            continue
        if not beneath(resolved, prefix_real):
            issues.append("External Wine drive mapping detected: " + node.name)
        if len(issues) >= MAX_REPORTED_ISSUES:
            break

    count = 0
    # Never follow links. This audit is deliberately bounded to avoid
    # unbounded recursive filesystem traversals or external target scans.
    for base, folders, filenames in os.walk(drive_c, followlinks=False):
        if len(issues) >= MAX_REPORTED_ISSUES:
            break
        for item in folders + filenames:
            count += 1
            if count > MAX_SCANNED_ENTRIES:
                issues.append("Prefix filesystem scan cap exceeded; incomplete audit")
                break
            entry = Path(base) / item
            if entry.is_symlink():
                try:
                    resolved = entry.resolve(strict=True)
                except (FileNotFoundError, RuntimeError, OSError):
                    issues.append("Unresolvable symlink within Wine C drive")
                    continue
                if not beneath(resolved, prefix_real):
                    issues.append("Host-exposing symlink within Wine C drive")
                if len(issues) >= MAX_REPORTED_ISSUES:
                    break
        if count > MAX_SCANNED_ENTRIES:
            break

    return {
        "schema_version": 1,
        "test_app": str(app_real),
        "wine_drive_link_audit_complete": len(issues) == 0,
        "observed_host_mapping_risk": bool(issues),
        "issues": issues,
        "prefix_entries_examined": count,
        # The presence/absence of symlinks cannot attest to Mac VM isolation.
        "host_filesystem_isolation_verified": False,
        "unreviewed_candidate_autorun_allowed": False,
        "game_executed": False,
        "working_game_modified": False,
    }


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--test-app", type=Path, default=DEFAULT_APP)
    parser.add_argument("--require-safe-mappings", action="store_true",
                        help="Fail when any mapped host filesystem exposure is detected")
    parser.add_argument("--require-automatic-execution-isolation",
                        action="store_true",
                        help="Fail closed: this file-only audit cannot verify a VM sandbox")
    args = parser.parse_args(argv)
    report = inspect(args.test_app)
    print(json.dumps(report, indent=2, sort_keys=True))
    if args.require_automatic_execution_isolation:
        raise RuntimeError("Automatic AI DLL execution requires stronger independently verified VM containment")
    if args.require_safe_mappings and report["observed_host_mapping_risk"]:
        raise RuntimeError("Wine prefix exposes host mappings or has incomplete audit")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, RuntimeError) as exc:
        print("WINE PREFIX ISOLATION NOT VERIFIED:", exc, file=sys.stderr)
        raise SystemExit(2)
