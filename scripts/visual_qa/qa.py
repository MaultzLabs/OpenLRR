#!/usr/bin/env python3
"""Offline OpenLRR screenshot/video visual-regression evaluator.

Reads captured media, writes only diagnostic artifacts, and NEVER launches the
game, changes source, installs DLLs, or authorizes a candidate. All thresholds
are heuristics: scores measure visual agreement, not gameplay correctness.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image, ImageOps

SCHEMA = 1
IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".bmp", ".webp"}
VIDEO_EXTS = {".mp4", ".mov", ".mkv", ".webm", ".avi"}
ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{2,63}$")
MAX_BYTES = 1_000_000_000
MAX_PIXELS = 2_500_000
MAX_FRAMES = 24
MAX_DURATION_S = 600
Image.MAX_IMAGE_PIXELS = MAX_PIXELS


def hash_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def safe_input(path: Path) -> Path:
    if path.is_symlink() or not path.is_file():
        raise ValueError("Capture must be an existing regular file, not a symlink")
    if not 0 < path.stat().st_size <= MAX_BYTES:
        raise ValueError("Capture size outside safety bounds")
    return path.resolve()


def load_image(path: Path) -> np.ndarray:
    with Image.open(path) as original:
        if original.width * original.height > MAX_PIXELS:
            raise ValueError("Image exceeds maximum pixel count")
        img = ImageOps.exif_transpose(original).convert("RGB")
        return np.asarray(img, dtype=np.uint8).copy()


def run_checked(command: list[str], timeout: int) -> str:
    proc = subprocess.run(command, capture_output=True, text=True,
                          timeout=timeout, check=False)
    if proc.returncode:
        raise ValueError("Media decoder failed: " + proc.stderr[-300:].replace("\n", " "))
    return proc.stdout


def extract_video(path: Path, dest: Path, fps: int) -> tuple[list[np.ndarray], float]:
    if not shutil.which("ffmpeg") or not shutil.which("ffprobe"):
        raise ValueError("Video inspection requires ffmpeg and ffprobe")
    metadata = json.loads(run_checked(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "format=duration:stream=width,height",
         "-of", "json", str(path)], 20))
    streams = metadata.get("streams", [])
    if not streams:
        raise ValueError("Capture has no video stream")
    width, height = streams[0].get("width"), streams[0].get("height")
    if type(width) is not int or type(height) is not int or not (0 < width * height <= MAX_PIXELS):
        raise ValueError("Unsafe video dimensions")
    try:
        duration = float(metadata.get("format", {}).get("duration"))
    except (ValueError, TypeError) as exc:
        raise ValueError("Cannot determine video duration") from exc
    if not math.isfinite(duration) or not 0 < duration <= MAX_DURATION_S:
        raise ValueError("Video duration outside safety bounds")
    # Sample the ENTIRE clip at uniform time intervals, not only its first
    # MAX_FRAMES/fps seconds; bound resident memory for long captures.
    effective_fps = min(float(fps), (MAX_FRAMES - 0.1) / duration)
    run_checked(["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error",
                 "-i", str(path), "-an", "-sn", "-vf", f"fps={effective_fps:.8f}",
                 "-frames:v", str(MAX_FRAMES), str(dest / "frame-%04d.png")], 90)
    frames = sorted(dest.glob("frame-*.png"))
    if not frames:
        raise ValueError("Video produced no sampled frames")
    return [load_image(frame) for frame in frames], duration


def load_mask(path: Path | None, shape: tuple[int, ...]) -> np.ndarray:
    if path is None:
        return np.ones(shape[:2], dtype=bool)
    safe_input(path)
    with Image.open(path) as im:
        grayscale = np.asarray(im.convert("L"), dtype=np.uint8)
    if grayscale.shape != shape[:2]:
        raise ValueError("Exclusion mask dimensions must match captures")
    valid = grayscale < 128  # White pixels are excluded.
    if not np.any(valid):
        raise ValueError("Exclusion mask hides the entire image")
    return valid


def global_ssim(a: np.ndarray, b: np.ndarray) -> float:
    x = a.astype(np.float64)
    y = b.astype(np.float64)
    mx, my = x.mean(), y.mean()
    vx, vy = ((x - mx) ** 2).mean(), ((y - my) ** 2).mean()
    cov = ((x - mx) * (y - my)).mean()
    c1, c2 = (0.01 * 255) ** 2, (0.03 * 255) ** 2
    return float(np.clip(((2 * mx * my + c1) * (2 * cov + c2)) /
                         ((mx * mx + my * my + c1) * (vx + vy + c2)), 0, 1))


def tile_ssim(a: np.ndarray, b: np.ndarray, valid: np.ndarray) -> float:
    height, width = valid.shape
    vals, weights = [], []
    # Local comparisons detect faults that full-frame statistics can hide.
    for y0 in range(0, height, max(8, math.ceil(height / 8))):
        for x0 in range(0, width, max(8, math.ceil(width / 8))):
            dy = slice(y0, min(height, y0 + max(8, math.ceil(height / 8))))
            dx = slice(x0, min(width, x0 + max(8, math.ceil(width / 8))))
            mask = valid[dy, dx]
            if mask.any():
                vals.append(global_ssim(a[dy, dx][mask], b[dy, dx][mask]))
                weights.append(int(mask.sum()))
    return float(np.average(vals, weights=weights))


def frame_metrics(reference: np.ndarray, candidate: np.ndarray,
                  valid: np.ndarray, tolerance: int) -> dict:
    delta = np.abs(reference.astype(np.int16) - candidate.astype(np.int16))
    active = delta[valid]
    mae = float(active.mean())
    changed = float((active > tolerance).any(axis=1).mean())
    ssim = tile_ssim(reference, candidate, valid)
    # A 0-100 agreement score; no unverified claims about real visible FPS.
    score = 100 * (.45 * (1 - mae / 255) + .35 * ssim + .20 * (1 - changed))
    refpix, candpix = reference[valid], candidate[valid]
    return {
        "score": round(max(0.0, min(100.0, score)), 2),
        "mae": round(mae, 3),
        "changed_ratio": round(changed, 5),
        "ssim": round(ssim, 5),
        "reference_luma": round(float(refpix.mean()), 2),
        "candidate_luma": round(float(candpix.mean()), 2),
        "reference_std": round(float(refpix.std()), 2),
        "candidate_std": round(float(candpix.std()), 2),
    }


def motion(first: np.ndarray, second: np.ndarray, mask: np.ndarray) -> float:
    delta = np.abs(first.astype(np.int16) - second.astype(np.int16))
    return float((delta[mask] > 12).any(axis=1).mean())


def issue(code: str, severity: str, detail: str, frame: int | None = None) -> dict:
    item = {"code": code, "severity": severity, "description": detail}
    if frame is not None:
        item["frame_index"] = frame
    return item


def heatmap(ref: np.ndarray, cand: np.ndarray, valid: np.ndarray,
            dest: Path) -> None:
    delta = np.abs(ref.astype(np.int16) - cand.astype(np.int16))
    intensity = np.clip(delta.max(axis=2) * 3, 0, 255).astype(np.uint8)
    heat = np.zeros_like(ref)
    heat[:, :, 0] = intensity
    heat[:, :, 1] = intensity // 5
    heat[~valid] = 0
    Image.fromarray(heat, "RGB").save(dest)


def compare_frames(ref_frames: list[np.ndarray], cand_frames: list[np.ndarray],
                   mask_path: Path | None, out: Path, tolerance: int,
                   min_score: float, duration_pair: tuple[float, float] | None = None) -> tuple[str, float | None, dict, list[dict], list[dict]]:
    issues: list[dict] = []
    if duration_pair is not None and abs(duration_pair[0] - duration_pair[1]) > max(0.25, .02 * min(duration_pair)):
        return ("inconclusive", None,
                {"reference_duration_s": round(duration_pair[0], 3),
                 "candidate_duration_s": round(duration_pair[1], 3)},
                [issue("capture_duration_mismatch", "blocking",
                       "Video durations differ by more than 2%; recapture matched windows.")], [])
    if len(ref_frames) != len(cand_frames):
        return ("inconclusive", None, {"reference_frames": len(ref_frames),
                "candidate_frames": len(cand_frames)},
                [issue("frame_count_mismatch", "blocking",
                       "Unequal sampled frame counts; compare equal-duration captures.")], [])
    if not ref_frames:
        raise ValueError("At least one frame is required")
    if any(a.shape != ref_frames[0].shape or b.shape != ref_frames[0].shape
           for a, b in zip(ref_frames, cand_frames)):
        return ("inconclusive", None,
                {"reference_frames": len(ref_frames), "candidate_frames": len(cand_frames)},
                [issue("geometry_mismatch", "blocking",
                       "Frame sizes do not match; establish identical capture resolution.")], [])
    valid = load_mask(mask_path, ref_frames[0].shape)
    per_frame = []
    for idx, (ref, cand) in enumerate(zip(ref_frames, cand_frames)):
        metrics = frame_metrics(ref, cand, valid, tolerance)
        per_frame.append(metrics)
        if idx < 12:
            heatmap(ref, cand, valid, out / f"diff-{idx:04d}.png")
        if (metrics["reference_luma"] > 20 and metrics["reference_std"] > 9
                and metrics["candidate_luma"] < 9 and metrics["candidate_std"] < 5):
            issues.append(issue("black_screen", "critical",
                                "Candidate frame appears blank while reference contains a scene.", idx))
    scores = [x["score"] for x in per_frame]
    if len(ref_frames) >= 4:
        frozen = 0
        flicker = 0
        for idx in range(1, len(ref_frames)):
            ref_move = motion(ref_frames[idx - 1], ref_frames[idx], valid)
            cand_move = motion(cand_frames[idx - 1], cand_frames[idx], valid)
            frozen = frozen + 1 if ref_move > .04 and cand_move < .001 else 0
            if frozen == 2:
                issues.append(issue("possible_freeze", "critical",
                                    "Candidate remained static while reference showed movement.", idx))
            ref_luma_change = abs(per_frame[idx]["reference_luma"] - per_frame[idx - 1]["reference_luma"])
            cand_luma_change = abs(per_frame[idx]["candidate_luma"] - per_frame[idx - 1]["candidate_luma"])
            if cand_luma_change > max(24, ref_luma_change + 18):
                flicker += 1
        if flicker >= 2:
            issues.append(issue("possible_flicker", "warning",
                                "Candidate shows larger brightness jumps than the reference."))
    score = round(float(np.mean(scores)), 2)
    worst = min(scores)
    metrics = {
        "frame_count": len(scores),
        "mean_score": score,
        "worst_frame_score": worst,
        "mean_absolute_error": round(float(np.mean([x["mae"] for x in per_frame])), 3),
        "changed_pixel_ratio": round(float(np.mean([x["changed_ratio"] for x in per_frame])), 5),
        "mean_local_ssim": round(float(np.mean([x["ssim"] for x in per_frame])), 5),
        "unmasked_pixel_count": int(valid.sum()),
    }
    critical = any(x["severity"] == "critical" for x in issues)
    if critical or score < 83 or worst < 65:
        status = "regression"
    elif score < min_score or issues:
        status = "review"
    else:
        status = "pass"
    if status != "pass" and not issues:
        issues.append(issue("visual_difference", "warning" if status == "review" else "blocking",
                            "Image comparison exceeds configured similarity tolerance."))
    return status, score, metrics, issues, per_frame


def report_for(reference: Path, candidate: Path, out: Path, experiment_id: str,
               scene: str, *, mask: Path | None = None, fps: int = 2,
               tolerance: int = 12, min_score: float = 94) -> dict:
    if not ID.fullmatch(experiment_id) or not ID.fullmatch(scene):
        raise ValueError("Experiment ID and scene must be 3-64 safe characters")
    if not 1 <= fps <= 10 or not 0 <= tolerance <= 255 or not 83 <= min_score <= 100:
        raise ValueError("Unsupported sampling or scoring parameters")
    reference, candidate = safe_input(reference), safe_input(candidate)
    if reference == candidate:
        raise ValueError("Reference and candidate must be distinct files")
    typ = ("image" if reference.suffix.lower() in IMAGE_EXTS else
           "video" if reference.suffix.lower() in VIDEO_EXTS else None)
    if typ is None or candidate.suffix.lower() not in (IMAGE_EXTS if typ == "image" else VIDEO_EXTS):
        raise ValueError("Both inputs must be recognized images or videos of the same kind")
    # Never follow a user-controlled output symlink, including parent links.
    raw_out = out.absolute()
    if any(part.is_symlink() for part in (raw_out, *raw_out.parents)):
        raise ValueError("Output path must not use symlinks")
    out = raw_out.resolve()
    if out == reference.parent or out == candidate.parent:
        raise ValueError("Output must be a separate dedicated directory")
    # Fail closed if someone points QA into an installed original game tree.
    if any((parent / name).exists()
           for parent in (out, *out.parents)
           for name in ("LegoRR.exe", "LEGOrr.exe", "legorr.exe")):
        raise ValueError("Refusing to write inside a game installation")
    if out.exists() and (not out.is_dir() or any(out.iterdir())):
        raise ValueError("Output directory must be an empty directory")
    out.mkdir(parents=True, exist_ok=True)
    durations = None
    if typ == "image":
        left, right = [load_image(reference)], [load_image(candidate)]
    else:
        with tempfile.TemporaryDirectory(prefix="openlrr-visual-qa-") as tmp:
            # Explicit directories prevent two decoders from overwriting samples.
            a, b = Path(tmp) / "a", Path(tmp) / "b"
            a.mkdir()
            b.mkdir()
            left, reference_seconds = extract_video(reference, a, fps)
            right, candidate_seconds = extract_video(candidate, b, fps)
            durations = (reference_seconds, candidate_seconds)
    status, score, metrics, findings, frames = compare_frames(
        left, right, mask, out, tolerance, min_score, duration_pair=durations)
    recommended = ("isolate_regression" if status == "regression" else
                   "improve_instrumentation" if status == "inconclusive" else
                   "request_visual_review" if status == "review" else "record_no_regression")
    result = {
        "schema_version": SCHEMA,
        "tool": "openlrr-visual-qa",
        "experiment_id": experiment_id,
        "scene": scene,
        "status": status,
        "score": score,
        "threshold": min_score,
        "pixel_tolerance": tolerance,
        "input_kind": typ,
        "sampling_fps": fps if typ == "video" else None,
        "metrics": metrics,
        "frames": frames,
        "findings": findings,
        "capture_hashes": {
            "reference_sha256": hash_file(reference),
            "candidate_sha256": hash_file(candidate),
            "mask_sha256": hash_file(mask) if mask is not None else None,
        },
        "repair_feedback": {
            "recommended_next_step": recommended,
            "reason_codes": [f["code"] for f in findings],
            "human_review_required": status != "pass",
        },
        "may_install_or_run_candidate": False,
        "may_touch_working_game": False,
        "may_deploy_automatically": False,
        "visual_fps_verified": False,
    }
    (out / "report.json").write_text(json.dumps(result, indent=2, sort_keys=True) + "\n",
                                      encoding="utf-8")
    return result


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--experiment-id", required=True)
    parser.add_argument("--scene", default="menu_boot_autotest_v1")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--mask", type=Path)
    parser.add_argument("--fps", type=int, default=2)
    parser.add_argument("--tolerance", type=int, default=12)
    parser.add_argument("--min-score", type=float, default=94)
    parser.add_argument("--fail-on-regression", action="store_true")
    args = parser.parse_args(argv)
    try:
        report = report_for(args.reference, args.candidate, args.out,
                            args.experiment_id, args.scene, mask=args.mask,
                            fps=args.fps, tolerance=args.tolerance,
                            min_score=args.min_score)
        print(json.dumps({"status": report["status"], "score": report["score"],
                          "report": str(args.out / "report.json")}, sort_keys=True))
        return 3 if args.fail_on_regression and report["status"] != "pass" else 0
    except (ValueError, OSError, subprocess.TimeoutExpired, json.JSONDecodeError) as exc:
        print("VISUAL QA STOPPED: " + str(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
