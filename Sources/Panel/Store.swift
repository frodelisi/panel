import AppKit
import Foundation

/// Allt panelen visar, och det som händer när man klickar.
@MainActor
final class Store: ObservableObject {
    @Published var config: Config { didSet { scheduleSave() } }
    @Published var mail: [MailItem] = []
    @Published var slack: [SlackItem] = []
    @Published var events: [EventItem] = []
    @Published var tasks: [TaskItem] = []
    @Published var weather: WeatherNow?
    @Published var invites: [Invite] = []
    @Published var economy: EconomyNow?
    @Published var doneToday = Store.loadDoneToday()
    @Published var music: MusicNow?
    @Published var problems: [ModuleKind: String] = [:]
    @Published var googleStatus = ""
    @Published var lastRefresh = Date.distantPast

    var openSettings: () -> Void = {}
    var layoutChanged: () -> Void = {}
    private var saveTask: Task<Void, Never>?

    init() {
        config = Config.load()
    }

    var enabledModules: [Module] { config.modules.filter(\.enabled) }

    private func count(_ kind: ModuleKind) -> Int {
        let inbox = config.modules.first { $0.kind == .inbox && $0.enabled }?.count
        if let inbox, kind == .mail || kind == .slack { return max(inbox, config.modules.first { $0.kind == kind }?.count ?? 0) }
        return config.modules.first { $0.kind == kind }?.count ?? 5
    }
    private func isOn(_ kind: ModuleKind) -> Bool {
        if config.modules.contains(where: { $0.kind == kind && $0.enabled }) { return true }
        // "Viktigt" behöver både mail och Slack; vädret kan visas i Live-raden.
        if (kind == .mail || kind == .slack) && config.modules.contains(where: { $0.kind == .inbox && $0.enabled }) { return true }
        if kind == .weather && config.weatherInHeader { return true }
        return false
    }

