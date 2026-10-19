#!/usr/bin/env python3
"""One opt-in, menu-only Mac diagnostic session using existing safe lab runner.

No autonomous repair, source patch, system Wine settings, global installs,
game composer, or unreviewed DLLs. By default only validates; --run explicitly
launches exactly one bounded approved diagnostic plan into the TEST app.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import time

HOME = Path.home()
ROOT = HOME / "OpenLRR-Agent"
APP = HOME / "Applications/Sikarugir/OpenLRR Menu Test.app"
GAME = APP / "Contents/SharedSupport/prefix/drive_c/Program Files/Rock Raiders OpenLRR"
CONFIG = HOME / ".config/openlrr-benchmark"
RUNS = HOME / "Downloads/OpenLRR Benchmark Runs"
OUTPUT = HOME / ".local/share/openlrr-agent/menu-diagnostic-sessions"
ONE_SHOT = ROOT / "scripts/macos/diagnostic-one-shot.sh"
SUPERVISOR = ROOT / "scripts/macos/lab-supervisor.py"
PROFILE = ROOT / "scripts/macos/wine-cpu-sample.py"
WIN_AUDIT = ROOT / "scripts/macos/wine-isolation-audit.py"

# Successful, previously TEST-executed Windows x86 diagnostic, not an AI
# generated candidate. These values are immutable, reviewed from GitHub
# build metadata and actual private Mac benchmark summaries.
RUN_ID = "39184097578"
SOURCE_SHA = "c3f8d2a81661a7626be0e8628d90c54898688c43"
DLL_SHA = "1179323074e03caf22f89ecbf05b9234f8ef5e18f2c1d6b8d797c2cf31c5b4ff"
MODES = {
    1: ("baseline", "baseline"),
    2: ("baseline", "nowait", "baseline", "nowait"),
}
MAX_SESSION_SECONDS = {1: 950, 2: 1650}
NAME = re.compile(r"^autobenchmark-\d{4}-\d\d-\d\d_\d\d-\d\d-\d\d$")
REVIEWED_WINE_PROFILE_COUNT = 1


def safe_process(args: list[str], *, timeout: int = 15) -> str | None:
    try:
        p = subprocess.run(args, capture_output=True, text=True,
                           timeout=timeout, check=False)
        return p.stdout.strip()[:300] if p.returncode == 0 else None
    except (OSError, subprocess.TimeoutExpired):
        return None


def no_symlink_ancestors(path: Path) -> bool:
    # Avoid path aliases accidentally pointing the TEST fixture at the
    # owner's normal Rock Raiders directory or an arbitrary host path.
    absolute = path.absolute()
    return not any(item.is_symlink() for item in (absolute, *absolute.parents))


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for data in iter(lambda: f.read(1024 * 1024), b""):
            h.update(data)
    return h.hexdigest()


def check_environment(session: int, *, os_check: bool = True) -> dict:
    if session not in MODES:
        raise ValueError("Only diagnostic sessions 1 and 2 are currently authorized")
    if os_check and sys.platform != "darwin":
        raise RuntimeError("This execution package is macOS-only")
    if (CONFIG / "STOP").exists() or (CONFIG / "PAUSE").exists():
        raise RuntimeError("STOP or PAUSE active, no game launch permitted")
    for lock in (CONFIG / "supervisor.lock",
                 HOME / ".local/share/openlrr-agent/paired-eval.lock",
                 HOME / ".local/share/openlrr-agent/approved-diagnostic-worker.lock"):
        if lock.exists() or lock.is_symlink():
            raise RuntimeError("Another lab experiment has an active/stale lock")
    if os_check:
        revision = safe_process(["git", "-C", str(ROOT), "rev-parse", "--verify", "HEAD"])
        if not isinstance(revision, str) or not re.fullmatch(r"[a-f0-9]{40}", revision):
            raise RuntimeError("Cannot verify checked-out lab source revision")
        dirty = subprocess.run(
            ["git", "-C", str(ROOT), "status", "--porcelain", "--untracked-files=no"],
            capture_output=True, text=True, timeout=15, check=False,
        )
        if dirty.returncode != 0 or dirty.stdout.strip():
            raise RuntimeError("Local lab scripts are modified; refuse unreviewed execution")
    for path in (APP, GAME, GAME / "LegoRR.exe", GAME / "openlrr.dll",
                 ONE_SHOT, SUPERVISOR):
        if not no_symlink_ancestors(path):
            raise RuntimeError("TEST app or lab scripts resolve through symlinks")
        if not path.is_file() and not path.is_dir():
            raise RuntimeError("Missing TEST app or trusted lab script")
    if APP.name != "OpenLRR Menu Test.app" or not GAME.resolve().is_relative_to(APP.resolve()):
        raise RuntimeError("Target does not resolve inside dedicated TEST application")
    if not RUNS.is_dir():
        raise RuntimeError("Existing benchmark results directory not found")
    if not (HOME / ".local/share/openlrr-agent/venv/bin/python").is_file():
        raise RuntimeError("Previously configured isolated lab Python venv missing")
    # Respect an existing ongoing TEST process. Never kill it automatically.
    if os_check:
        # lsof returns exit status 1 with EMPTY output when no processes
        # own files under the TEST game. This is the normal safe case.
        try:
            inspected = subprocess.run(
                ["/usr/sbin/lsof", "-nP", "-t", "+D", str(GAME)],
                capture_output=True, text=True, timeout=25, check=False,
            )
        except (OSError, subprocess.TimeoutExpired) as error:
            raise RuntimeError("Could not inspect TEST process handles") from error
        if (inspected.returncode not in (0, 1)
                or (inspected.returncode == 1 and inspected.stderr.strip())
                or len(inspected.stdout) > 8192):
            raise RuntimeError("TEST process handle inspection unreliable")
        if inspected.stdout.strip():
            raise RuntimeError("TEST app still has open file handles")
        needed = ("gh", "shasum", "lsof", "git", "python3")
        if any(shutil.which(c) is None for c in needed):
            raise RuntimeError("Existing GitHub CLI, Python3 or Mac utilities unavailable")
        if safe_process(["gh", "auth", "status"]) is None:
            # 'gh auth status' often writes to stderr even on success;
            # use a read-only identity API to check authentication.
            if safe_process(["gh", "api", "user", "--jq", ".login"]) is None:
                raise RuntimeError("GitHub CLI is not authenticated")
        visibility = safe_process([
            "gh", "repo", "view", "MaultzLabs/OpenLRR-Test-Results",
            "--json", "visibility", "--jq", ".visibility"
        ])
        if visibility != "PRIVATE":
            raise RuntimeError("Benchmark repository is not proven private")
    return {
        "schema_version": 1, "session": session, "plan": list(MODES[session]),
        "approved_run_id": RUN_ID, "approved_source_sha": SOURCE_SHA,
        "approved_dll_sha256": DLL_SHA,
        "test_app_only": True, "working_game_modified": False,
        "ai_candidate_execution_allowed": False,
        "visible_fps_verified": False,
        "screenshots_available": "unverified",
        "screenshot_reason": "Separate visual QA capture is not yet integrated into this runner",
        "permissions": {
            "screen_recording": "not_requested",
            "microphone": "not_requested",
            "accessibility": "not_requested"
        },
    }


def mac_snapshot() -> dict:
    # Never return a home path, serial number, raw environment or drive map.
    wine_path = shutil.which("wine")
    prefix = APP / "Contents/SharedSupport/prefix"
    drive_maps = prefix / "dosdevices"
    external_drives = []
    if drive_maps.is_dir():
        for entry in sorted(drive_maps.iterdir()):
            if entry.is_symlink() and entry.name != "c:":
                try:
                    resolved = entry.resolve(strict=True)
                    if not resolved.is_relative_to(prefix.resolve()):
                        external_drives.append(entry.name[:6])
                except (OSError, RuntimeError):
                    external_drives.append("unverifiable_mapping")
    options = sorted(x for x in (
        "menuperf.enable", "menuperf.nowait", "menuperf.gdi",
        "menuperf.optimize"
    ) if (GAME / x).exists())
    graphics_files = {}
    for name in ("ddraw.dll", "d3d8.dll", "d3d9.dll",
                 "dgVoodoo.conf", "dxvk.conf"):
        item = GAME / name
        # Only report fixed filenames and file digests; no user paths or
        # potentially identifying raw configuration contents are uploaded.
        if item.is_file() and not item.is_symlink() and item.stat().st_size <= 10_000_000:
            graphics_files[name] = {"present": True,
                                    "sha256": sha256_file(item)}
    wine_registry_graphics = "unavailable"
    registry = prefix / "user.reg"
    if registry.is_file() and not registry.is_symlink() and registry.stat().st_size <= 4_000_000:
        # Presence alone is useful to reproduce a wrapper's choice. Avoid
        # collecting raw registry values, users, host paths or license keys.
        source = registry.read_text(encoding="utf-8", errors="replace")
        wine_registry_graphics = (
            "direct3d_section_present" if "[Software\\\\Wine\\\\Direct3D]" in source
            else "no_direct3d_section_observed"
        )
    sw = safe_process(["sw_vers", "-productVersion"])
    return {
        "schema_version": 1,
        "local_graphics_compatibility_files": graphics_files,
        "wine_direct3d_registry_section": wine_registry_graphics,
        "architecture": platform.machine(),
        "macos_version": sw or "unavailable",
        "wine_version": safe_process([wine_path, "--version"]) if wine_path else "unavailable_in_PATH",
        "wine_version_source": "PATH" if wine_path else "not_resolved_from_embedded_wrapper",
        "test_app_detected": APP.is_dir(),
        "test_prefix_detected": prefix.is_dir(),
        "test_menu_marker_names": options,
        "wine_external_drive_names": external_drives[:16],
        "win32_binary_identity_expected": DLL_SHA,
        "display_refresh_hz": None,
        "display_capture_permission": "not_checked",
        "visible_fps_measured": False,
        "cpu_profiler": "attempt_local_only",
        "raw_machine_paths_redacted": True,
    }


def known_runs() -> set[str]:
    if not RUNS.exists():
        return set()
    return {p.name for p in RUNS.iterdir() if p.is_dir() and NAME.fullmatch(p.name)}


def verify_completed(run_ids: list[str], modes: tuple[str, ...]) -> dict:
    if len(run_ids) != len(modes) or len(set(run_ids)) != len(run_ids):
        raise ValueError("Incomplete or duplicate supervised run list")
    observations = []
    for name, mode in zip(run_ids, modes):
        if not NAME.fullmatch(name):
            raise ValueError("Unsafe benchmark run directory")
        base = RUNS / name
        if not no_symlink_ancestors(base):
            raise ValueError("Run receipt path must not be a symlink")
        receipt = base / "lifecycle.verified"
        summary_path = base / "summary.json"
        csv = base / "menuperf.csv"
        binary = base / "benchmark-openlrr.dll"
        for candidate in (receipt, summary_path, csv, binary):
            if candidate.is_symlink() or not candidate.is_file():
                raise ValueError("Missing verified run artifact")
        if receipt.read_text(encoding="utf-8") != (
                "wrapper_wait_exited=yes\ntest_game_handles=none\n"):
            raise ValueError("Unverified TEST process exit")
        if sha256_file(binary) != DLL_SHA:
            raise ValueError("Run did not use the owner-reviewed diagnostic DLL")
        if csv.stat().st_size > 2_000_000 or summary_path.stat().st_size > 65_536:
            raise ValueError("Oversized performance summary")
        summary = json.loads(summary_path.read_text(encoding="utf-8"))
        metrics = summary.get("metrics", {})
        expected = {"optimization": 0, "nowait": int(mode == "nowait"),
                    "gdi": int(mode == "gdi")}
        if (summary.get("schema_version") != 1 or summary.get("run") != name
                or summary.get("dll_sha256") != DLL_SHA
                or summary.get("close_requested") is not True
                or metrics.get("mode") != expected
                or type(metrics.get("present_calls")) is not int
                or metrics["present_calls"] < 1):
            raise ValueError("Run identity, graphics mode, or lifecycle inconsistent")
        seconds = metrics.get("logged_duration_s")
        if (type(seconds) not in (int, float) or not 45 <= seconds <= 90):
            raise ValueError("Benchmark run was not a comparable 60-second session")
        frames = metrics.get("frame_flips_per_s")
        latency = metrics.get("present_avg_ms")
        if (type(frames) not in (int, float) or type(latency) not in (int, float)
                or not 0 <= frames <= 1000 or not 0 <= latency <= 100000):
            raise ValueError("Invalid presentation benchmark metrics")
        observations.append({
            "run_id": name, "mode": mode, "reported_seconds": seconds,
            "logical_frame_flips_per_s": frames,
            "average_present_ms": latency,
            "window_blits_over_1000ms": metrics.get("window_blt_calls_over_1000ms"),
            "thread_cpu_samples": metrics.get("blit_thread_cpu_samples"),
            "low_cpu_long_blits": metrics.get("blit_slow_low_cpu_calls"),
            "process_exit_receipt": "verified",
            "test_binary_sha256": DLL_SHA,
            "visual_verification": "missing",
            "input_validation": "missing",
            "audio_validation": "missing",
        })
    comparisons = []
    if len(modes) == 4:
        for i in (0, 2):
            a, b = observations[i], observations[i + 1]
            comparisons.append({
                "baseline": a["run_id"], "candidate": b["run_id"],
                "candidate_mode": b["mode"], "binary_identical": True,
                "scene": "menu_boot_autotest_v1",
                "durations_comparable": abs(
                    a["reported_seconds"] - b["reported_seconds"]) <= 5,
                "average_present_change_pct": round(
                    100 * (b["average_present_ms"] / a["average_present_ms"] - 1), 3
                ) if a["average_present_ms"] > 0 else None,
            })
    return {
        "runs": observations,
        "pairs": comparisons,
        "evidence_completeness": {
            "instrumented_present_timing": "available",
            "separate_visible_frame_capture": "missing",
            "verified_visible_fps": "missing",
            "screen_regression_result": "missing",
            "input_test_result": "missing",
            "audio_test_result": "missing",
        },
        "claims": {
            "60_visible_fps_achieved": False,
            "menu_functional_and_responsive_proven": False,
            "session_2_proves_performance_gain": False,
            "working_game_modified": False,
        },
    }


def store_new(path: Path, data: dict) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    if path.exists() or path.is_symlink() or path.parent.is_symlink():
        raise RuntimeError("Existing diagnostic output or unsafe symlink")
    with os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600),
                   "w", encoding="utf-8") as stream:
        json.dump(data, stream, sort_keys=True, indent=2)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())


def run_session(session: int, *, profile_cpu: bool = True) -> dict:
    info = check_environment(session)
    start = datetime.now(timezone.utc)
    directory = OUTPUT / ("session_%d_%s" % (session, start.strftime("%Y%m%dT%H%M%SZ")))
    if directory.exists() or directory.is_symlink() or OUTPUT.is_symlink():
        raise RuntimeError("Session state collision or symlink")
    directory.mkdir(parents=True, mode=0o700)
    store_new(directory / "preflight.json", info)
    store_new(directory / "mac-environment.json", mac_snapshot())
    before = known_runs()
    log = directory / "runner-local-only.log"
    env = {k: v for k, v in os.environ.items() if not k.startswith("OPENAI_") and k not in (
        "GH_TOKEN", "GITHUB_TOKEN", "GIT_ASKPASS", "SSH_ASKPASS")}
    env.update({
        "OPENLRR_DIAGNOSTIC_PLAN": ",".join(MODES[session]),
        "OPENLRR_DIAGNOSTIC_REVIEWED_SHA256": DLL_SHA,
        "OPENLRR_REPORT_REPO": "MaultzLabs/OpenLRR-Test-Results"
    })
    provenance = {
        "schema_version": 1, "session": session,
        "reviewed_artifact_run": RUN_ID, "source_revision": SOURCE_SHA,
        "dll_sha256": DLL_SHA, "plan": list(MODES[session]),
        "raw_cpu_stacks_private_local_only": True,
        "optional_screenshot_capture": "not_attempted",
        "working_game_writes_authorized": False,
        "new_candidate_dll_execution_authorized": False,
    }
    store_new(directory / "plan.json", provenance)
    profile_result = "not_attempted"
    status = "failed_or_incomplete"
    try:
        with log.open("x", encoding="utf-8") as sink:
            proc = subprocess.Popen(
                ["/bin/bash", str(ONE_SHOT), RUN_ID, SOURCE_SHA],
                stdout=sink, stderr=subprocess.STDOUT, env=env,
            )
            started = time.monotonic()
            attempted = False
            previous_notice = -30
            print("Approved menu session started. TEST app only; "
                  "two baselines" if session == 1 else
                  "Approved menu session started. TEST app only; "
                  "two preliminary graphics A/B pairs", flush=True)
            print("Private benchmark uploads are handled by the existing runner. "
                  "Log:", log, flush=True)
            while proc.poll() is None:
                if time.monotonic() - started - previous_notice >= 30:
                    previous_notice = time.monotonic() - started
                    print("TEST session still running; elapsed:",
                          int(previous_notice), "seconds", flush=True)
                elapsed = time.monotonic() - started
                if elapsed > MAX_SESSION_SECONDS[session]:
                    (CONFIG / "STOP").touch(exist_ok=True)
                    raise RuntimeError("Diagnostic watchdog timed out; STOP set, do not retry")
                if (CONFIG / "STOP").exists():
                    raise RuntimeError("STOP was requested; do not run another test")
                # A wall-clock delay after GitHub download is not proof that
                # Wine is rendering. Profile only when a NEW supervised run
                # exists and fresh TEST menu telemetry has appeared.
                live = GAME / "menuperf.csv"
                observed_new_run = bool(known_runs() - before)
                try:
                    fresh_frame_data = (
                        live.is_file() and not live.is_symlink()
                        and live.stat().st_size > 120
                        and live.stat().st_mtime >= start.timestamp()
                    )
                except (FileNotFoundError, PermissionError):
                    # The runner rotates the TEST telemetry file between
                    # arms. A transient gap is not a failing game result.
                    fresh_frame_data = False
                if (profile_cpu and not attempted and elapsed >= 20
                        and observed_new_run and fresh_frame_data):
                    attempted = True
                    if PROFILE.is_file() and no_symlink_ancestors(PROFILE):
                        capture = subprocess.run(
                            [sys.executable, str(PROFILE), "--capture"],
                            capture_output=True, text=True, timeout=35,
                            env=env, check=False)
                        profile_result = (
                            "locally_recorded" if capture.returncode == 0
                            else "unavailable_no_process_or_capture_permission"
                        )
                    else:
                        profile_result = "unavailable_missing_profiler"
                time.sleep(2)
            if proc.returncode != 0:
                raise RuntimeError("Supervised session failed; test lock and backups require inspection")
        after = known_runs()
        new = sorted(after - before)
        if len(new) != len(MODES[session]):
            raise RuntimeError("Wrong number of new benchmark directories; no result accepted")
        verified = verify_completed(new, MODES[session])
        if profile_cpu and not attempted:
            profile_result = "unavailable_no_fresh_live_menu_telemetry"
        result = {
            **verified, "session": session,
            "source_artifact_run": RUN_ID, "source_revision": SOURCE_SHA,
            "private_upload": "supervisor_reports_all_uploaded",
            "cpu_stack_profile": profile_result,
            "visible_fps_verified": False,
            "complete_60fps_success": False,
            "raw_cpu_stack_upload": False,
            "local_log": "runner-local-only.log",
        }
        store_new(directory / "report.json", result)
        status = "completed_with_unverified_visual_input_audio"
        return {"status": status, "report_directory": str(directory), **result}
    except KeyboardInterrupt as interrupt:
        # The game runner already polls STOP for graceful shutdown.
        # Do not force-kill Wine or delete any safety lock after SIGINT.
        CONFIG.mkdir(parents=True, exist_ok=True, mode=0o700)
        (CONFIG / "STOP").touch(exist_ok=True)
        raise RuntimeError(
            "Interrupted; STOP requested and session left incomplete. "
            "Inspect TEST game exit before any new run."
        ) from interrupt
    finally:
        store_new(directory / "session-state.json", {
            "state": status, "game_process_clean_exit_independently_proven":
                status == "completed_with_unverified_visual_input_audio",
            "partial_data_is_not_a_passing_result": True,
            "stop_or_crash_requires_human_inspection": status != "completed_with_unverified_visual_input_audio",
        })


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--session", type=int, choices=(1, 2), default=1)
    p.add_argument("--run", action="store_true", help="Run the reviewed TEST diagnostic; default is no-launch preflight")
    p.add_argument("--no-local-cpu-profile", action="store_true",
                   help="Skip optional native macOS CPU stack sampling")
    args = p.parse_args(argv)
    detail = check_environment(args.session)
    if not args.run:
        print(json.dumps({
            **detail, "will_launch_game": False, "local_environment": mac_snapshot(),
            "next_action": "pass --run to execute one explicitly selected TEST session",
        }, indent=2, sort_keys=True))
        return 0
    print(json.dumps(run_session(args.session, profile_cpu=not args.no_local_cpu_profile),
                     indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError, TypeError, json.JSONDecodeError) as err:
        print("MENU SESSION FAILED CLOSED:", err, file=sys.stderr)
        raise SystemExit(2)
