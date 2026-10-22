"""Offline coverage audit for cross-platform evidence (no media reads)."""
from collections import Counter
import compare

SCHEMA = "openlrr-evidence-coverage-audit-v1"
SOURCES = {"video", "mac_input", "wine_api", "nerps", "openlrr_menu", "capture_control"}


def audit(mac_index, windows_report):
    mac = compare.normalize_mac(mac_index)
    win = compare.normalize_windows(windows_report)
    omitted = 0
    known = True
    counts = Counter()
    for clip in mac_index["clips"]:
        n = clip.get("events_omitted")
        if n is None:
            known = False
        elif type(n) is not int or not 0 <= n <= compare.MAX_EVENTS:
            raise ValueError("Invalid omitted-event count")
        else:
            omitted += n
        sources = clip.get("sources")
        if sources is None:
            known = False
            counts.update(e.get("source") for e in clip["events"]
                          if isinstance(e, dict) and e.get("source") in SOURCES)
            continue
        if not isinstance(sources, dict):
            raise ValueError("Invalid source counters")
        for name, count in sources.items():
            if name not in SOURCES or type(count) is not int or not 0 <= count <= compare.MAX_EVENTS:
                raise ValueError("Invalid source counter")
            preview = sum(isinstance(e, dict) and e.get("source") == name
                          for e in clip["events"])
            if preview > count:
                raise ValueError("Source counter contradicts indexed events")
        counts.update(sources)
    coverage = "unknown" if not known else "incomplete" if omitted else "complete"
    return {
        "schema": SCHEMA,
        "mac": {
            "clip_count": mac["clip_count"],
            "event_preview_coverage": coverage,
            "events_omitted": omitted if known else None,
            "indexed_input_events": counts["mac_input"],
            "indexed_wine_events": counts["wine_api"],
            "indexed_nerps_events": counts["nerps"],
            "original_game_attested": False,
        },
        "windows": {
            "controller_status": win["controller_status"],
            "frame_records": len(win["visual_observations"]),
            "original_game_attested": False,
        },
        "cross_platform": {
            "frame_synchronized": False,
            "gameplay_parity": "not_established",
            "action_overlap_complete": False,
        },
    }
