#!/usr/bin/env python3
"""Safe opt-in macOS sample() sidecar for already-running OpenLRR TEST Wine.

This tool NEVER launches, terminates, changes or installs a game process.
It refuses non-Wine PIDs or ambiguous ownership, bounds sampling time and
stores raw potentially-sensitive macOS stacks LOCALLY only. The summary is
categorical and is not proof of Wine/driver root cause or displayed FPS.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import subprocess
import sys

HOME = Path.home()
APP = HOME / "Applications/Sikarugir/OpenLRR Menu Test.app"
GAME = APP / "Contents/SharedSupport/prefix/drive_c/Program Files/Rock Raiders OpenLRR"
CONFIG = HOME / ".config/openlrr-benchmark"
STATE = HOME / ".local/share/openlrr-agent/wine-cpu-profiles"
SAMPLE_BINARY = Path("/usr/bin/sample")
SYMBOLS = (
    "ddraw", "wined3d", "win32u", "wine", "quartz",
    "coreanimation", "metal", "libsystem_kernel", "pthread",
)
PID = re.compile(r"^[1-9][0-9]{0,9}$")
MAX_RAW_BYTES = 8_000_000
MAX_DISCOVERED_PIDS = 16
SECONDS = 3
SAMPLE_INTERVAL_MS = 20


def stop_check() -> None:
    if (CONFIG / "STOP").exists() or (CONFIG / "PAUSE").exists():
        raise RuntimeError("STOP/PAUSE active; CPU sampling disabled")


def validate_test_target() -> None:
    if APP.is_symlink() or GAME.is_symlink() or not APP.is_dir() or not GAME.is_dir():
        raise RuntimeError("Dedicated TEST game is unavailable")
    if not GAME.resolve(strict=True).is_relative_to(APP.resolve(strict=True)):
        raise RuntimeError("TEST directory resolves outside the isolated app")
    if not (GAME / "LegoRR.exe").is_file():
        raise RuntimeError("TEST executable missing")


def checked_run(args: list[str], *, timeout: int) -> str:
    proc = subprocess.run(
        args, capture_output=True, text=True,
        check=False, timeout=timeout,
    )
    # macOS lsof returns 1 with empty stdout/stderr when no process has
    # that exact file open. This is an ordinary no-writer condition, not
    # permission to fall back to a process-name-only search.
    if proc.returncode:
        if (args[0] == "/usr/sbin/lsof" and proc.returncode == 1
                and not proc.stdout.strip() and not proc.stderr.strip()):
            return ""
        raise RuntimeError("CPU sampling process lookup or profiling failed")
    if len(proc.stdout) > 8192:
        raise RuntimeError("Excessive Mac process lookup output")
    return proc.stdout


def writable_test_csv_owners(raw: str, expected: Path) -> set[str]:
    """Extract writers by lsof's per-FD access field, not by process name.

    -Fpcfan reports p=PID, c=command, f=descriptor, a=access (r/w/u),
    n=exact opened pathname. A read-only observer is never a game writer.
    Reject malformed output rather than treating a process name as evidence.
    """
    owners: set[str] = set()
    owner = None
    descriptor = None
    access = None
    name = None

    def finish() -> None:
        if descriptor is not None and name == str(expected) and access in ("w", "u"):
            if owner is None or not PID.fullmatch(owner):
                raise RuntimeError("Malformed TEST telemetry file owner identity")
            owners.add(owner)

    if len(raw) > 8192:
        raise RuntimeError("Oversized TEST telemetry process descriptor response")
    for line in raw.splitlines():
        if not line:
            continue
        field, value = line[0], line[1:]
        if field == "p":
            finish()
            if not PID.fullmatch(value):
                raise RuntimeError("Malformed TEST telemetry process identifier")
            owner, descriptor, access, name = value, None, None, None
        elif field == "f":
            finish()
            if owner is None:
                raise RuntimeError("File descriptor without TEST process identity")
            descriptor, access, name = value, None, None
        elif field == "a":
            if descriptor is None:
                raise RuntimeError("File access mode without descriptor")
            access = value.lower()
        elif field == "n":
            if descriptor is None:
                raise RuntimeError("File name without descriptor")
            name = value
        elif field == "c":
            # Do not use or publish the arbitrary process name from lsof.
            continue
        else:
            raise RuntimeError("Unexpected TEST telemetry descriptor field")
    finish()
    return owners


def recognizable_test_game_identity(command: str) -> bool:
    """Accept known Wine naming OR a directly TEST-bundle-bound launcher."""
    lower = command.lower()
    return any(token in lower for token in ("wine", "legorr", "rock raiders")) or (
        str(APP).lower() in lower and
        any(token in lower for token in ("sikarugir", "wineskin"))
    )


def verified_test_writer_roles() -> dict[str, str]:
    """Classify writable owners; do not attach or infer a PID from ordering.

    A Wine child and Wine wrapper may both hold the same writable descriptor.
    A unique LegoRR owner wins. Alternatively, one Wine owner accompanied
    ONLY by TEST wrappers is safe to select. Otherwise fail closed.
    """
    stop_check()
    validate_test_target()
    live = GAME / "menuperf.csv"
    header = "seconds,optimization,nowait,gdi,operation,calls,total_ms,max_ms"
    if live.is_symlink() or not live.is_file() or live.stat().st_size < len(header):
        raise RuntimeError("No verified live TEST menu telemetry file")
    with live.open("r", encoding="utf-8", errors="replace") as stream:
        if stream.readline().strip() != header:
            raise RuntimeError("TEST menu telemetry header is invalid")
    raw = checked_run(["/usr/sbin/lsof", "-nP", "-Fpcfan", str(live)], timeout=20)
    writers = writable_test_csv_owners(raw, live)
    if not writers:
        raise RuntimeError("No verified writable TEST menu telemetry owner found")
    if len(writers) > MAX_DISCOVERED_PIDS:
        raise RuntimeError("Too many TEST telemetry writable owners")

    roles: dict[str, str] = {}
    for pid in sorted(writers, key=int):
        # Arguments are never retained in the report, logged or uploaded.
        name = checked_run(["/bin/ps", "-p", pid, "-o", "comm="], timeout=5).strip()
        argv = checked_run(["/bin/ps", "-p", pid, "-o", "command="], timeout=5).strip()
        command = name + "\n" + argv
        if re.search(r"(?<![a-z0-9])legorr(?:\.exe)?(?![a-z0-9])", command.lower()):
            roles[pid] = "game_executable"
        elif (str(APP).lower() in command.lower()
              and any(x in command.lower() for x in ("sikarugir", "wineskin"))):
            roles[pid] = "isolated_test_wrapper"
        elif any(x in command.lower() for x in ("wine", "rock raiders")):
            roles[pid] = "wine_related"
        else:
            roles[pid] = "unrecognized"
    return roles


def selected_verified_test_pid(roles: dict[str, str]) -> str:
    if not roles:
        raise RuntimeError("No verified writable TEST menu telemetry owner found")
    if len(roles) == 1:
        pid, role = next(iter(roles.items()))
        if role not in ("game_executable", "wine_related"):
            raise RuntimeError("TEST telemetry owner is not a Wine game process")
        return pid
    game = [pid for pid, role in roles.items() if role == "game_executable"]
    if len(game) == 1:
        return game[0]
    # The real Mac October 19 trace reported one Wine process and one
    # isolated Wineskin wrapper sharing the verified TEST telemetry file.
    # Sample the uniquely identified Wine owner, NEVER the wrapper.
    wine = [pid for pid, role in roles.items() if role == "wine_related"]
    if not game and len(wine) == 1 and all(
            role in ("wine_related", "isolated_test_wrapper")
            for role in roles.values()):
        return wine[0]
    raise RuntimeError("Multiple writable TEST menu telemetry owners")


def sanitized_test_writer_inspection(roles: dict[str, str]) -> dict:
    """No PIDs, process commands, file locations, or personal paths leave Mac."""
    allowed = ("game_executable", "isolated_test_wrapper", "wine_related",
               "unrecognized")
    counts = {kind: sum(role == kind for role in roles.values())
              for kind in allowed}
    try:
        selected_verified_test_pid(roles)
        state = "unique_target_verified"
    except RuntimeError:
        state = "ambiguous_or_unrecognized"
    return {
        "schema_version": 1,
        "status": state,
        "writer_count": len(roles),
        "owner_role_counts": counts,
        "pid_values_exposed": False,
        "raw_commands_exposed": False,
        "launches_game": False,
        "attempts_native_sampling": False,
    }


def find_test_wine_pid() -> str:
    return selected_verified_test_pid(verified_test_writer_roles())


# All report categories are allowlisted. No discovered symbol, address,
# source path, environment value or thread name enters the safe summary.
SAMPLE_CATEGORIES = (
    "ddraw", "wined3d", "win32u", "wine_other", "metal",
    "coreanimation", "quartz", "kernel_wait", "libsystem_kernel",
    "pthread", "other",
)
SAMPLE_FRAME = re.compile(r"^([ \t+|:!]*)([0-9]{1,9})[ \t]+(.+)$")


def _frame_category(symbol: str) -> str:
    lower = symbol.lower()
    # Order matters: metal framework, DirectDraw and WineD3D may all occur
    # in one call chain. We classify only the sampled leaf's own frame.
    for label, pattern in (
        ("wined3d", r"\bwined3d\b"),
        ("ddraw", r"\bddraw\b"),
        ("win32u", r"\bwin32u\b"),
        ("coreanimation", r"\bcoreanimation\b"),
        ("metal", r"\bmetal\b|\bmtl(?:command|device|blit)"),
        ("quartz", r"\bquartz\b"),
        ("kernel_wait", r"\b(?:semaphore_wait_trap|__ulock_wait|mach_msg_trap|__psynch_cvwait)\b"),
        ("libsystem_kernel", r"\blibsystem_kernel\b"),
        ("pthread", r"\bpthread\b"),
        ("wine_other", r"\bwine(?:64)?\b"),
    ):
        if re.search(pattern, lower):
            return label
    return "other"


def sample_tree_hotspots(data: str) -> dict:
    """Parse macOS sample's inclusive call-tree counts, using guide columns.

    Exclusive leaf weight = inclusive frame samples minus direct children.
    These are thread-stack observations, NOT wall-time CPU percentages, a
    diagnosis of a GPU driver, or necessarily the graphics thread.
    """
    counts = {category: 0 for category in SAMPLE_CATEGORIES}
    if "Call graph:" not in data:
        return {"status": "unrecognized_sample_format", "leaf_samples": counts,
                "thread_root_count": 0, "total_leaf_sample_observations": 0}
    nodes = []
    parents = []
    graph = False
    thread_roots = 0
    for line in data.splitlines():
        if not graph:
            if line.strip() == "Call graph:":
                graph = True
            continue
        if line.strip().startswith(("Total number in stack", "Binary Images:",
                                    "Sort by top of stack", "Heaviest stack",
                                    "Sample analysis of process")):
            break
        matched = SAMPLE_FRAME.match(line)
        if not matched:
            continue
        indent, count_s, symbol = matched.groups()
        depth = len(indent.expandtabs(4))
        count = int(count_s)
        if count <= 0:
            continue
        while parents and nodes[parents[-1]]["depth"] >= depth:
            parents.pop()
        # Reject malformed nesting instead of attributing a thread-root's
        # inclusive sample count to a guessed module.
        is_thread = bool(re.search(r"\bThread_[0-9]+\b", symbol))
        if not parents and not is_thread:
            continue
        if is_thread:
            parents.clear()
            thread_roots += 1
        node = {"depth": depth, "count": count, "children": 0,
                "category": None if is_thread else _frame_category(symbol)}
        if parents:
            nodes[parents[-1]]["children"] += count
        nodes.append(node)
        parents.append(len(nodes) - 1)
    for node in nodes:
        exclusive = max(0, node["count"] - node["children"])
        if node["category"] is not None:
            counts[node["category"]] += exclusive
    total = sum(counts.values())
    return {
        "status": "parsed" if thread_roots and total else "unrecognized_sample_format",
        "thread_root_count": min(thread_roots, 10000),
        "total_leaf_sample_observations": total,
        "leaf_samples": counts,
        "fraction_denominator": "all parsed thread leaf observations, not process CPU time",
    }


def summarize_latest_local_trace() -> dict:
    """Reanalyze a prior local trace without starting Wine or attaching a PID."""
    if STATE.is_symlink() or not STATE.is_dir():
        raise RuntimeError("No safe local CPU profiler state directory")
    candidates = [
        p for p in STATE.glob("sample_*/raw-local-only.sample")
        if not p.is_symlink() and not p.parent.is_symlink() and p.is_file()
        and 0 < p.stat().st_size <= MAX_RAW_BYTES
    ]
    if not candidates:
        raise RuntimeError("No valid existing local CPU trace")
    chosen = max(candidates, key=lambda p: p.stat().st_mtime_ns)
    raw = chosen.read_text(encoding="utf-8", errors="replace")
    return {
        "status": "local_only_readonly_trace_analysis",
        "tested_process_at_analysis_time": False,
        "raw_trace_uploaded": False,
        "safe_to_upload_raw_trace": False,
        "cpu_tree": sample_tree_hotspots(raw),
    }


def sanitized_summary(data: str, pid: str) -> dict:
    if not PID.fullmatch(pid) or not isinstance(data, str):
        raise ValueError("Invalid local CPU trace")
    # Counts are counts of text occurrences, NOT sampling percentages or
    # attributed function execution time. No raw line/path is ever published.
    low = data.lower()
    counts = {
        name: len(re.findall(r"(?<![a-z0-9_])" + re.escape(name)
                             + r"(?![a-z0-9_])", low))
        for name in SYMBOLS
    }
    return {
        "schema_version": 1,
        "source": "local_mac_sample_cpu_stack_trace",
        "test_process_pid_verified": True,
        "pid_redacted": True,
        "seconds_requested": SECONDS,
        "sample_interval_ms_requested": SAMPLE_INTERVAL_MS,
        "symbol_mention_counts": counts,
        "cpu_tree": sample_tree_hotspots(data),
        "has_driver_attribution": False,
        "is_verified_visible_fps": False,
        "safe_to_upload_raw_trace": False,
        "started_game": False,
        "executed_ai_candidate": False,
        "modified_working_game": False,
    }


def capture(*, now: datetime | None = None) -> dict:
    stop_check()
    if not SAMPLE_BINARY.is_file():
        raise RuntimeError("macOS sample tool unavailable")
    target = find_test_wine_pid()
    stop_check()
    # Recheck the same TEST-only PID immediately before attachment; avoid
    # targeting a process that disappeared or changed during preflight.
    if find_test_wine_pid() != target:
        raise RuntimeError("TEST process identity changed during profiler preflight")
    now = (now or datetime.now(timezone.utc)).astimezone(timezone.utc)
    folder = STATE / ("sample_" + now.strftime("%Y%m%dT%H%M%SZ") + "_" + target)
    if STATE.is_symlink() or folder.exists() or folder.is_symlink():
        raise RuntimeError("CPU profiler output directory unsafe or already exists")
    folder.mkdir(parents=True, mode=0o700)
    raw = folder / "raw-local-only.sample"
    # sample is a macOS system profiler. It attaches to one already-running
    # TEST Wine process. It does not create or authorize a new game process.
    completed = subprocess.run(
        [str(SAMPLE_BINARY), target, str(SECONDS), str(SAMPLE_INTERVAL_MS),
         "-file", str(raw)],
        capture_output=True, text=True,
        check=False, timeout=SECONDS + 20,
    )
    if completed.returncode:
        raise RuntimeError("Mac CPU sampling failed; inspect local profiler folder")
    stop_check()
    if raw.is_symlink() or not raw.is_file() or not 0 < raw.stat().st_size <= MAX_RAW_BYTES:
        raise RuntimeError("Unusable or oversized local sample trace")
    raw.chmod(0o600)
    report = sanitized_summary(raw.read_text(encoding="utf-8", errors="replace"), target)
    summary = folder / "summary.json"
    with summary.open("x", encoding="utf-8") as stream:
        json.dump(report, stream, indent=2, sort_keys=True)
        stream.write("\n")
    summary.chmod(0o600)
    return {
        "status": "local_sample_recorded",
        "summary_path": str(summary),
        "raw_trace_path": str(raw),
        "raw_trace_uploaded": False,
        **report,
    }


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--capture", action="store_true",
                        help="Explicitly attach to an ALREADY RUNNING TEST Wine process")
    parser.add_argument("--summarize-latest", action="store_true",
                        help="Read and categorize a previous local trace, no game or sampling")
    parser.add_argument("--inspect-writers", action="store_true",
                        help="Classify currently running TEST telemetry owners; no sampling")
    args = parser.parse_args(argv)
    if sum((args.capture, args.summarize_latest, args.inspect_writers)) > 1:
        parser.error("Choose one action")
    if args.inspect_writers:
        print(json.dumps(sanitized_test_writer_inspection(
            verified_test_writer_roles()), indent=2, sort_keys=True))
        return 0
    if args.summarize_latest:
        print(json.dumps(summarize_latest_local_trace(), indent=2, sort_keys=True))
        return 0
    if not args.capture:
        print(json.dumps({
            "mode": "offline_preflight",
            "native_sample_started": False,
            "game_started": False,
            "raw_trace_uploaded": False,
        }, sort_keys=True))
        return 0
    print(json.dumps(capture(), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError,
            subprocess.SubprocessError) as exc:
        print("TEST CPU SAMPLING BLOCKED:", exc, file=sys.stderr)
        raise SystemExit(2)
