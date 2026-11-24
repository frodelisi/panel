import SwiftUI

struct Theme {
    var dark: Bool
    var panel: Color { dark ? Color(white: 0.045) : Color(white: 0.97) }
    var card: Color { dark ? Color(white: 0.095) : Color.white }
    var field: Color { dark ? Color(white: 0.14) : Color(white: 0.93) }
    var text: Color { dark ? Color(white: 0.95) : Color(white: 0.1) }
    var dim: Color { dark ? Color(white: 0.68) : Color(white: 0.38) }
    var faint: Color { dark ? Color(white: 0.42) : Color(white: 0.6) }
    var line: Color { dark ? Color(white: 0.16) : Color(white: 0.9) }
    let accent = Color(red: 1.0, green: 0.62, blue: 0.35)
    let unread = Color(red: 0.04, green: 0.52, blue: 1.0)
}

let cardWidth: CGFloat = 252
let cardHeight: CGFloat = 268

struct PanelView: View {
    @ObservedObject var store: Store
    var theme: Theme { Theme(dark: store.config.dark) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            HStack(alignment: .top, spacing: 12) {
                ForEach(store.enabledModules) { module in
                    ModuleCard(module: module, store: store, theme: theme)
                }
                if store.enabledModules.isEmpty {
                    Text("Inga delar är på. Tryck på kugghjulet för att välja vad panelen ska visa.")
                        .foregroundColor(theme.dim).frame(width: cardWidth * 2, height: 80)
                }
            }
        }
        .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 18)
        .background(theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(theme.line, lineWidth: 1))
        .font(.system(size: 13))
        .fixedSize()
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let next = nextUp {
                Circle().fill(theme.accent).frame(width: 7, height: 7)
                Text(next).foregroundColor(theme.text).fontWeight(.medium)
            }
            if nextUp == nil && Updater.updatedRecently && !Updater.version.isEmpty {
                Image(systemName: "sparkles").foregroundColor(theme.faint)
                Text("Ny version: \(Updater.version)").foregroundColor(theme.faint).lineLimit(1)
            }
            Spacer(minLength: 40)
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()))
                .foregroundColor(theme.dim)
            Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain).foregroundColor(theme.dim).help("Hämta nytt")
            Button { store.openSettings() } label: { Image(systemName: "slider.horizontal.3") }
                .buttonStyle(.plain).foregroundColor(theme.dim).help("Inställningar och konton")
            Button { LinkOpener.open(store.config.chatURL) } label: { Image(systemName: "gearshape") }
                .buttonStyle(.plain).foregroundColor(theme.dim).help("Ändra panelen med Claude")
        }
        .padding(.horizontal, 6).frame(height: 28)
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

struct ModuleCard: View {
    var module: Module
    @ObservedObject var store: Store
    var theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: module.kind.symbol)
                Text(module.title.uppercased()).kerning(0.8)
                Spacer()
            }
            .font(.system(size: 11.5, weight: .semibold)).foregroundColor(theme.dim)

            if let problem = store.problems[module.kind] {
                Text(problem).foregroundColor(theme.faint).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            } else {
                content
            }
        }
        .padding(15)
        .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

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
                                Circle().stroke(theme.faint, lineWidth: 1.5).frame(width: 16, height: 16)
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
                .background(hover ? theme.field : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, -6)
        .onHover { hover = $0 }
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
        .foregroundColor(hot ? Color(white: 0.08) : theme.text)
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
