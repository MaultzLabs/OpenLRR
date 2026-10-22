// Native Rock Raiders window-only capture probe.
// Build: xcrun swiftc -O -framework Cocoa -framework CoreGraphics \
//          window_probe.swift -o build/window_probe
//
// Modes: list, inspect WINDOW_ID OWNER_PID, events WINDOW_ID OWNER_PID.
// NEVER captures desktop or any unrelated window contents.
import AppKit
import CoreGraphics
import Foundation

struct WindowRecord {
    let id: Int
    let pid: Int
    let name: String
    let title: String
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let onscreen: Bool

    var safeIdentity: Bool {
        let gameTitle = title.lowercased()
        let gameOwner = name.lowercased()
        let matchesTitle = gameTitle.contains("rock raiders") ||
                           gameTitle.contains("legorr") ||
                           gameTitle.contains("openlrr")
        // A browser tab titled "Rock Raiders" is not a game! Require
        // both a retail game title AND a Wine/game executable owner.
        let matchesOwner = ["wine", "wineskin", "whisky", "crossover",
                            "sikarugir", "rock raiders", "legorr",
                            "openlrr"].contains(where: gameOwner.contains)
        return matchesTitle && matchesOwner &&
               width >= 320 && height >= 200 &&
               width <= 8192 && height <= 8192 && id > 0 && pid > 0
    }

    var dictionary: [String: Any] {
        [
            "id": id, "pid": pid,
            "bounds": ["x": x, "y": y, "width": width, "height": height],
            "onscreen": onscreen,
            // Used in local list output only; never in session summary.
            "title": title, "owner": name
        ]
    }
}