    /// Antal att göra-punkter som bockats av i dag (nollställs vid midnatt).
    nonisolated static func loadDoneToday() -> Int {
        let d = UserDefaults.standard
        return d.string(forKey: "doneDay") == Store.dayKey() ? d.integer(forKey: "doneCount") : 0
    }
    nonisolated static func dayKey() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date())
    }
    private func bumpDone() {
        doneToday = Store.loadDoneToday() + 1
        UserDefaults.standard.set(Store.dayKey(), forKey: "doneDay")
        UserDefaults.standard.set(doneToday, forKey: "doneCount")
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = config
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            snapshot.save()
            self?.layoutChanged()
        }
    }

    // MARK: Hämta

    func refresh() async {
        lastRefresh = Date()
        let mailN = count(.mail), slackN = count(.slack), calN = count(.calendar), taskN = count(.tasks)
        let mailOn = isOn(.mail), slackOn = isOn(.slack), calOn = isOn(.calendar), taskOn = isOn(.tasks)
        let days = config.calendarDays, hide = config.hideCalendarWords, clientID = config.googleClientID
        let slackUnread = config.slackUnreadOnly
        let googleAccounts = Google.accounts, gmailQuery = config.gmailQuery
        let tasksAccount = taskAccount
        let rules = MailRules(important: config.importantMail, senders: config.importantSenders, unimportant: config.unimportantWords)

        // Allt hämtas samtidigt.
        // Gmail när Google-konton är inloggade, annars Mail-appen.
        async let m = Store.attempt(mailOn) { () async throws -> [MailItem] in
            if googleAccounts.isEmpty { throw PanelError("Lägg till dina Gmail-konton i inställningarna") }
            return try await Gmail.important(accounts: googleAccounts, clientID: clientID, query: gmailQuery, count: mailN, rules: rules)
        }
        async let inv = Store.loadInvites(mailOn, googleAccounts, clientID)
        async let s = Store.attempt(slackOn) { try await SlackSource.fetch(count: slackN, unreadOnly: slackUnread) }
        // Google Kalender när Google-konton är inloggade, annars Kalender-appen på Macen.
        async let e = Store.attempt(calOn) { () async throws -> [EventItem] in
            if googleAccounts.isEmpty { return try await CalendarSource.fetch(days: days, count: calN, hideWords: hide) }
            return try await Gmail.events(accounts: googleAccounts, clientID: clientID, days: days, count: calN, hideWords: hide)
        }
        async let t = Store.attempt(taskOn) { try await GoogleTasks.fetch(account: tasksAccount, clientID: clientID, count: taskN) }

        apply(.mail, await m) { self.mail = $0 }
        invites = await inv
        apply(.slack, await s) { self.slack = $0 }
        apply(.calendar, await e) { self.events = $0 }
        apply(.tasks, await t) { self.tasks = $0 }
        if isOn(.weather) {
            do { weather = try await WeatherSource.fetch(city: config.weatherCity); problems[.weather] = nil }
            catch { problems[.weather] = error.localizedDescription }
        }
        if config.modules.contains(where: { $0.kind == .economy && $0.enabled }) {
            do { economy = try await EconomySource.fetch(base: config.dashboardURL); problems[.economy] = nil }
            catch { problems[.economy] = error.localizedDescription }
        }
        await refreshMusic()
    }

    /// Musiken hämtas ofta (varannan sekund) medan panelen är öppen.
    func refreshMusic() async {
        guard isOn(.music) else { return }
        music = await MusicSource.fetch()
    }

    func musicCommand(_ command: String) {
        guard let app = music?.app else { return }
        if command == "playpause" { music?.playing.toggle() }   // knappen byts direkt
        Task {
            await MusicSource.command(command, app: app)
            try? await Task.sleep(nanoseconds: 350_000_000)
            await refreshMusic()
        }
    }

    nonisolated static func loadInvites(_ on: Bool, _ accounts: [String], _ clientID: String) async -> [Invite] {
        if !on || accounts.isEmpty { return [] }
        return await Gmail.invites(accounts: accounts, clientID: clientID)
    }

    nonisolated static func attempt<T>(_ on: Bool, _ fetch: () async throws -> T) async -> Result<T, Error>? {
        guard on else { return nil }
        do { return .success(try await fetch()) } catch { return .failure(error) }
    }

    private func apply<T>(_ kind: ModuleKind, _ result: Result<T, Error>?, _ set: (T) -> Void) {
        guard let result else { return }
        switch result {
        case .success(let value):
            set(value)
            problems[kind] = nil
        case .failure(let error):
            problems[kind] = error.localizedDescription
        }
    }

    // MARK: Klick

    func open(_ item: MailItem) { MailSource.open(item) }
    func open(_ item: EventItem) { CalendarSource.open(item) }
    func open(_ item: SlackItem) { if let url = item.link { NSWorkspace.shared.open(url) } }

    func complete(_ task: TaskItem) {
        tasks.removeAll { $0.id == task.id }      // försvinner direkt, Google uppdateras i bakgrunden
        bumpDone()
        Task {
            do { try await GoogleTasks.complete(task, account: taskAccount, clientID: config.googleClientID) }
            catch { problems[.tasks] = error.localizedDescription; await refresh() }
        }
    }

    func addTask(_ title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        Task {
            do {
                try await GoogleTasks.add(t, listTitle: config.newTaskList, account: taskAccount, clientID: config.googleClientID)
                await refresh()
            } catch { problems[.tasks] = error.localizedDescription }
        }
    }

    func signInGoogle() {
        googleStatus = "Öppnar Google i webbläsaren…"
        Task {
            do {
                let email = try await Google.addAccount(clientID: config.googleClientID.trimmingCharacters(in: .whitespaces))
                googleStatus = "\(email) är inloggad ✓"
                await refresh()
            } catch { googleStatus = error.localizedDescription }
        }
    }

    /// Kontot där att göra-listan ligger: det valda, annars det första (eller den gamla inloggningen).
    var taskAccount: String? {
        let chosen = config.tasksAccount.trimmingCharacters(in: .whitespaces).lowercased()
        if !chosen.isEmpty, Google.accounts.contains(chosen) { return chosen }
        return Google.hasLegacy ? nil : Google.accounts.first
    }

    /// Svara på en inbjudan. Den försvinner direkt; Google meddelar den som bjöd in.
    func respond(_ invite: Invite, _ status: String) {
        invites.removeAll { $0.id == invite.id }
        Task {
            do { try await Gmail.respond(invite, status: status, clientID: config.googleClientID) }
            catch { problems[.mail] = error.localizedDescription; await refresh() }
        }
    }

    // MARK: Ändra panelen

    func move(_ module: Module, by step: Int) {
        guard let i = config.modules.firstIndex(of: module) else { return }
        let j = i + step
        guard config.modules.indices.contains(j) else { return }
        config.modules.swapAt(i, j)
    }

    func addModule(_ kind: ModuleKind) {
        config.modules.append(Module(kind: kind, title: kind.defaultTitle))
    }

    func remove(_ module: Module) {
        config.modules.removeAll { $0.id == module.id }
    }
}
