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

    private func count(_ kind: ModuleKind) -> Int { config.modules.first { $0.kind == kind }?.count ?? 5 }
    private func isOn(_ kind: ModuleKind) -> Bool { config.modules.contains { $0.kind == kind && $0.enabled } }

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
        let rules = MailRules(important: config.importantMail, senders: config.importantSenders, unimportant: config.unimportantWords)

        // Alla fyra hämtas samtidigt.
        async let m = Store.attempt(mailOn) { try await MailSource.fetch(count: mailN, rules: rules) }
        async let s = Store.attempt(slackOn) { try await SlackSource.fetch(count: slackN, unreadOnly: slackUnread) }
        async let e = Store.attempt(calOn) { try await CalendarSource.fetch(days: days, count: calN, hideWords: hide) }
        async let t = Store.attempt(taskOn) { try await GoogleTasks.fetch(clientID: clientID, count: taskN) }

        apply(.mail, await m) { self.mail = $0 }
        apply(.slack, await s) { self.slack = $0 }
        apply(.calendar, await e) { self.events = $0 }
        apply(.tasks, await t) { self.tasks = $0 }
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
        Task {
            do { try await GoogleTasks.complete(task, clientID: config.googleClientID) }
            catch { problems[.tasks] = error.localizedDescription; await refresh() }
        }
    }

    func addTask(_ title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        Task {
            do {
                try await GoogleTasks.add(t, listTitle: config.newTaskList, clientID: config.googleClientID)
                await refresh()
            } catch { problems[.tasks] = error.localizedDescription }
        }
    }

    func signInGoogle() {
        googleStatus = "Öppnar Google i webbläsaren…"
        Task {
            do {
                try await GoogleTasks.signIn(clientID: config.googleClientID.trimmingCharacters(in: .whitespaces))
                googleStatus = "Kopplad ✓"
                await refresh()
            } catch { googleStatus = error.localizedDescription }
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
