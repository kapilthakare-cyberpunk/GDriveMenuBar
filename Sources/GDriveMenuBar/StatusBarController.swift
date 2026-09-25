import AppKit
import SwiftUI

@MainActor
final class GDriveStatusController {
    private var item: NSStatusItem?
    private let popover = NSPopover()
    private let store = GDriveStore()
    private var timer: Timer?

    func start() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if #available(macOS 11.0, *) { item?.isVisible = true }
        if let button = item?.button {
            button.action = #selector(toggle(_:))
            button.target = self
            button.image = NSImage(systemSymbolName: "icloud", accessibilityDescription: "GDrive")
            button.image?.isTemplate = true
            button.font = .menuBarFont(ofSize: 13)
        }
        popover.contentViewController = NSHostingController(rootView: GDrivePopoverView(store: store))
        popover.behavior = .transient
        popover.animates = true
        store.refresh()
        updateTitle()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.store.refresh()
                self?.updateTitle()
            }
        }
        debug("started pid=\(ProcessInfo.processInfo.processIdentifier)")
    }

    private func updateTitle() {
        guard let button = item?.button else { return }
        if store.snap.cap.available {
            button.title = "\(Int(store.snap.cap.usedPct))%"
        } else {
            button.title = store.snap.state
        }
        debug("title=\(button.title)")
    }

    @objc private func toggle(_ sender: Any?) {
        guard let button = item?.button else { return }
        if popover.isShown { popover.performClose(sender) }
        else { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
    }

    private func debug(_ msg: String) {
        guard ProcessInfo.processInfo.environment["GDRIVE_DEBUG"] != nil else { return }
        let line = "[GDriveMenuBar] \(msg)\n"
        if let fh = try? FileHandle(forWritingTo: URL(fileURLWithPath: "/tmp/GDriveMenuBar.debug.log")) {
            _ = try? fh.seekToEnd()
            try? fh.write(contentsOf: line.data(using: .utf8) ?? Data())
            try? fh.close()
        } else {
            try? line.write(toFile: "/tmp/GDriveMenuBar.debug.log", atomically: false, encoding: .utf8)
        }
    }
}