func windowRecords() -> [WindowRecord] {
    let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
    guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
                    as? [[String: Any]] else { return [] }
    var records: [WindowRecord] = []
    for window in windows {
        guard let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue,
              layer == 0,
              let id = (window[kCGWindowNumber as String] as? NSNumber)?.intValue,
              let pid = (window[kCGWindowOwnerPID as String] as? NSNumber)?.intValue,
              let bounds = window[kCGWindowBounds as String] as? [String: Any],
              let x = (bounds["X"] as? NSNumber)?.doubleValue,
              let y = (bounds["Y"] as? NSNumber)?.doubleValue,
              let w = (bounds["Width"] as? NSNumber)?.doubleValue,
              let h = (bounds["Height"] as? NSNumber)?.doubleValue else { continue }
        records.append(WindowRecord(
            id: id, pid: pid,
            name: window[kCGWindowOwnerName as String] as? String ?? "",
            title: window[kCGWindowName as String] as? String ?? "",
            x: x, y: y, width: w, height: h,
            onscreen: (window[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false))
    }
    return records
}

func emit(_ value: [String: Any]) {
    guard JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value,
                                                 options: [.sortedKeys]),
          let json = String(data: data, encoding: .utf8) else { return }
    print(json)
    fflush(stdout)
}

func gameWindow(id: Int, pid: Int) -> WindowRecord? {
    windowRecords().first(where: { $0.id == id && $0.pid == pid &&
                                    $0.safeIdentity })
}

func checkedInt(_ index: Int) -> Int? {
    guard CommandLine.arguments.count > index else { return nil }
    return Int(CommandLine.arguments[index])
}

guard CommandLine.arguments.count >= 2 else {
    fputs("usage: window_probe list | inspect ID PID | events ID PID\n", stderr)
    exit(2)
}
let mode = CommandLine.arguments[1]
if mode == "list" {
    for item in windowRecords() where item.safeIdentity && item.onscreen {
        emit(item.dictionary)
    }
    exit(0)
}

if mode == "diagnose" {
    // Diagnostic COUNTS ONLY. Do not expose unrelated window names, titles,
    // application paths, process arguments or desktop pixel data.
    let windows = windowRecords().filter { $0.onscreen && $0.width >= 320 &&
        $0.height >= 200 && $0.width <= 8192 && $0.height <= 8192 }
    let wineWords = ["wine", "wineskin", "whisky", "crossover",
                     "sikarugir", "rock raiders", "legorr", "openlrr"]
    let wine = windows.filter { window in
        wineWords.contains(where: window.name.lowercased().contains)
    }
    emit([
        "screen_recording_permission": CGPreflightScreenCaptureAccess(),
        "input_monitoring_permission": CGPreflightListenEventAccess(),
        "eligible_game_windows": windows.filter { $0.safeIdentity }.count,
        "wine_like_windows": wine.count,
        "wine_like_untitled_windows": wine.filter { $0.title.isEmpty }.count,
        "wine_like_titled_windows": wine.filter { !$0.title.isEmpty }.count,
        "counts_only": true
    ])
    exit(0)
}


guard (mode == "inspect" || mode == "events"),
      let id = checkedInt(2), let pid = checkedInt(3),
      id > 0, pid > 0 else {
    fputs("expected inspect/events with a positive window ID and PID\n", stderr)
    exit(2)
}

if mode == "inspect" {
    if let window = gameWindow(id: id, pid: pid) {
        emit(["exists": true, "id": id, "pid": pid,
              "onscreen": window.onscreen,
              "bounds": ["x": window.x, "y": window.y,
                         "width": window.width, "height": window.height]])
    } else {
        emit(["exists": false, "id": id, "pid": pid])
    }
    exit(0)
}

guard gameWindow(id: id, pid: pid) != nil else {
    fputs("game window no longer exists: refusing global input monitor\n", stderr)
    exit(3)
}
// Refuse to silently launch an input-less session. This checks the helper\u0027s
// own macOS Input Monitoring permission without requesting broad access.
guard CGPreflightListenEventAccess() else {
    fputs("Input Monitoring permission is missing for the game-window helper.\n", stderr)
    exit(4)
}
NSApplication.shared.setActivationPolicy(.prohibited)

// Log game-focused hardware keycodes, never text, clipboard or input
// outside the verified game window. A short hardcoded WASD subset misses
// actual Rock Raiders hotkeys and mislabels normal play as no input.
let gameOwnerHints = ["wine", "wineskin", "whisky", "crossover",
                      "sikarugir", "rock raiders", "legorr", "openlrr"]
func gameIsFrontmost(_ target: WindowRecord) -> Bool {
    // Wine's visible game window PID may differ from the active Wineskin
    // wrapper app PID. Require the *actual* topmost on-screen normal window
    // to be this game, plus a verified active Wine/game application.
    guard windowRecords().first(where: { $0.onscreen })?.id == target.id,
          let foreground = NSWorkspace.shared.frontmostApplication else {
        return false
    }
    if Int(foreground.processIdentifier) == target.pid { return true }
    let activeName = (foreground.localizedName ?? "").lowercased()
    return gameOwnerHints.contains(where: activeName.contains)
}
let mask: NSEvent.EventTypeMask = [
    .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
    .mouseMoved, .leftMouseDragged, .rightMouseDragged,
    .scrollWheel, .keyDown, .keyUp, .flagsChanged
]
var lastMove: TimeInterval = 0
let observer = NSEvent.addGlobalMonitorForEvents(matching: mask) { event in
    // A Wine process can own additional settings or prompt windows.
    // Require the exact target game window to be foremost within its app,
    // not merely some foreground Wine window or a similarly titled browser.
    guard let target = gameWindow(id: id, pid: pid), target.onscreen,
          gameIsFrontmost(target) else { return }
    let now = ProcessInfo.processInfo.systemUptime
    var data: [String: Any] = [
        "source": "mac_input", "monotonic_s": now,
        "unix_s": Date().timeIntervalSince1970,
        "window_id": id
    ]
    switch event.type {
    case .keyDown, .keyUp, .flagsChanged:
        data["event"] = event.type == .keyDown ? "key_down" :
                        (event.type == .keyUp ? "key_up" : "modifier_changed")
        data["keycode"] = Int(event.keyCode)
        data["modifier_flags"] = Int(event.modifierFlags.rawValue & 0x1fffff)
    case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
         .mouseMoved, .leftMouseDragged, .rightMouseDragged, .scrollWheel:
        guard let position = event.cgEvent?.location else { return }
        let dx = position.x - target.x
        let dy = position.y - target.y
        guard dx >= 0 && dy >= 0 && dx < target.width && dy < target.height else {
            return
        }
        switch event.type {
        case .leftMouseDown: data["event"] = "left_down"
        case .leftMouseUp: data["event"] = "left_up"
        case .rightMouseDown: data["event"] = "right_down"
        case .rightMouseUp: data["event"] = "right_up"
        case .scrollWheel:
            data["event"] = "scroll"
            data["scroll_y"] = event.scrollingDeltaY
        default:
            if now - lastMove < 0.08 { return }
            lastMove = now
            data["event"] = "mouse_move"
        }
        data["x"] = Int(dx)
        data["y"] = Int(dy)
        data["x_normalized"] = round(Double(dx) / target.width * 10000) / 10000
        data["y_normalized"] = round(Double(dy) / target.height * 10000) / 10000
    default: return
    }
    emit(data)
}
guard let observer else {
    fputs("Input Monitoring permission unavailable; screenshots can continue without input.\n", stderr)
    exit(4)
}

// An installed NSEvent monitor is not proof of delivered clicks/keys.
// The coordinator also counts actual game-scoped events.
emit(["source": "capture_control", "event": "input_monitor_ready",
      "window_id": id, "unix_s": Date().timeIntervalSince1970,
      "monotonic_s": ProcessInfo.processInfo.systemUptime])

// Stops even if the parent capture supervisor exits.
let guardTimer = Timer(timeInterval: 0.25, repeats: true) { _ in
    if gameWindow(id: id, pid: pid) == nil {
        emit(["source": "capture_control", "event": "game_window_closed",
              "unix_s": Date().timeIntervalSince1970])
        CFRunLoopStop(CFRunLoopGetMain())
    }
}
RunLoop.current.add(guardTimer, forMode: .default)
while gameWindow(id: id, pid: pid) != nil {
    _ = RunLoop.current.run(mode: .default,
                            before: Date(timeIntervalSinceNow: 0.25))
}
NSEvent.removeMonitor(observer)
