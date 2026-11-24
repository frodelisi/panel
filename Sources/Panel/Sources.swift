import AppKit
import EventKit
import Foundation

// MARK: - Mail (läses från Mail-appen)

struct MailItem: Identifiable, Hashable {
    var id: String          // Message-ID, används för att öppna mailet i Mail
    var sender: String
    var subject: String
    var unread: Bool
    var date: Date?
}

enum MailSource {
    private static let queue = DispatchQueue(label: "panel.mail")

    static func fetch(count: Int) async throws -> [MailItem] {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                let script = """
                tell application "Mail"
                    set out to ""
                    set n to count of messages of inbox
                    if n > \(max(1, count) + 4) then set n to \(max(1, count) + 4)
                    repeat with i from 1 to n
                        set m to message i of inbox
                        set d to (date received of m) as «class isot» as string
                        set out to out & (message id of m) & tab & (sender of m) & tab & (subject of m) & tab & (read status of m) & tab & d & linefeed
                    end repeat
                    return out
                end tell
                """
                var error: NSDictionary?
                guard let result = NSAppleScript(source: script)?.executeAndReturnError(&error) else {
                    let message = (error?[NSAppleScript.errorMessage] as? String) ?? "Kunde inte läsa Mail"
                    cont.resume(throwing: PanelError(message))
                    return
                }
                let parser = ISO8601DateFormatter()
                parser.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime, .withDashSeparatorInDate]
                parser.timeZone = .current
                let items: [MailItem] = (result.stringValue ?? "").split(separator: "\n").compactMap { line in
                    let f = line.components(separatedBy: "\t")
                    guard f.count >= 5 else { return nil }
                    return MailItem(id: f[0], sender: cleanSender(f[1]), subject: f[2], unread: f[3] == "false", date: parser.date(from: f[4]))
                }
                let newest = items.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
                cont.resume(returning: Array(newest.prefix(max(1, count))))
            }
        }
    }

    /// "Molly Andersson <molly@…>" → "Molly Andersson"
    static func cleanSender(_ s: String) -> String {
        if let i = s.firstIndex(of: "<") {
            let name = s[..<i].trimmingCharacters(in: CharacterSet(charactersIn: " \""))
            if !name.isEmpty { return name }
        }
        return s.trimmingCharacters(in: CharacterSet(charactersIn: "<> "))
    }

    static func open(_ item: MailItem) {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "<>")
        let id = item.id.addingPercentEncoding(withAllowedCharacters: allowed) ?? item.id
        if let url = URL(string: "message://%3C\(id)%3E") { NSWorkspace.shared.open(url) }
    }
}

// MARK: - Kalender (allt som finns i macOS Kalender, även Google-kalendrar)

struct EventItem: Identifiable, Hashable {
    var id: String
    var title: String
    var start: Date
    var allDay: Bool
    var location: String
}

enum CalendarSource {
    static let store = EKEventStore()

    static func requestAccess() async -> Bool {
        if #available(macOS 14.0, *) {
            return (try? await store.requestFullAccessToEvents()) ?? false
        }
        return await withCheckedContinuation { cont in
            store.requestAccess(to: .event) { granted, _ in cont.resume(returning: granted) }
        }
    }

    static func fetch(days: Int, count: Int, hideWords: String) async throws -> [EventItem] {
        guard await requestAccess() else { throw PanelError("Ge Panel åtkomst till Kalender i Systeminställningar → Integritet") }
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: max(1, days), to: start) ?? start
        let hidden = hideWords.lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
            .filter { e in
                let t = (e.title ?? "").lowercased()
                return !hidden.contains { t.contains($0) } && (e.isAllDay || e.endDate > Date())
            }
            .sorted { $0.startDate < $1.startDate }
        return events.prefix(count).map {
            EventItem(id: $0.eventIdentifier ?? UUID().uuidString, title: $0.title ?? "", start: $0.startDate, allDay: $0.isAllDay, location: $0.location ?? "")
        }
    }

    static func open(_ item: EventItem) {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
    }
}

// MARK: - Slack (med en egen användar-token)

struct SlackItem: Identifiable, Hashable {
    var id: String
    var who: String
    var place: String
    var text: String
    var date: Date
    var link: URL?
}

enum SlackSource {
    static func fetch(count: Int) async throws -> [SlackItem] {
        guard let token = Keychain.get("slack"), !token.isEmpty else { throw PanelError("Koppla Slack i inställningarna") }
        let since = Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date()
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        var c = URLComponents(string: "https://slack.com/api/search.messages")!
        c.queryItems = [
            URLQueryItem(name: "query", value: "after:\(day.string(from: since))"),
            URLQueryItem(name: "sort", value: "timestamp"),
            URLQueryItem(name: "sort_dir", value: "desc"),
            URLQueryItem(name: "count", value: "\(max(1, count))"),
        ]
        var request = URLRequest(url: c.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw PanelError("Konstigt svar från Slack") }
        guard json["ok"] as? Bool == true else { throw PanelError("Slack: \(json["error"] as? String ?? "fel")") }
        let matches = ((json["messages"] as? [String: Any])?["matches"] as? [[String: Any]]) ?? []
        return matches.map { m in
            let channel = m["channel"] as? [String: Any] ?? [:]
            let isDM = (channel["is_im"] as? Bool ?? false) || (channel["is_mpim"] as? Bool ?? false)
            let name = channel["name"] as? String ?? ""
            let team = m["team"] as? String ?? ""
            let channelID = channel["id"] as? String ?? ""
            let ts = Double(m["ts"] as? String ?? "") ?? 0
            let link = URL(string: "slack://channel?team=\(team)&id=\(channelID)") ?? (m["permalink"] as? String).flatMap(URL.init(string:))
            return SlackItem(id: (m["iid"] as? String) ?? (channelID + "\(ts)"),
                             who: m["username"] as? String ?? "",
                             place: isDM ? "DM" : "#\(name)",
                             text: clean(m["text"] as? String ?? ""),
                             date: Date(timeIntervalSince1970: ts),
                             link: link)
        }
    }

    /// Slack skriver länkar och omnämnanden som <https://…|text> och <@U123>.
    static func clean(_ text: String) -> String {
        var s = text
        while let open = s.range(of: "<"), let close = s.range(of: ">", range: open.upperBound..<s.endIndex) {
            let inner = String(s[open.upperBound..<close.lowerBound])
            let shown: String
            if let bar = inner.firstIndex(of: "|") { shown = String(inner[inner.index(after: bar)...]) }
            else if inner.hasPrefix("@") { shown = "@" }
            else if inner.hasPrefix("#") { shown = "#kanal" }
            else { shown = inner }
            s.replaceSubrange(open.lowerBound..<close.upperBound, with: shown)
        }
        return s.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "\n", with: " ")
    }
}

// MARK: - Genvägar

enum LinkOpener {
    static func open(_ target: String) {
        let t = target.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("/") || t.hasPrefix("~") {
            NSWorkspace.shared.open(URL(fileURLWithPath: (t as NSString).expandingTildeInPath))
        } else if let url = URL(string: t.contains("://") ? t : "https://\(t)") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct PanelError: LocalizedError {
    var message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
