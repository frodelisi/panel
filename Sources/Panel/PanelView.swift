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

let cardWidth: CGFloat = 248
let cardHeight: CGFloat = 272

/// Öppen eller stängd. Ändras med animation av PanelController.
final class Motion: ObservableObject {
    @Published var open = false
    @Published var hovered: Int?          // kortet som är utfällt
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
    var width: CGFloat = cardWidth
    var height: CGFloat = cardHeight
    var plain = false        // utan egen bakgrund (LiveCard ritar den)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !module.kind.isSmall || plain { cardHeader }

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
        .padding(plain ? 20 : 16)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(plain ? Color.clear : theme.card)
            .shadow(color: plain ? .clear : theme.cardShadow, radius: 10, y: 3))
    }

    private var cardHeader: some View {
        HStack(spacing: 7) {
            Image(systemName: module.kind.symbol).font(.system(size: 12, weight: .semibold))
            Text(module.title).font(.system(size: 13, weight: .semibold, design: .rounded))
            if dashboardLink != nil { Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .bold)).opacity(0.6) }
            Spacer()
        }
        .foregroundColor(theme.dim)
        .contentShape(Rectangle())
        .onTapGesture { if let url = dashboardLink { NSWorkspace.shared.open(url) } }
        .help(dashboardLink == nil ? "" : "Öppna i dashboarden")
    }

    /// Klick på kortets rubrik öppnar dashboarden på rätt sida (om en adress är inställd).
    private var dashboardLink: URL? {
        let base = store.config.dashboardURL.trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty, let page = module.kind.dashboardPage else { return nil }
        return URL(string: (base.hasPrefix("http") ? base : "http://" + base) + "/#" + page)
    }

    /// Kontonamnet visas bara när mailen kommer från fler än ett konto.
    private var manyAccounts: Bool { Set(store.mail.map(\.account)).count > 1 }

    private var needsLogin: Bool { [.mail, .tasks, .slack, .calendar, .inbox, .economy].contains(module.kind) }

    @ViewBuilder private var content: some View {
        switch module.kind {
        case .mail: mail
        case .slack: slack
        case .calendar: calendar
        case .tasks: TasksCard(store: store, theme: theme)
        case .links: links
        case .note: note
        case .weather: weather
        case .music: music
        case .inbox: inbox
        case .economy: economy
        }
    }

    private var mail: some View {
        ScrollView(showsIndicators: false) {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(store.invites) { invite in
                InviteRow(invite: invite, theme: theme, store: store)
            }
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
            empty(store.mail.isEmpty && store.invites.isEmpty, "Inga viktiga mail 🎉")
        }
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
            empty(store.slack.isEmpty, store.config.slackUnreadOnly ? "Inget oläst i Slack 🎉" : "Inget nytt i Slack")
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

    /// Viktigt: inbjudningar, viktiga mail och olästa Slack i en lista.
    private var inbox: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(store.invites) { InviteRow(invite: $0, theme: theme, store: store) }
                ForEach(store.mail) { m in
                    Row(theme: theme) { store.open(m) } content: {
                        HStack(spacing: 6) {
                            if m.unread { Circle().fill(theme.unread).frame(width: 6, height: 6) }
                            Text(m.sender).fontWeight(.semibold).foregroundColor(theme.text).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(m.account.isEmpty ? "mail" : m.account).font(.system(size: 10, weight: .medium)).foregroundColor(theme.faint)
                        }
                        Text(m.subject).foregroundColor(theme.dim).lineLimit(1)
                    }
                }
                ForEach(store.slack) { m in
                    Row(theme: theme) { store.open(m) } content: {
                        HStack {
                            Text("\(m.who) · \(m.place)").fontWeight(.semibold).foregroundColor(theme.text).lineLimit(1)
                            Spacer(minLength: 4)
                            Text("slack").font(.system(size: 10, weight: .medium)).foregroundColor(theme.faint)
                        }
                        Text(m.text).foregroundColor(theme.dim).lineLimit(1)
                    }
                }
                if store.invites.isEmpty && store.mail.isEmpty && store.slack.isEmpty {
                    Text("Inget viktigt just nu 🎉").foregroundColor(theme.faint)
                }
            }
        }
    }

    @ViewBuilder private var economy: some View {
        if let e = store.economy {
            Text(e.pott == nil ? "–" : kronor(e.pott)).font(.system(size: 34, weight: .heavy, design: .rounded)).foregroundColor(theme.text)
            Text(e.pott == nil ? "Fyll i lönen i dashboarden" : "till potten i \(e.month)").font(.system(size: 12.5)).foregroundColor(theme.dim)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(e.goals.prefix(3), id: \.self) { g in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(g.name).fontWeight(.semibold).foregroundColor(theme.text)
                            Spacer()
                            Text("\(kronor(g.saved)) / \(kronor(g.target))").font(.system(size: 11)).foregroundColor(theme.faint)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(theme.field)
                                Capsule().fill(Color(red: 0.43, green: 0.25, blue: 0.88))
                                    .frame(width: geo.size.width * CGFloat(min(1, g.target.map { $0 > 0 ? g.saved / $0 : 0 } ?? 0)))
                            }
                        }
                        .frame(height: 6)
                    }
                }
            }
            .padding(.top, 6)
            if e.subscriptions > 0 {
                Text("Prenumerationer \(kronor(e.subscriptions))/mån").font(.system(size: 11.5)).foregroundColor(theme.faint)
            }
        } else {
            Text("Ekonomin hämtas från dashboarden på Mac minin.").foregroundColor(theme.faint)
        }
    }

    @ViewBuilder private var weather: some View {
        if let w = store.weather {
            HStack(alignment: .center, spacing: 12) {
                WeatherIcon(symbol: w.symbol, size: 30, theme: theme)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(w.temp)°").font(.system(size: 22, weight: .semibold, design: .rounded)).foregroundColor(theme.text)
                    Text("\(w.text) · \(w.high)° / \(w.low)°").font(.system(size: 11.5)).foregroundColor(theme.dim).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 0) {
                ForEach(w.hours, id: \.self) { h in
                    VStack(spacing: 2) {
                        Text(h.hour).font(.system(size: 10.5, weight: .medium)).foregroundColor(theme.faint)
                        WeatherIcon(symbol: h.symbol, size: 12, theme: theme)
                        Text("\(h.temp)°").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundColor(theme.text)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        } else {
            Text("Hämtar väder…").foregroundColor(theme.faint)
        }
    }

    @ViewBuilder private var music: some View {
        if let m = store.music {
            HStack(spacing: 11) {
                AsyncImage(url: m.artwork) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    ZStack { theme.field; Image(systemName: "music.note").foregroundColor(theme.faint) }
                }
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(m.title).fontWeight(.semibold).foregroundColor(theme.text).lineLimit(1)
                    Text(m.artist).font(.system(size: 12)).foregroundColor(theme.dim).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 26) {
                Spacer()
                MusicButton(symbol: "backward.fill", theme: theme) { store.musicCommand("previous track") }
                MusicButton(symbol: m.playing ? "pause.fill" : "play.fill", theme: theme, big: true) { store.musicCommand("playpause") }
                MusicButton(symbol: "forward.fill", theme: theme) { store.musicCommand("next track") }
                Spacer()
            }
        } else {
            Text("Ingen musik spelas").foregroundColor(theme.faint)
            Button { MusicSource.openSpotify() } label: {
                Text("Öppna Spotify").fontWeight(.medium).foregroundColor(theme.text)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Capsule().fill(theme.field))
            }.buttonStyle(.plain)
        }
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

struct MusicButton: View {
    var symbol: String
    var theme: Theme
    var big = false
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: big ? 18 : 13, weight: .semibold))
                .foregroundColor(theme.text)
                .frame(width: big ? 34 : 26, height: big ? 34 : 26)
                .background(Circle().fill(hover ? theme.hover : Color.clear))
                .scaleEffect(hover ? 1.06 : 1)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
    }
}

