import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store: Store
    var controller: PanelController?
    var settingsWindow: NSWindow?
    var refreshTimer: Timer?
    var updateTimer: Timer?

    override init() {
        store = Store()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = PanelController(store: store)
        store.openSettings = { [weak self] in self?.showSettings() }
        Task { await store.refresh() }
        let minutes = Double(max(1, store.config.refreshMinutes))
        refreshTimer = Timer.scheduledTimer(withTimeInterval: minutes * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.store.refresh() }
        }
        // Nya versioner från GitHub: en minut efter start och sedan varje timme.
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { Updater.check() }
        updateTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in Updater.check() }
        // Första gången: visa inställningarna så att man ser att appen startat.
        if !FileManager.default.fileExists(atPath: Config.file.path) {
            store.config.save()
            showSettings()
        }
    }

    /// Startar man appen igen (dubbelklick) öppnas inställningarna.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func showSettings() {
        controller?.hide()
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 720),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Panel – inställningar"
            window.contentView = NSHostingView(rootView: SettingsView(store: store))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

@main
@MainActor
enum PanelMain {
    static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // ingen ikon i Docken
        app.run()
    }
}
