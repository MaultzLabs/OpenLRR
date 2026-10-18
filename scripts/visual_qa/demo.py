#!/usr/bin/env python3
"""Generate entirely synthetic evidence proving the visual QA failure path."""
from __future__ import annotations

import json
from pathlib import Path
import sys

import numpy as np
from PIL import Image

from qa import report_for


def main() -> int:
    root = Path("visual-qa-synthetic-proof")
    if root.exists():
        raise RuntimeError("Proof directory exists; refusing to overwrite")
    root.mkdir()
    yy, xx = np.indices((120, 200))
    reference = np.stack((xx % 255, yy * 2 % 255,
                          ((xx + yy) * 2) % 255), axis=2).astype(np.uint8)
    candidate = reference.copy()
    candidate[20:100, 30:170] = 0  # synthetic broken rendering rectangle
    a, b = root / "reference.png", root / "candidate.png"
    Image.fromarray(reference).save(a)
    Image.fromarray(candidate).save(b)
    result = report_for(a, b, root / "diagnostics",
                        "synthetic_demo_001", "menu_boot_autotest_v1")
    assert result["status"] in ("review", "regression")
    assert result["repair_feedback"]["recommended_next_step"] != "record_no_regression"
    assert result["may_touch_working_game"] is False
    assert result["may_install_or_run_candidate"] is False
    assert result["may_deploy_automatically"] is False
    print(json.dumps({"status": result["status"], "score": result["score"],
                      "findings": result["findings"],
                      "report": str(root / "diagnostics/report.json")}, indent=2))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, RuntimeError, AssertionError) as exc:
        print("Synthetic proof failed: " + str(exc), file=sys.stderr)
        sys.exit(2)
