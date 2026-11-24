import AppKit
import SwiftUI

/// Ett fönster som kan ta emot klick och text utan att ta fokus från appen du jobbar i.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Visar panelen när musen förs upp till kameran (eller mitten av skärmens överkant på en skärm utan kamera),
/// och döljer den när musen lämnar den.
@MainActor
final class PanelController {
    private let store: Store
    private let panel: FloatingPanel
    private let hosting: NSHostingView<PanelView>
    private let motion: Motion
    private var timer: Timer?
    private var musicTimer: Timer?
    private var hoverSince: Date?
    private var outsideSince: Date?
    private var clickMonitor: Any?
    private(set) var isShown = false

    init(store: Store) {
        self.store = store
        let motion = Motion()
        self.motion = motion
        hosting = NSHostingView(rootView: PanelView(store: store, motion: motion))
        panel = FloatingPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false          // skuggan ritas av panelen själv
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.contentView = hosting
        panel.ignoresMouseEvents = true

        store.layoutChanged = { [weak self] in self?.resize() }
        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // Medan panelen är öppen: håll musiken aktuell.
        musicTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isShown else { return }
                await self.store.refreshMusic()
            }
        }
        // Klick utanför panelen stänger den (även om du skriver i den).
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in if self?.isShown == true { self?.hide() } }
        }
    }

    /// Området som öppnar panelen: kamerans "notch", annars en remsa mitt i överkanten.
    private func hotspot(on screen: NSScreen) -> NSRect {
        let f = screen.frame
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let x0 = f.minX + left.width, x1 = f.maxX - right.width
            return NSRect(x: x0, y: f.maxY - 34, width: max(80, x1 - x0), height: 34)
        }
        return NSRect(x: f.midX - 130, y: f.maxY - 3, width: 260, height: 3)
    }

    private func tick() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) else { return }

        if !isShown {
            if NSMouseInRect(mouse, hotspot(on: screen), false) {
                if hoverSince == nil { hoverSince = Date() }
                if Date().timeIntervalSince(hoverSince!) > 0.12 { show(on: screen) }
            } else {
                hoverSince = nil
            }
            return
        }

        // Ligger musen kvar över panelen eller kameran? Annars stäng efter en kort stund.
        let inside = NSMouseInRect(mouse, panel.frame.insetBy(dx: 20, dy: 0), false) || NSMouseInRect(mouse, hotspot(on: screen), false)
        let typing = panel.isKeyWindow && panel.firstResponder is NSTextView   // stäng inte mitt i en text
        if inside || typing {
            outsideSince = nil
        } else {
            if outsideSince == nil { outsideSince = Date() }
            if Date().timeIntervalSince(outsideSince!) > 0.35 { hide() }
        }
    }

    private func targetFrame(on screen: NSScreen) -> NSRect {
        let size = hosting.fittingSize
        let f = screen.frame
        let top = screen.visibleFrame.maxY            // precis under menyraden, så att menyraden alltid syns
        let center = screen.auxiliaryTopLeftArea.map { f.minX + $0.width + (f.width - $0.width - (screen.auxiliaryTopRightArea?.width ?? 0)) / 2 } ?? f.midX
        var x = center - size.width / 2
        x = min(max(x, f.minX - 36), f.maxX - size.width + 36)
        return NSRect(x: x, y: top - size.height + 2, width: size.width, height: size.height)
    }

    func show(on screen: NSScreen? = nil) {
        guard !isShown, let screen = screen ?? NSScreen.main else { return }
        isShown = true
        hoverSince = nil
        if Date().timeIntervalSince(store.lastRefresh) > 30 { Task { await store.refresh() } }
        else { Task { await store.refreshMusic() } }
        panel.setFrame(targetFrame(on: screen), display: true)
        panel.ignoresMouseEvents = false
        panel.orderFrontRegardless()
        // Panelen fjädrar ner från kameran; korten följer efter en i taget (se PanelView).
        withAnimation(panelSpring) { motion.open = true }
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        outsideSince = nil
        panel.ignoresMouseEvents = true
        withAnimation(.spring(response: 0.3, dampingFraction: 1)) { motion.open = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, !self.isShown else { return }
            self.panel.orderOut(nil)
        }
    }

    /// När delar läggs till eller tas bort ändras panelens storlek.
    func resize() {
        guard isShown, let screen = panel.screen ?? NSScreen.main else { return }
        panel.setFrame(targetFrame(on: screen), display: true, animate: true)
    }
}
