import SwiftUI

/// Mått för den nya designen. PanelController använder samma mått för att veta vilket kort musen är över.
enum Layout {
    static let cw: CGFloat = 196          // smalt kort
    static let ch: CGFloat = 146
    static let fw: CGFloat = 440          // utfällt kort
    static let gap: CGFloat = 14
    static let side: CGFloat = 44         // luft runt panelen för skuggan
    static let top: CGFloat = 6
    static let bottom: CGFloat = 56
    static let pad: CGFloat = 16          // panelens inre marginal
    static let header: CGFloat = 30       // Live-raden
    static let headerGap: CGFloat = 12

    static func rowWidth(_ n: Int) -> CGFloat { CGFloat(n) * cw + CGFloat(max(0, n - 1)) * gap }
    static func contentWidth(_ n: Int) -> CGFloat { max(rowWidth(n), fw, 620) }
    static var rowTop: CGFloat { top + pad + header + headerGap }
    static var glassHeight: CGFloat { pad + header + headerGap + ch + pad }

    static func fullHeight(_ kind: ModuleKind) -> CGFloat {
        switch kind {
        case .music: return 250
        case .weather: return 240
        case .tasks: return 330
        case .economy: return 300
        default: return 330
        }
    }
    static let maxFull: CGFloat = 330

    /// Kortets vänsterkant inom raden. Utfällt kort centreras över sin plats men stannar inom panelen.
    static func x(_ i: Int, open: Bool, n: Int) -> CGFloat {
        let left = CGFloat(i) * (cw + gap)
        guard open else { return left }
        let centered = left + cw / 2 - fw / 2
        return min(max(centered, 0), max(0, contentWidth(n) - fw))
    }

    static func windowSize(_ n: Int) -> CGSize {
        CGSize(width: side * 2 + pad * 2 + contentWidth(n),
               height: rowTop + max(ch + pad, maxFull) + bottom)
    }
}

/// Färgen för varje sorts kort (ikon och liten rubrik).
func kindColor(_ kind: ModuleKind) -> Color {
    switch kind {
    case .calendar: return Color(red: 0.04, green: 0.44, blue: 0.91)
    case .inbox, .mail: return Color(red: 0.83, green: 0.19, blue: 0.16)
    case .slack: return Color(red: 0.42, green: 0.18, blue: 0.43)
    case .music: return Color(red: 0.88, green: 0.21, blue: 0.35)
    case .tasks: return Color(red: 1.0, green: 0.71, blue: 0.28)
    case .economy: return Color(red: 0.43, green: 0.25, blue: 0.88)
    case .weather: return Color(red: 0.04, green: 0.53, blue: 0.59)
    case .links, .note: return Color(white: 0.45)
    }
}

struct PanelView: View {
    @ObservedObject var store: Store
    @ObservedObject var motion: Motion
    var theme: Theme { Theme(dark: store.config.dark) }

