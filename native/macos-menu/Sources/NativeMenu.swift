#if os(macOS)
import AppKit
import Foundation
import ImageIO

/// Deliberately standalone: no Wine, DirectDraw, original EXE or injected DLL.
/// This is an original-menu-background viewer, NOT a playable game.
final class NativeMenuApplication: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var background: NSImageView!
    private var status: NSTextField!

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Rock Raiders — Native Menu Prototype"
        window.center()
        window.minSize = NSSize(width: 640, height: 480)
        window.contentAspectRatio = NSSize(width: 4, height: 3)
        let root = NSView(frame: window.contentView!.bounds)
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.black.cgColor
        window.contentView = root

        background = NSImageView(frame: root.bounds)
        background.autoresizingMask = [.width, .height]
        background.imageScaling = .scaleProportionallyUpOrDown
        background.imageAlignment = .alignCenter
        root.addSubview(background)

        let controls = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 800, height: 80))
        controls.material = .hudWindow
        controls.blendingMode = .withinWindow
        controls.state = .active
        controls.autoresizingMask = [.width, .maxYMargin]
        root.addSubview(controls)

        let open = NSButton(title: "Open LegoRR0.wad…", target: self, action: #selector(openArchive))
        let about = NSButton(title: "About This Prototype", target: self, action: #selector(aboutPrototype))
        let quit = NSButton(title: "Quit", target: NSApp, action: #selector(NSApplication.terminate(_:)))
        let buttons = NSStackView(views: [open, about, quit])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 12
        buttons.translatesAutoresizingMaskIntoConstraints = false
        controls.addSubview(buttons)

        status = NSTextField(labelWithString: "Select your original LegoRR0.wad file. No data will be modified or uploaded.")
        status.lineBreakMode = .byTruncatingTail
        status.textColor = .labelColor
        status.translatesAutoresizingMaskIntoConstraints = false
        controls.addSubview(status)
        NSLayoutConstraint.activate([
            buttons.leadingAnchor.constraint(equalTo: controls.leadingAnchor, constant: 16),
            buttons.topAnchor.constraint(equalTo: controls.topAnchor, constant: 9),
            status.leadingAnchor.constraint(equalTo: controls.leadingAnchor, constant: 16),
            status.trailingAnchor.constraint(lessThanOrEqualTo: controls.trailingAnchor, constant: -16),
            status.topAnchor.constraint(equalTo: buttons.bottomAnchor, constant: 6)
        ])
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if CommandLine.arguments.count > 1 {
            load(URL(fileURLWithPath: CommandLine.arguments[1]))
        }
    }

    @objc private func openArchive() {
        let chooser = NSOpenPanel()
        chooser.canChooseFiles = true
        chooser.canChooseDirectories = false
        chooser.allowsMultipleSelection = false
        chooser.message = "Select a copy of LegoRR0.wad from your original Rock Raiders installation."
        chooser.beginSheetModal(for: window) { [weak self] response in
            if response == .OK, let url = chooser.url { self?.load(url) }
        }
    }

    private func load(_ url: URL) {
        do {
            let wad = try WadArchive(url: url)
            let bmp = try wad.asset("Interface/FrontEnd/MenuBGpic.bmp")
            guard bmp.count >= 2 && bmp.prefix(2) == Data([66, 77]) else {
                throw WadArchive.WadError.invalid("menu background is not a BMP image")
            }
            guard let source = CGImageSourceCreateWithData(bmp as CFData, nil),
                  let cg = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  cg.width > 0, cg.height > 0,
                  cg.width <= 8192, cg.height <= 8192 else {
                throw WadArchive.WadError.invalid("macOS cannot decode the menu BMP")
            }
            background.image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            status.stringValue = "Original menu background loaded (\(cg.width) × \(cg.height)); viewer only — no game yet."
            window.title = "Rock Raiders — Native Menu Prototype (asset loaded)"
        } catch {
            status.stringValue = "Unable to load menu background."
            let alert = NSAlert()
            alert.messageText = "Cannot open Rock Raiders menu background"
            alert.informativeText = "\(error)\n\nYour WAD file was not changed."
            alert.alertStyle = .warning
            alert.beginSheetModal(for: window)
        }
    }

    @objc private func aboutPrototype() {
        let alert = NSAlert()
        alert.messageText = "Native macOS proof of concept"
        alert.informativeText = "This program reads the original menu background from your WAD, displays it in an AppKit window, and exits cleanly. It does not yet implement LEGO Rock Raiders gameplay, animated menus, sound, or frame-rate benchmarks. It never uses Wine or modifies the original game."
        alert.beginSheetModal(for: window)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main struct NativeMenuMain {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = NativeMenuApplication()
        app.delegate = delegate
        app.run()
    }
}
#endif
