import SwiftUI

/// Ljust som iOS: frostat glas, vita kort, mjuka skuggor. Mörkt finns kvar som val.
struct Theme {
    var dark: Bool
    var tint: Color { dark ? Color.black.opacity(0.42) : Color(red: 0.97, green: 0.96, blue: 0.95).opacity(0.55) }
    var card: Color { dark ? Color.white.opacity(0.055) : Color.white.opacity(0.82) }
    var cardShadow: Color { dark ? Color.clear : Color(red: 0.35, green: 0.25, blue: 0.15).opacity(0.08) }
    var field: Color { dark ? Color.white.opacity(0.08) : Color(red: 0.46, green: 0.46, blue: 0.5).opacity(0.1) }
    var hover: Color { dark ? Color.white.opacity(0.07) : Color(red: 0.46, green: 0.46, blue: 0.5).opacity(0.08) }
    var text: Color { dark ? Color(white: 0.96) : Color(red: 0.11, green: 0.11, blue: 0.12) }
    var dim: Color { dark ? Color(white: 0.66) : Color(red: 0.24, green: 0.24, blue: 0.26).opacity(0.62) }
    var faint: Color { dark ? Color(white: 0.45) : Color(red: 0.24, green: 0.24, blue: 0.26).opacity(0.4) }
    var edge: Color { dark ? Color.white.opacity(0.09) : Color.white.opacity(0.9) }
    let accent = Color(red: 1.0, green: 0.58, blue: 0.0)          // iOS orange
    var unread: Color { Color(red: 0.0, green: 0.48, blue: 1.0) }  // iOS blå
}

let cardWidth: CGFloat = 256
let cardHeight: CGFloat = 272

/// Öppen eller stängd. Ändras med animation av PanelController.
final class Motion: ObservableObject {
    @Published var open = false
}

/// macOS egna genomskinliga bakgrund (som Kontrollcenter).
struct Blur: NSViewRepresentable {
    var dark: Bool
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = dark ? .hudWindow : .sidebar
        v.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    }
}

/// Fjädern som används överallt, så att allt rör sig likadant.
let panelSpring = Animation.spring(response: 0.46, dampingFraction: 0.84)

struct PanelView: View {
    @ObservedObject var store: Store
    @ObservedObject var motion: Motion
    var theme: Theme { Theme(dark: store.config.dark) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(store.enabledModules.enumerated()), id: \.element.id) { index, module in
                    ModuleCard(module: module, store: store, theme: theme)
                        .opacity(motion.open ? 1 : 0)
                        .offset(y: motion.open ? 0 : -12)
                        .animation(motion.open ? panelSpring.delay(0.06 + 0.045 * Double(index)) : .easeOut(duration: 0.12), value: motion.open)
                }
                if store.enabledModules.isEmpty {
                    Text("Inga delar är på. Tryck på reglageknappen för att välja vad panelen ska visa.")
                        .foregroundColor(theme.dim).frame(width: cardWidth * 2, height: 80)
                }
            }
        }
        .padding(16)
        .background(ZStack { Blur(dark: store.config.dark); theme.tint })
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(theme.edge, lineWidth: 0.75))
        .shadow(color: Color(red: 0.3, green: 0.2, blue: 0.1).opacity(store.config.dark ? 0.45 : 0.16), radius: 30, y: 18)
        .font(.system(size: 13))
        .scaleEffect(motion.open ? 1 : 0.9, anchor: .top)
        .opacity(motion.open ? 1 : 0)
        .blur(radius: motion.open ? 0 : 8)
        .padding(.horizontal, 44).padding(.bottom, 56).padding(.top, 6)   // plats för skuggan
        .fixedSize()
        .environment(\.colorScheme, store.config.dark ? .dark : .light)
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let next = nextUp {
                Circle().fill(theme.accent).frame(width: 6, height: 6)
                Text(next).foregroundColor(theme.text).fontWeight(.medium).lineLimit(1)
            } else if Updater.updatedRecently && !Updater.version.isEmpty {
                Image(systemName: "sparkles").foregroundColor(theme.faint)
                Text("Ny version: \(Updater.version)").foregroundColor(theme.faint).lineLimit(1)
            }
            Spacer(minLength: 40)
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(theme.dim)
            HeaderButton(symbol: "arrow.clockwise", help: "Hämta nytt", theme: theme) { Task { await store.refresh() } }
            HeaderButton(symbol: "slider.horizontal.3", help: "Inställningar och konton", theme: theme) { store.openSettings() }
            HeaderButton(symbol: "gearshape", help: "Ändra panelen med Claude", theme: theme) { LinkOpener.open(store.config.chatURL) }
        }
        .padding(.horizontal, 6).frame(height: 26)
    }

    /// Det viktigaste just nu: närmaste deadline i dag eller i morgon.
    private var nextUp: String? {
        guard let e = store.events.first else { return nil }
        let cal = Calendar.current
        if cal.isDateInToday(e.start) { return "I dag: \(e.title)" }
        if cal.isDateInTomorrow(e.start) { return "I morgon: \(e.title)" }
        return nil
    }
}

