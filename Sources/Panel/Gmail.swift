import Foundation

/// En kalenderinbjudan som väntar på svar.
struct Invite: Identifiable, Hashable {
    var id: String { account + "/" + eventID }
    var eventID: String
    var account: String
    var title: String
    var start: Date?
    var allDay: Bool
    var organizer: String
    var attendees: Data      // alla deltagare som JSON (behövs för att svara)
}

/// De viktigaste mailen och olästa inbjudningar från alla inloggade Gmail-konton.
enum Gmail {
    /// De viktigaste mailen från alla konton. query är en vanlig Gmail-sökning.
    static func important(accounts: [String], clientID: String, query: String, count: Int, rules: MailRules) async throws -> [MailItem] {
        var all: [MailItem] = []
        var firstError: Error?
        for account in accounts {
            do { all += try await fetch(account: account, clientID: clientID, query: query, max: max(count * 2, 10)) }
            catch { firstError = firstError ?? error }
        }
        if all.isEmpty, let firstError { throw firstError }
        let sorted = all
            .filter { !rules.isUnimportant($0) }       // kvitton, nyhetsbrev och Facebook bort
            .sorted { rules.score($0) > rules.score($1) }
        return Array(sorted.prefix(max(1, count)))
    }

    private static func fetch(account: String, clientID: String, query: String, max: Int) async throws -> [MailItem] {
        var c = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages")!
        c.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "maxResults", value: "\(max)")]
        let list = try await Google.request("GET", c.url!.absoluteString, account: account, clientID: clientID)
        let ids = (list["messages"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }

        var items: [MailItem] = []
        for id in ids {
            let m = try await Google.request(
                "GET", "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)?format=metadata&metadataHeaders=From&metadataHeaders=Subject",
                account: account, clientID: clientID)
            let headers = (m["payload"] as? [String: Any])?["headers"] as? [[String: Any]] ?? []
            func header(_ name: String) -> String {
                headers.first { ($0["name"] as? String)?.lowercased() == name.lowercased() }?["value"] as? String ?? ""
            }
            let labels = m["labelIds"] as? [String] ?? []
            let millis = Double(m["internalDate"] as? String ?? "") ?? 0
            let thread = m["threadId"] as? String ?? id
            let from = header("From")
            let link = URL(string: "https://mail.google.com/mail/?authuser=\(account)#all/\(thread)")
            items.append(MailItem(id: account + "/" + id, sender: MailSource.cleanSender(from), address: from,
                                  subject: header("Subject"), unread: labels.contains("UNREAD"), flagged: labels.contains("STARRED"),
                                  date: millis > 0 ? Date(timeIntervalSince1970: millis / 1000) : nil,
                                  account: shortName(account), link: link))
        }
        return items
    }

    /// "frode@touchen.se" → "touchen", "frode.lisiderius@gmail.com" → "gmail"
    static func shortName(_ email: String) -> String {
        let domain = email.split(separator: "@").last.map(String.init) ?? email
        return domain.split(separator: ".").first.map(String.init) ?? domain
    }

    // MARK: Inbjudningar

    static func invites(accounts: [String], clientID: String) async -> [Invite] {
        var all: [Invite] = []
        let iso = ISO8601DateFormatter()
        let now = iso.string(from: Date())
        let later = iso.string(from: Date().addingTimeInterval(90 * 86_400))
        for account in accounts {
            var c = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
            c.queryItems = [
                URLQueryItem(name: "timeMin", value: now), URLQueryItem(name: "timeMax", value: later),
                URLQueryItem(name: "singleEvents", value: "true"), URLQueryItem(name: "orderBy", value: "startTime"),
                URLQueryItem(name: "maxResults", value: "100"),
            ]
            guard let json = try? await Google.request("GET", c.url!.absoluteString, account: account, clientID: clientID) else { continue }
            for e in json["items"] as? [[String: Any]] ?? [] {
                let attendees = e["attendees"] as? [[String: Any]] ?? []
                guard let me = attendees.first(where: { $0["self"] as? Bool == true }),
                      me["responseStatus"] as? String == "needsAction",
                      (e["organizer"] as? [String: Any])?["self"] as? Bool != true,
                      let eventID = e["id"] as? String else { continue }
                let start = e["start"] as? [String: Any] ?? [:]
                let organizer = (e["organizer"] as? [String: Any]) ?? [:]
                all.append(Invite(eventID: eventID, account: account, title: e["summary"] as? String ?? "(utan namn)",
                                  start: parseStart(start), allDay: start["date"] != nil,
                                  organizer: organizer["displayName"] as? String ?? organizer["email"] as? String ?? "",
                                  attendees: (try? JSONSerialization.data(withJSONObject: attendees)) ?? Data()))
            }
        }
        return all.sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
    }

    /// Svarar på en inbjudan: "accepted", "tentative" eller "declined". Den som bjöd in får besked.
    static func respond(_ invite: Invite, status: String, clientID: String) async throws {
        var attendees = (try? JSONSerialization.jsonObject(with: invite.attendees) as? [[String: Any]]) ?? []
        for i in attendees.indices where attendees[i]["self"] as? Bool == true {
            attendees[i]["responseStatus"] = status
        }
        _ = try await Google.request(
            "PATCH", "https://www.googleapis.com/calendar/v3/calendars/primary/events/\(invite.eventID)?sendUpdates=all",
            account: invite.account, clientID: clientID, body: ["attendees": attendees])
    }

    private static func parseStart(_ s: [String: Any]) -> Date? {
        if let dt = s["dateTime"] as? String {
            let f = ISO8601DateFormatter()
            if let d = f.date(from: dt) { return d }
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.date(from: dt)
        }
        if let d = s["date"] as? String {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            return f.date(from: d)
        }
        return nil
    }
}
