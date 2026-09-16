import AppKit

@main
struct GDriveMenuBarMain {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = GDriveMenuBarApp()
        app.delegate = delegate
        app.run()
    }
}

class GDriveMenuBarApp: NSObject, NSApplicationDelegate {
    private var controller: GDriveStatusController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        self.controller = GDriveStatusController()
        self.controller?.start()
    }
}
