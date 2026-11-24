import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
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
            window.delegate = self
            window.center()
            settingsWindow = window
        }
        // Medan inställningarna är öppna är Panel en vanlig app (med meny), så att man kan skriva och klistra in.
        NSApp.setActivationPolicy(.regular)
        NSApp.mainMenu = Self.makeMenu()
        settingsWindow?.makeKeyAndOrderFront(nil)
        if #available(macOS 14.0, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.settingsWindow?.makeKeyAndOrderFront(nil) }
    }

    func windowWillClose(_ notification: Notification) {
        // Tillbaka till osynlig app (ingen ikon i Docken).
        DispatchQueue.main.async { NSApp.setActivationPolicy(.accessory) }
    }

    /// Arkiv- och Redigera-meny: utan dem fungerar inte Cmd+V, Cmd+C, Cmd+A och Cmd+W.
    static func makeMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Stäng fönstret", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: "Avsluta Panel", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Redigera")
        edit.addItem(withTitle: "Ångra", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Gör om", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Klipp ut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Kopiera", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Klistra in", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Markera allt", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        return main
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