/// En kalenderinbjudan med svarsknappar.
struct InviteRow: View {
    var invite: Invite
    var theme: Theme
    @ObservedObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Inbjudan").font(.system(size: 10, weight: .semibold)).foregroundColor(.white)
                    .padding(.horizontal, 6).padding(.vertical, 1.5)
                    .background(Capsule().fill(theme.accent))
                Text(invite.title).fontWeight(.semibold).foregroundColor(theme.text).lineLimit(1)
            }
            Text(when).font(.system(size: 11.5)).foregroundColor(theme.dim).lineLimit(1)
            HStack(spacing: 6) {
                answer("Ja", "accepted", color: Color(red: 0.2, green: 0.78, blue: 0.35))
                answer("Kanske", "tentative", color: theme.dim)
                answer("Nej", "declined", color: Color(red: 1, green: 0.27, blue: 0.23))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.accent.opacity(0.08)))
        .padding(.bottom, 8)
    }

    private var when: String {
        var parts: [String] = []
        if let start = invite.start {
            parts.append(relativeDay(start))
            if !invite.allDay { parts.append(start.formatted(date: .omitted, time: .shortened)) }
        }
        if !invite.organizer.isEmpty { parts.append(invite.organizer) }
        return parts.joined(separator: " · ")
    }

    private func answer(_ label: String, _ status: String, color: Color) -> some View {
        Button { withAnimation(panelSpring) { store.respond(invite, status) } } label: {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundColor(color)
                .frame(maxWidth: .infinity).padding(.vertical, 5)
                .background(Capsule().fill(theme.card))
        }
        .buttonStyle(.plain)
    }
}

/// Väderikon som syns på ljus bakgrund: sol och måne i färg, moln grå (de är annars vita).
struct WeatherIcon: View {
    var symbol: String
    var size: CGFloat
    var theme: Theme

    var body: some View {
        let sunny = symbol.contains("sun")
        let moon = symbol.contains("moon")
        let wet = symbol.contains("rain") || symbol.contains("drizzle") || symbol.contains("bolt") || symbol.contains("snow")
        Image(systemName: symbol)
            .symbolRenderingMode(.palette)
            .foregroundStyle(
                // Rena sol- och månsymboler har bara ett lager: färga det direkt.
                symbol.hasPrefix("sun") ? Color(red: 1, green: 0.72, blue: 0.1)
                    : symbol.hasPrefix("moon") ? Color(red: 0.55, green: 0.6, blue: 0.9)
                    : (theme.dark ? Color.white.opacity(0.85) : Color(white: 0.55)),
                sunny ? Color(red: 1, green: 0.72, blue: 0.1) : moon ? Color(red: 0.55, green: 0.6, blue: 0.9)
                    : wet ? Color(red: 0.2, green: 0.55, blue: 1) : (theme.dark ? Color.white.opacity(0.6) : Color(white: 0.7)))
            .font(.system(size: size))
    }
}