    var body: some View {
        let modules = store.enabledModules
        let n = modules.count
        let width = Layout.contentWidth(n)
        ZStack(alignment: .topLeading) {
            // Glaset bakom Live-raden och korten
            ZStack { Blur(dark: store.config.dark); theme.tint }
                .frame(width: width + Layout.pad * 2, height: Layout.glassHeight)
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(theme.edge, lineWidth: 0.75))
                .shadow(color: Color(red: 0.3, green: 0.2, blue: 0.1).opacity(store.config.dark ? 0.45 : 0.16), radius: 30, y: 18)

            VStack(alignment: .leading, spacing: Layout.headerGap) {
                liveRow.frame(width: width, height: Layout.header)
                ZStack(alignment: .topLeading) {
                    ForEach(Array(modules.enumerated()), id: \.element.id) { index, module in
                        LiveCard(module: module, index: index, count: n, store: store, motion: motion, theme: theme)
                            .opacity(motion.open ? 1 : 0)
                            .offset(y: motion.open ? 0 : -10)
                            .animation(motion.open ? panelSpring.delay(0.05 + 0.04 * Double(index)) : .easeOut(duration: 0.12), value: motion.open)
                    }
                    if modules.isEmpty {
                        Text("Inga kort är på. Tryck på reglageknappen för att välja.").foregroundColor(theme.dim)
                    }
                }
                .frame(width: width, height: Layout.ch, alignment: .topLeading)
            }
            .padding(Layout.pad)
        }
        .font(.system(size: 13))
        .scaleEffect(motion.open ? 1 : 0.92, anchor: .top)
        .opacity(motion.open ? 1 : 0)
        .blur(radius: motion.open ? 0 : 8)
        .padding(.horizontal, Layout.side)
        .padding(.top, Layout.top)
        .frame(width: Layout.windowSize(n).width, height: Layout.windowSize(n).height, alignment: .topLeading)
        .environment(\.colorScheme, store.config.dark ? .dark : .light)
    }

    /// "● Live  uppdaterad för 1 min sedan · onsdag 25 november   1° Mulet          ↻ ⚙︎"
    private var liveRow: some View {
        HStack(spacing: 10) {
            Circle().fill(Color(red: 0.13, green: 0.77, blue: 0.37)).frame(width: 8, height: 8)
                .background(Circle().fill(Color(red: 0.13, green: 0.77, blue: 0.37).opacity(0.18)).frame(width: 16, height: 16))
            Text("Live").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundColor(theme.text)
            Text("\(updatedText) · \(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))")
                .foregroundColor(theme.dim).lineLimit(1)
            if store.config.weatherInHeader, let w = store.weather {
                HStack(spacing: 4) {
                    WeatherIcon(symbol: w.symbol, size: 12, theme: theme)
                    Text("\(w.temp)° \(w.text)").fontWeight(.semibold)
                }
                .foregroundColor(kindColor(.weather))
                .padding(.leading, 6)
            }
            Spacer(minLength: 20)
            if Updater.updatedRecently && !Updater.version.isEmpty {
                Image(systemName: "sparkles").foregroundColor(theme.faint).help("Ny version: \(Updater.version)")
            }
            HeaderButton(symbol: "arrow.clockwise", help: "Hämta nytt", theme: theme) { Task { await store.refresh() } }
            HeaderButton(symbol: "slider.horizontal.3", help: "Inställningar och konton", theme: theme) { store.openSettings() }
            HeaderButton(symbol: "gearshape", help: "Ändra panelen med Claude", theme: theme) { LinkOpener.open(store.config.chatURL) }
        }
    }

    private var updatedText: String {
        let s = Date().timeIntervalSince(store.lastRefresh)
        if s < 60 { return "uppdaterad nyss" }
        if s < 3600 { return "uppdaterad för \(Int(s / 60)) min sedan" }
        return "uppdaterad \(store.lastRefresh.formatted(date: .omitted, time: .shortened))"
    }
}

/// Ett kort i raden. Smalt med stor siffra; fälls ut när musen är över det.
struct LiveCard: View {
    var module: Module
    var index: Int
    var count: Int
    @ObservedObject var store: Store
    @ObservedObject var motion: Motion
    var theme: Theme