struct HeaderButton: View {
    var symbol: String
    var help: String
    var theme: Theme
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(hover ? theme.text : theme.dim)
                .frame(width: 26, height: 26)
                .background(Circle().fill(hover ? theme.hover : Color.clear))
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
    }
}

struct ModuleCard: View {
    var module: Module
    @ObservedObject var store: Store
    var theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: module.kind.symbol).font(.system(size: 12, weight: .semibold))
                Text(module.title).font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer()
            }
            .foregroundColor(theme.dim)

            if let problem = store.problems[module.kind] {
                Text(problem).foregroundColor(theme.faint).fixedSize(horizontal: false, vertical: true)
                if needsLogin {
                    Button { store.openSettings() } label: {
                        Text("Koppla").fontWeight(.medium).foregroundColor(theme.text)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(Capsule().fill(theme.field))
                    }.buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            } else {
                content
            }
        }
        .padding(16)
        .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(theme.card)
            .shadow(color: theme.cardShadow, radius: 10, y: 3))
    }

    /// Kontonamnet visas bara när mailen kommer från fler än ett konto.
    private var manyAccounts: Bool { Set(store.mail.map(\.account)).count > 1 }

    private var needsLogin: Bool { module.kind == .tasks || module.kind == .slack || module.kind == .calendar }

    @ViewBuilder private var content: some View {
        switch module.kind {
        case .mail: mail
        case .slack: slack
        case .calendar: calendar
        case .tasks: TasksCard(store: store, theme: theme)
        case .links: links
        case .note: note
        }
    }

    private var mail: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(store.mail) { m in
                Row(theme: theme) { store.open(m) } content: {
                    HStack(spacing: 6) {
                        if m.unread { Circle().fill(theme.unread).frame(width: 6, height: 6) }
                        Text(m.sender).fontWeight(.semibold).foregroundColor(theme.text).lineLimit(1)
                        Spacer(minLength: 4)
                        if manyAccounts && !m.account.isEmpty {
                            Text(m.account).font(.system(size: 10, weight: .medium)).foregroundColor(theme.dim).lineLimit(1)
                                .padding(.horizontal, 6).padding(.vertical, 1.5)
                                .background(Capsule().fill(theme.field))
                        }
                        Text(short(m.date)).font(.system(size: 11)).foregroundColor(theme.faint)
                    }
                    Text(m.subject).foregroundColor(theme.dim).lineLimit(1)
                }
            }
            empty(store.mail.isEmpty, "Inga mail")
            Spacer(minLength: 0)
        }
    }

    private var slack: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(store.slack) { s in
                Row(theme: theme) { store.open(s) } content: {
                    HStack {
                        Text("\(s.who) · \(s.place)").fontWeight(.semibold).foregroundColor(theme.text).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(short(s.date)).font(.system(size: 11)).foregroundColor(theme.faint)
                    }
                    Text(s.text).foregroundColor(theme.dim).lineLimit(1)
                }
            }
            empty(store.slack.isEmpty, "Inget nytt i Slack")
            Spacer(minLength: 0)
        }
    }

    private var calendar: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(store.events) { e in
                Row(theme: theme) { store.open(e) } content: {
                    HStack(spacing: 11) {
                        DayBadge(date: e.start, theme: theme, hot: Calendar.current.isDateInToday(e.start) || Calendar.current.isDateInTomorrow(e.start))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(e.title).fontWeight(.medium).foregroundColor(theme.text).lineLimit(1)
                            Text(detail(e)).font(.system(size: 11.5)).foregroundColor(theme.faint).lineLimit(1)
                        }
                    }
                }
            }
            empty(store.events.isEmpty, "Inget i kalendern")
            Spacer(minLength: 0)
        }
    }

    private var links: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(store.config.links) { l in
                Button { LinkOpener.open(l.target) } label: {
                    Text(l.name).lineLimit(1).foregroundColor(theme.text)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(theme.field).clipShape(RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain)
            }
        }
    }

    private var note: some View {
        TextEditor(text: $store.config.note)
            .font(.system(size: 13))
            .foregroundColor(theme.text)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
    }

    @ViewBuilder private func empty(_ isEmpty: Bool, _ text: String) -> some View {
        if isEmpty { Text(text).foregroundColor(theme.faint) }
    }

    private func detail(_ e: EventItem) -> String {
        var parts: [String] = []
        if !e.allDay { parts.append(e.start.formatted(date: .omitted, time: .shortened)) }
        if !e.location.isEmpty { parts.append(e.location) }
        return parts.isEmpty ? relativeDay(e.start) : parts.joined(separator: " · ")
    }
}

