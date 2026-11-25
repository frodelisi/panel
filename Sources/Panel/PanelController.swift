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
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
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

        updateHover(mouse)

        // Ligger musen kvar över panelen, ett utfällt kort eller kameran? Annars stäng efter en kort stund.
        let expanded = motion.hovered.map { expandedRect($0) } ?? .zero
        let inside = NSMouseInRect(mouse, glassRect.insetBy(dx: -12, dy: -12), false)
            || NSMouseInRect(mouse, expanded.insetBy(dx: -10, dy: -10), false)
            || NSMouseInRect(mouse, hotspot(on: screen), false)
        let typing = panel.isKeyWindow && panel.firstResponder is NSTextView   // stäng inte mitt i en text
        if inside || typing {
            outsideSince = nil
        } else {
            if outsideSince == nil { outsideSince = Date() }
            if Date().timeIntervalSince(outsideSince!) > 0.35 { hide() }
        }
    }

    // MARK: Vilket kort är musen över? (samma mått som PanelView, se Layout)

    private var moduleCount: Int { store.enabledModules.count }
    private var rowOrigin: NSPoint {   // radens övre vänstra hörn på skärmen
        NSPoint(x: panel.frame.minX + Layout.side + Layout.pad, y: panel.frame.maxY - Layout.rowTop)
    }
    private var glassRect: NSRect {
        NSRect(x: panel.frame.minX + Layout.side, y: panel.frame.maxY - Layout.top - Layout.glassHeight,
               width: Layout.contentWidth(moduleCount) + Layout.pad * 2, height: Layout.glassHeight)
    }
    private func compactRect(_ i: Int) -> NSRect {
        NSRect(x: rowOrigin.x + Layout.x(i, open: false, n: moduleCount), y: rowOrigin.y - Layout.ch, width: Layout.cw, height: Layout.ch)
    }
    private func expandedRect(_ i: Int) -> NSRect {
        let kinds = store.enabledModules.map(\.kind)
        let h = i < kinds.count ? Layout.fullHeight(kinds[i]) : Layout.ch
        return NSRect(x: rowOrigin.x + Layout.x(i, open: true, n: moduleCount), y: rowOrigin.y - h, width: Layout.fw, height: h)
    }

    private var hoverGoneSince: Date?
    private func updateHover(_ mouse: NSPoint) {
        var target: Int?
        if let h = motion.hovered, NSMouseInRect(mouse, expandedRect(h), false) {
            target = h                                            // kvar i det utfällda kortet
        } else {
            target = (0..<moduleCount).first { NSMouseInRect(mouse, compactRect($0), false) }
        }
        if target == motion.hovered { hoverGoneSince = nil; return }
        if target == nil {
            // Lite fördröjning, så att kortet inte fälls ihop när musen passerar mellanrummet.
            if hoverGoneSince == nil { hoverGoneSince = Date() }
            guard Date().timeIntervalSince(hoverGoneSince!) > 0.15 else { return }
        }
        hoverGoneSince = nil
        withAnimation(panelSpring) { motion.hovered = target }
    }

    private func targetFrame(on screen: NSScreen) -> NSRect {
        let size = hosting.fittingSize
        let f = screen.frame
        let top = screen.visibleFrame.maxY            // precis under menyraden, så att menyraden alltid syns
        let center = screen.auxiliaryTopLeftArea.map { f.minX + $0.width + (f.width - $0.width - (screen.auxiliaryTopRightArea?.width ?? 0)) / 2 } ?? f.midX
        var x = center - size.width / 2
        x = min(max(x, f.minX - Layout.side + 8), f.maxX - size.width + Layout.side - 8)
        return NSRect(x: x, y: top - size.height + Layout.top - 2, width: size.width, height: size.height)
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
        withAnimation(.spring(response: 0.3, dampingFraction: 1)) { motion.open = false; motion.hovered = nil }
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
