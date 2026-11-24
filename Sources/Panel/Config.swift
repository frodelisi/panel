import Foundation
import Security

/// Vilka sorters delar panelen kan visa.
enum ModuleKind: String, Codable, CaseIterable, Identifiable {
    case mail, slack, calendar, tasks, links, note, weather, music
    var id: String { rawValue }

    var defaultTitle: String {
        switch self {
        case .mail: return "Mail"
        case .slack: return "Slack"
        case .calendar: return "Deadlines"
        case .tasks: return "Att göra"
        case .links: return "Genvägar"
        case .note: return "Anteckningar"
        case .weather: return "Väder"
        case .music: return "Musik"
        }
    }

    /// Halvhöga kort; två i rad läggs ovanpå varandra i samma kolumn.
    var isSmall: Bool { self == .weather || self == .music }

    var symbol: String {
        switch self {
        case .mail: return "envelope"
        case .slack: return "number"
        case .calendar: return "calendar"
        case .tasks: return "checkmark.circle"
        case .links: return "square.grid.2x2"
        case .note: return "note.text"
        case .weather: return "cloud.sun"
        case .music: return "music.note"
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
        Module(kind: .weather, title: "Väder"),
        Module(kind: .music, title: "Musik"),
    ]
    var links: [LinkItem] = [
        LinkItem(name: "Gmail", target: "https://mail.google.com"),
        LinkItem(name: "Kalender", target: "https://calendar.google.com"),
        LinkItem(name: "Google Tasks", target: "https://tasks.google.com"),
        LinkItem(name: "Mail", target: "/System/Applications/Mail.app"),
    ]
    var note = ""
    var dark = false                     // ljus panel som standard
    var slackUnreadOnly = true            // visa bara olästa Slack-meddelanden
    var weatherCity = "Stockholm"
    var gmailQuery = "in:inbox is:important category:primary newer_than:14d"   // vilka mail som räknas som viktiga
    var tasksAccount = ""                 // vilket Google-konto att göra-listan ligger i (tomt = första)
    var themeVersion = 4                 // äldre inställningar (mörk standard) byts till ljust en gång
    var calendarDays = 14
    var hideCalendarWords = ""           // kommaseparerade ord: händelser som innehåller dem visas inte
    var googleClientID = ""
    var newTaskList = "Mina uppgifter"    // listan i Google Tasks som nya uppgifter hamnar i
    var refreshMinutes = 2
    var importantMail = true             // visa de viktigaste mailen i stället för de senaste
    var importantSenders = ""            // kommaseparerat: namn eller adresser som alltid kommer först
    var unimportantWords = "no-reply, noreply, nyhetsbrev, newsletter, kvitto, receipt, faktura, invoice, order, levererad, delivered, erbjudande, rabatt, facebook, instagram, linkedin, tiktok"
    var chatURL = "https://claude.ai/code/session_01B9wdk8mGJodFQjCvNRXVx8"   // kugghjulet öppnar chatten med Claude

    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Panel", isDirectory: true)
    }
    static var file: URL { folder.appendingPathComponent("config.json") }

    static func load() -> Config {
        guard let data = try? Data(contentsOf: file),
              var config = try? JSONDecoder().decode(Config.self, from: data) else { return Config() }
        if config.themeVersion < 2 { config.dark = false }
        if config.themeVersion < 3 && !config.unimportantWords.lowercased().contains("facebook") {
            config.unimportantWords += ", facebook, instagram, linkedin, tiktok"
        }
        if config.themeVersion < 4 {
            for kind in [ModuleKind.weather, .music] where !config.modules.contains(where: { $0.kind == kind }) {
                config.modules.append(Module(kind: kind, title: kind.defaultTitle))
            }
        }
        if config.themeVersion < 4 {
            config.themeVersion = 4
            config.save()
        }
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
        themeVersion = (try? c.decode(Int.self, forKey: .themeVersion)) ?? 0
        slackUnreadOnly = (try? c.decode(Bool.self, forKey: .slackUnreadOnly)) ?? d.slackUnreadOnly
        weatherCity = (try? c.decode(String.self, forKey: .weatherCity)) ?? d.weatherCity
        gmailQuery = (try? c.decode(String.self, forKey: .gmailQuery)) ?? d.gmailQuery
        tasksAccount = (try? c.decode(String.self, forKey: .tasksAccount)) ?? d.tasksAccount
        importantMail = (try? c.decode(Bool.self, forKey: .importantMail)) ?? d.importantMail
        importantSenders = (try? c.decode(String.self, forKey: .importantSenders)) ?? d.importantSenders
        unimportantWords = (try? c.decode(String.self, forKey: .unimportantWords)) ?? d.unimportantWords
    }
}

/// Hemligheter (Slack-token, Google-nycklar). Sparas i en fil som bara ditt konto kan läsa
/// (~/Library/Application Support/Panel/secrets.json), inte i nyckelringen: nyckelringen frågar
/// om lösenord efter varje uppdatering, eftersom appen byggs om. Äldre nycklar flyttas över en gång.
enum Keychain {
    private static let service = "se.panel.app"
    private static var file: URL { Config.folder.appendingPathComponent("secrets.json") }
    private static var cache: [String: String]?

    private static func load() -> [String: String] {
        if let cache { return cache }
        let data = (try? Data(contentsOf: file)) ?? Data()
        let values = (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
        cache = values
        return values
    }

    private static func store(_ values: [String: String]) {
        cache = values
        try? FileManager.default.createDirectory(at: Config.folder, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(values) {
            try? data.write(to: file, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
    }

    static func get(_ key: String) -> String? {
        var values = load()
        if let v = values[key] { return v.isEmpty ? nil : v }
        // Flytta över från nyckelringen (en sista gång), sedan aldrig mer.
        if !values.keys.contains("moved." + key) {
            // Bara "klar" om nyckeln flyttades eller inte fanns. Avbryts lösenordsrutan försöker vi igen nästa gång.
            let (status, old) = oldKeychainValue(key)
            if status == errSecSuccess || status == errSecItemNotFound {
                values["moved." + key] = "1"
                if let old {
                    values[key] = old
                    deleteOldKeychainValue(key)
                }
                store(values)
            }
        }
        return values[key]
    }

    static func set(_ value: String?, for key: String) {
        var values = load()
        values[key] = value ?? ""
        values["moved." + key] = "1"
        store(values)
    }

    private static func oldKeychainValue(_ key: String) -> (OSStatus, String?) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let data = out as? Data else { return (status, nil) }
        return (status, String(data: data, encoding: .utf8))
    }

    private static func deleteOldKeychainValue(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