    var body: some View {
        let open = motion.hovered == index
        let other = motion.hovered != nil && !open
        let dark = module.kind == .tasks                 // det mörka hjältekortet
        let t = dark ? Theme(dark: true) : theme
        let w = open ? Layout.fw : Layout.cw
        let h = open ? Layout.fullHeight(module.kind) : Layout.ch

        ZStack(alignment: .topLeading) {
            CompactCard(module: module, store: store, theme: t)
                .frame(width: Layout.cw, height: Layout.ch, alignment: .topLeading)
                .opacity(open ? 0 : 1)
            if open {
                ModuleCard(module: module, store: store, theme: t, width: Layout.fw, height: h, plain: true)
                    .transition(.opacity.combined(with: .offset(y: 8)))
            }
        }
        .frame(width: w, height: h, alignment: .topLeading)
        .background(background(dark: dark))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(dark ? Color.white.opacity(0.08) : Color.white, lineWidth: 0.5))
        .shadow(color: Color(red: 0.24, green: 0.16, blue: 0.08).opacity(open ? 0.32 : 0.14), radius: open ? 30 : 10, y: open ? 22 : 6)
        .scaleEffect(other ? 0.96 : 1, anchor: .top)
        .opacity(other ? 0.55 : 1)
        .blur(radius: other ? 1.5 : 0)
        .offset(x: Layout.x(index, open: open, n: count))
        .zIndex(open ? 10 : 0)
    }

    @ViewBuilder private func background(dark: Bool) -> some View {
        if dark {
            LinearGradient(colors: [Color(red: 0.17, green: 0.15, blue: 0.14), Color(red: 0.08, green: 0.07, blue: 0.06)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            ZStack {
                Color.white.opacity(store.config.dark ? 0.06 : 0.88)
                kindColor(module.kind).opacity(store.config.dark ? 0.08 : 0.05)
            }
        }
    }
}

/// Det smala kortets innehåll: liten färgad rubrik, en stor siffra och en rad under.
struct CompactCard: View {
    var module: Module
    @ObservedObject var store: Store
    var theme: Theme

    var body: some View {
        Group {
            switch module.kind {
            case .tasks: tasks
            case .music: music
            default:
                VStack(alignment: .leading, spacing: 0) {
                    label
                    Text(big).font(.system(size: 32, weight: .heavy, design: .rounded)).foregroundColor(theme.text)
                        .lineLimit(1).minimumScaleFactor(0.6).padding(.top, 8)
                    Text(sub).font(.system(size: 12.5)).foregroundColor(theme.dim).lineLimit(1).padding(.top, 2)
                    Spacer(minLength: 0)
                    segments
                }
            }
        }
        .padding(16)
    }

    private var label: some View {
        HStack(spacing: 6) {
            Image(systemName: module.kind.symbol).font(.system(size: 11, weight: .bold))
            Text(module.title).font(.system(size: 12, weight: .bold, design: .rounded))
        }
        .foregroundColor(kindColor(module.kind))
    }

    /// Den stora siffran.
    private var big: String {
        if store.problems[module.kind] != nil { return "–" }
        switch module.kind {
        case .calendar:
            guard let e = store.events.first else { return "Inget" }
            if Calendar.current.isDateInToday(e.start) { return e.allDay ? "I dag" : e.start.formatted(date: .omitted, time: .shortened) }
            if Calendar.current.isDateInTomorrow(e.start) { return "I morgon" }
            return e.start.formatted(.dateTime.weekday(.abbreviated).day())
        case .inbox: return "\(store.invites.count + store.mail.count + store.slack.count)"
        case .mail: return "\(store.mail.count)"
        case .slack: return "\(store.slack.count)"
        case .economy:
            guard let e = store.economy else { return "–" }
            if let p = e.pott { return kronor(p) }
            if let g = e.goals.first { return kronor(g.saved) }
            return "–"
        case .weather: return store.weather.map { "\($0.temp)°" } ?? "–"
        case .links: return "\(store.config.links.count)"
        case .note: return store.config.note.isEmpty ? "Tom" : "✎"
        case .tasks, .music: return ""
        }
    }

    /// Raden under siffran.
    private var sub: String {
        if let problem = store.problems[module.kind] { return problem }
        switch module.kind {
        case .calendar: return store.events.first?.title ?? "Inget i kalendern"
        case .inbox:
            var parts: [String] = []
            if !store.invites.isEmpty { parts.append("\(store.invites.count) inbjudan") }
            if !store.mail.isEmpty { parts.append("\(store.mail.count) mail") }
            if !store.slack.isEmpty { parts.append("\(store.slack.count) Slack") }
            return parts.isEmpty ? "Inget viktigt" : parts.joined(separator: " · ")
        case .mail: return store.mail.first?.sender ?? "Inga viktiga mail"
        case .slack: return store.slack.first.map { "\($0.who) · \($0.place)" } ?? "Inget oläst"
        case .economy:
            guard let e = store.economy else { return "Koppla dashboarden" }
            if e.pott != nil { return "till potten i \(e.month)" }
            if let g = e.goals.first { return "\(g.name) av \(kronor(g.target))" }
            return "Fyll i dashboarden"
        case .weather: return store.weather.map { "\($0.text) · \($0.high)° / \($0.low)°" } ?? ""
        case .links: return "genvägar"
        case .note: return store.config.note.split(separator: "\n").first.map(String.init) ?? "Skriv något"
        case .tasks, .music: return ""
        }
    }

    /// Små staplar längst ner, som på en live-tavla.
    @ViewBuilder private var segments: some View {
        let colors: [Color] = {
            switch module.kind {
            case .calendar: return store.events.prefix(5).map { Calendar.current.isDateInToday($0.start) ? kindColor(.calendar) : theme.field }
            case .inbox:
                return Array((Array(repeating: Color(red: 0.94, green: 0.54, blue: 0), count: store.invites.count)
                    + Array(repeating: Color(red: 0.92, green: 0.26, blue: 0.21), count: store.mail.count)
                    + Array(repeating: Color(red: 0.29, green: 0.08, blue: 0.29), count: store.slack.count)).prefix(8))
            case .economy:
                guard let g = store.economy?.goals.first, let t = g.target, t > 0 else { return [] }
                let filled = Int((g.saved / t * 5).rounded(.down))
                return (0..<5).map { $0 < filled ? kindColor(.economy) : theme.field }
            default: return []
            }
        }()
        if !colors.isEmpty {
            HStack(spacing: 3) {
                ForEach(colors.indices, id: \.self) { i in Capsule().fill(colors[i]).frame(height: 5) }
            }
        }
    }

    /// Mörka hjältekortet: ring med dagens framsteg.
    private var tasks: some View {
        let left = store.tasks.count
        let done = store.doneToday
        let pct = (done + left) > 0 ? Double(done) / Double(done + min(left, 5)) : 0
        return HStack(spacing: 12) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.12), lineWidth: 7)
                Circle().trim(from: 0, to: pct).stroke(kindColor(.tasks), style: StrokeStyle(lineWidth: 7, lineCap: .round)).rotationEffect(.degrees(-90))
                Text("\(Int(pct * 100))%").font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundColor(.white)
            }
            .frame(width: 62, height: 62)
            VStack(alignment: .leading, spacing: 3) {
                Text("Att göra").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundColor(Color.white.opacity(0.6))
                Text("\(left) kvar").font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundColor(.white)
                Text(done == 0 ? "inget klart i dag" : "\(done) klara i dag").font(.system(size: 12)).foregroundColor(Color.white.opacity(0.6))
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }

    /// Musiken i mitten: omslag, låt och artist.
    private var music: some View {
        HStack(spacing: 12) {
            if let m = store.music {
                AsyncImage(url: m.artwork) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: {
                    LinearGradient(colors: [Color(red: 0.96, green: 0.64, blue: 0.48), Color(red: 0.61, green: 0.43, blue: 0.94)], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    label
                    Text(m.title).font(.system(size: 15, weight: .bold)).foregroundColor(theme.text).lineLimit(1)
                    Text(m.artist).font(.system(size: 12)).foregroundColor(theme.dim).lineLimit(1)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    label
                    Text("Ingen musik").font(.system(size: 17, weight: .bold)).foregroundColor(theme.text)
                    Text("Håll musen här för att starta").font(.system(size: 12)).foregroundColor(theme.dim)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }
}
