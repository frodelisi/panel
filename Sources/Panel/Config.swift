import Foundation
import Security

/// Vilka sorters delar panelen kan visa.
enum ModuleKind: String, Codable, CaseIterable, Identifiable {
    case mail, slack, calendar, tasks, links, note
    var id: String { rawValue }

    var defaultTitle: String {
        switch self {
        case .mail: return "Mail"
        case .slack: return "Slack"
        case .calendar: return "Deadlines"
        case .tasks: return "Att göra"
        case .links: return "Genvägar"
        case .note: return "Anteckningar"
        }
    }

    var symbol: String {
        switch self {
        case .mail: return "envelope"
        case .slack: return "number"
        case .calendar: return "calendar"
        case .tasks: return "checkmark.circle"
        case .links: return "square.grid.2x2"
        case .note: return "note.text"
        }
    }
}

/// En del i panelen. Ordningen i listan är ordningen i panelen.
struct Module: Codable, Identifiable, Hashable {
    var id = UUID()
    var kind: ModuleKind
    var title: String
    var enabled = true
    var count = 5
}

/// En genväg: en webbadress (https://…) eller en app/mapp (/Applications/Mail.app).
struct LinkItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var target: String
}

struct Config: Codable {
    var modules: [Module] = [
        Module(kind: .mail, title: "Mail", count: 4),
        Module(kind: .slack, title: "Slack", count: 4),
        Module(kind: .calendar, title: "Deadlines", count: 4),
        Module(kind: .tasks, title: "Att göra", count: 6),
        Module(kind: .links, title: "Genvägar", enabled: false),
        Module(kind: .note, title: "Anteckningar", enabled: false),
    ]
    var links: [LinkItem] = [
        LinkItem(name: "Gmail", target: "https://mail.google.com"),
        LinkItem(name: "Kalender", target: "https://calendar.google.com"),
        LinkItem(name: "Google Tasks", target: "https://tasks.google.com"),
        LinkItem(name: "Mail", target: "/System/Applications/Mail.app"),
    ]
    var note = ""
    var dark = true
    var calendarDays = 14
    var hideCalendarWords = ""           // kommaseparerade ord: händelser som innehåller dem visas inte
    var googleClientID = ""
    var newTaskList = "Mina uppgifter"    // listan i Google Tasks som nya uppgifter hamnar i
    var refreshMinutes = 2
    var chatURL = "https://claude.ai/code/session_01B9wdk8mGJodFQjCvNRXVx8"   // kugghjulet öppnar chatten med Claude

    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Panel", isDirectory: true)
    }
    static var file: URL { folder.appendingPathComponent("config.json") }

    static func load() -> Config {
        guard let data = try? Data(contentsOf: file),
              let config = try? JSONDecoder().decode(Config.self, from: data) else { return Config() }
        return config
    }

    func save() {
        try? FileManager.default.createDirectory(at: Config.folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(self) { try? data.write(to: Config.file, options: .atomic) }
    }

    // Nya fält i senare versioner ska inte göra att en gammal config inte går att läsa.
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config()
        modules = (try? c.decode([Module].self, forKey: .modules)) ?? d.modules
        links = (try? c.decode([LinkItem].self, forKey: .links)) ?? d.links
        note = (try? c.decode(String.self, forKey: .note)) ?? d.note
        dark = (try? c.decode(Bool.self, forKey: .dark)) ?? d.dark
        calendarDays = (try? c.decode(Int.self, forKey: .calendarDays)) ?? d.calendarDays
        hideCalendarWords = (try? c.decode(String.self, forKey: .hideCalendarWords)) ?? d.hideCalendarWords
        googleClientID = (try? c.decode(String.self, forKey: .googleClientID)) ?? d.googleClientID
        newTaskList = (try? c.decode(String.self, forKey: .newTaskList)) ?? d.newTaskList
        refreshMinutes = (try? c.decode(Int.self, forKey: .refreshMinutes)) ?? d.refreshMinutes
        chatURL = (try? c.decode(String.self, forKey: .chatURL)) ?? d.chatURL
    }
}

/// Hemligheter (Slack-token, Google-nycklar) sparas i macOS nyckelring, inte i config-filen.
enum Keychain {
    private static let service = "se.panel.app"

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String?, for key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}
