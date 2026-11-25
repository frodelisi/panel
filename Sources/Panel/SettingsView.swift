import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var store: Store
    @State private var clientSecret = Keychain.get("google.secret") ?? ""
    @State private var slackToken = Keychain.get("slack") ?? ""
    @State private var slackSaved = ""

    init(store: Store) { self.store = store }

    var body: some View {
        Form {
            Section("Konton") {
                AccountRow(symbol: "envelope", name: "Gmail",
                           status: store.problems[.mail] ?? (Google.accounts.isEmpty ? "Inget Gmail-konto inloggat" : Google.accounts.joined(separator: ", ")),
                           button: "Lägg till konto") {
                    store.signInGoogle()
                }
                AccountRow(symbol: "calendar", name: "Kalender", status: store.problems[.calendar] ?? "Läses från Kalender-appen ✓", button: "Ge åtkomst") {
                    Task { _ = await CalendarSource.requestAccess(); await store.refresh() }
                }
                AccountRow(symbol: "checkmark.circle", name: "Google Tasks",
                           status: store.problems[.tasks] ?? (store.taskAccount ?? (Google.hasLegacy ? "Inloggad ✓" : "Inte inloggad")),
                           button: "Lägg till konto") {
                    store.signInGoogle()
                }
                AccountRow(symbol: "number", name: "Slack", status: Keychain.get("slack") == nil ? "Inte kopplad – klistra in token längre ner" : "Kopplad ✓",
                           button: "Skapa token") {
                    LinkOpener.open("https://api.slack.com/apps")
                }
            }

            Section("Mail") {
                Toggle("Visa de viktigaste mailen (annars de senaste)", isOn: $store.config.importantMail)
                TextField("Viktiga avsändare, t.ex. molly, skolan.se, mamma", text: $store.config.importantSenders)
                TextField("Oviktigt (sorteras bort): ord i avsändare eller ämne", text: $store.config.unimportantWords)
            }

            Section("Delar i panelen") {
                ForEach($store.config.modules) { $module in
                    HStack(spacing: 10) {
                        Toggle("", isOn: $module.enabled).labelsHidden()
                        Image(systemName: module.kind.symbol).frame(width: 18)
                        TextField("Namn", text: $module.title, prompt: Text("Namn")).labelsHidden().frame(width: 150)
                        if module.kind != .links && module.kind != .note && !module.kind.isSmall {
                            Stepper("Visa \(module.count)", value: $module.count, in: 1...15).frame(width: 120)
                        }
                        Spacer()
                        Button { store.move(module, by: -1) } label: { Image(systemName: "chevron.up") }.help("Flytta till vänster")
                        Button { store.move(module, by: 1) } label: { Image(systemName: "chevron.down") }.help("Flytta till höger")
                        Button { store.remove(module) } label: { Image(systemName: "trash") }.help("Ta bort")
                    }
                    .buttonStyle(.borderless)
                }
                Menu("Lägg till en del") {
                    ForEach(ModuleKind.allCases) { kind in
                        Button(kind.defaultTitle) { store.addModule(kind) }
                    }
                }
                .fixedSize()
            }

            Section("Utseende") {
                Toggle("Mörk panel", isOn: $store.config.dark)
                TextField("Väder för (stad)", text: $store.config.weatherCity)
                TextField("Dashboard (adress till Mac minin, t.ex. http://mac-mini.local:8765)", text: $store.config.dashboardURL)
                Stepper("Deadlines: visa \(store.config.calendarDays) dagar framåt", value: $store.config.calendarDays, in: 1...60)
                TextField("Dölj kalenderhändelser som innehåller (t.ex. lunch, pengar)", text: $store.config.hideCalendarWords)
                TextField("Kugghjulet öppnar (länk till chatten med Claude)", text: $store.config.chatURL)
            }

            Section("Genvägar") {
                ForEach($store.config.links) { $link in
                    HStack {
                        TextField("Namn", text: $link.name, prompt: Text("Namn")).labelsHidden().frame(width: 140)
                        TextField("Adress", text: $link.target, prompt: Text("https://… eller /Applications/…")).labelsHidden()
                        Button { store.config.links.removeAll { $0.id == link.id } } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
                HStack {
                    Button("Lägg till genväg") { store.config.links.append(LinkItem(name: "Ny", target: "https://")) }
                    Button("Lägg till en app…") { pickApp() }
                }
            }

            Section("Google (Gmail, inbjudningar och Google Tasks)") {
                TextField("Client ID", text: $store.config.googleClientID)
                SecureField("Client secret", text: $clientSecret)
                    .onChange(of: clientSecret) { Keychain.set($0, for: "google.secret") }
                ForEach(Google.accounts, id: \.self) { email in
                    HStack {
                        Image(systemName: "person.crop.circle").foregroundColor(.secondary)
                        Text(email)
                        Spacer()
                        Button("Ta bort") { Google.removeAccount(email); store.googleStatus = "\(email) borttaget"; Task { await store.refresh() } }
                    }
                }
                HStack {
                    Button("Lägg till Google-konto") { store.signInGoogle() }
                    Text(store.googleStatus).foregroundColor(.secondary)
                }
                Text("Lägg till både ditt privata och ditt jobbkonto. Varje konto loggas in en gång i webbläsaren.")
                    .font(.caption).foregroundColor(.secondary)
                TextField("Vilka mail räknas som viktiga (Gmail-sökning)", text: $store.config.gmailQuery)
                if !Google.accounts.isEmpty {
                    Picker("Att göra-listan ligger i", selection: $store.config.tasksAccount) {
                        Text("Första kontot").tag("")
                        ForEach(Google.accounts, id: \.self) { Text($0).tag($0) }
                    }
                }
                TextField("Nya uppgifter hamnar i listan", text: $store.config.newTaskList)
            }

            Section("Slack") {
                Toggle("Visa bara olästa meddelanden", isOn: $store.config.slackUnreadOnly)
                SecureField("Användar-token (börjar med xoxp-)", text: $slackToken)
                HStack {
                    Button("Spara") {
                        Keychain.set(slackToken.trimmingCharacters(in: .whitespaces), for: "slack")
                        slackSaved = "Sparad ✓"
                        Task { await store.refresh() }
                    }
                    Text(slackSaved).foregroundColor(.secondary)
                }
            }

            Section("Version") {
                Text(Updater.version.isEmpty ? "Okänd version" : Updater.version).foregroundColor(.secondary)
                if Updater.repoPath != nil {
                    Text("Panelen hämtar nya versioner från GitHub själv, en gång i timmen.").foregroundColor(.secondary)
                    Button("Sök efter ny version nu") { Updater.check() }
                } else {
                    Text("Installerad utan GitHub, så den uppdateras inte själv.").foregroundColor(.secondary)
                }
            }

            Section("Mail och kalender") {
                Text("Mail läses från Mail-appen och kalendern från Kalender-appen på den här Macen. macOS frågar om lov första gången.")
                    .foregroundColor(.secondary)
                HStack {
                    Button("Hämta nytt nu") { Task { await store.refresh() } }
                    Button("Visa inställningsfilen") { NSWorkspace.shared.activateFileViewerSelecting([Config.file]) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 640, height: 720)
    }

    private func pickApp() {
        let open = NSOpenPanel()
        open.directoryURL = URL(fileURLWithPath: "/Applications")
        open.allowedContentTypes = [.application]
        open.canChooseDirectories = false
        if open.runModal() == .OK, let url = open.url {
            store.config.links.append(LinkItem(name: url.deletingPathExtension().lastPathComponent, target: url.path))
        }
    }
}

struct AccountRow: View {
    var symbol: String
    var name: String
    var status: String
    var button = "Öppna"
    var action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).frame(width: 18)
            Text(name).frame(width: 110, alignment: .leading)
            Text(status).foregroundColor(.secondary).lineLimit(1)
            Spacer()
            Button(button, action: action)
        }
    }
}