struct TasksCard: View {
    @ObservedObject var store: Store
    var theme: Theme
    @State private var newTask = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(store.tasks) { t in
                        HStack(spacing: 10) {
                            Button { store.complete(t) } label: {
                                Circle().strokeBorder(theme.faint, lineWidth: 1.4).frame(width: 17, height: 17)
                                    .contentShape(Circle())
                            }.buttonStyle(.plain).help("Bocka av")
                            Text(t.title).foregroundColor(theme.text).lineLimit(1)
                            Spacer(minLength: 4)
                            if let due = t.due {
                                Text(dueText(due)).font(.system(size: 11)).foregroundColor(isSoon(due) ? theme.accent : theme.faint)
                            }
                        }
                        .padding(.vertical, 5)
                    }
                    if store.tasks.isEmpty { Text("Allt är klart").foregroundColor(theme.faint) }
                }
            }
            HStack(spacing: 7) {
                Image(systemName: "plus").foregroundColor(theme.faint)
                TextField("Lägg till", text: $newTask)
                    .textFieldStyle(.plain).foregroundColor(theme.text)
                    .onSubmit { store.addTask(newTask); newTask = "" }
            }
            .padding(.horizontal, 12).frame(height: 32)
            .background(theme.field).clipShape(Capsule())
            .padding(.top, 8)
        }
    }

    /// Google sparar bara datumet (midnatt UTC), så det läses i UTC.
    private func dueDay(_ d: Date) -> Date {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let c = utc.dateComponents([.year, .month, .day], from: d)
        return Calendar.current.date(from: c) ?? d
    }
    private func dueText(_ d: Date) -> String { relativeDay(dueDay(d)) }
    private func isSoon(_ d: Date) -> Bool {
        let day = dueDay(d)
        return day < Calendar.current.date(byAdding: .day, value: 2, to: Calendar.current.startOfDay(for: Date()))!
    }
}

/// En klickbar rad med tunn linje mellan raderna.
struct Row<Content: View>: View {
    var theme: Theme
    var action: () -> Void
    @ViewBuilder var content: Content
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) { content }
                .padding(.vertical, 7).padding(.horizontal, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hover ? theme.hover : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, -6)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
    }
}

struct DayBadge: View {
    var date: Date
    var theme: Theme
    var hot: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased()).font(.system(size: 9, weight: .semibold))
            Text(date.formatted(.dateTime.day())).font(.system(size: 17, weight: .semibold))
        }
        .foregroundColor(hot ? .white : theme.text)
        .frame(width: 40, height: 40)
        .background(hot ? theme.accent : theme.field)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

func short(_ date: Date?) -> String {
    guard let date else { return "" }
    if Calendar.current.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
    return relativeDay(date)
}

func relativeDay(_ date: Date) -> String {
    let cal = Calendar.current
    if cal.isDateInToday(date) { return "I dag" }
    if cal.isDateInTomorrow(date) { return "I morgon" }
    if cal.isDateInYesterday(date) { return "I går" }
    return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
}
