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
            Section("Delar i panelen") {
                ForEach($store.config.modules) { $module in
                    HStack(spacing: 10) {
                        Toggle("", isOn: $module.enabled).labelsHidden()
                        Image(systemName: module.kind.symbol).frame(width: 18)
                        TextField("Namn", text: $module.title).frame(width: 150)
                        if module.kind != .links && module.kind != .note {
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
                Stepper("Deadlines: visa \(store.config.calendarDays) dagar framåt", value: $store.config.calendarDays, in: 1...60)
                TextField("Dölj kalenderhändelser som innehåller (t.ex. lunch, pengar)", text: $store.config.hideCalendarWords)
                TextField("Kugghjulet öppnar (länk till chatten med Claude)", text: $store.config.chatURL)
            }

            Section("Genvägar") {
                ForEach($store.config.links) { $link in
                    HStack {
                        TextField("Namn", text: $link.name).frame(width: 140)
                        TextField("Webbadress eller app, t.ex. /Applications/Slack.app", text: $link.target)
                        Button { store.config.links.removeAll { $0.id == link.id } } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
                HStack {
                    Button("Lägg till genväg") { store.config.links.append(LinkItem(name: "Ny", target: "https://")) }
                    Button("Lägg till en app…") { pickApp() }
                }
            }

            Section("Google Tasks") {
                TextField("Client ID", text: $store.config.googleClientID)
                SecureField("Client secret", text: $clientSecret)
                    .onChange(of: clientSecret) { Keychain.set($0, for: "google.secret") }
                TextField("Nya uppgifter hamnar i listan", text: $store.config.newTaskList)
                HStack {
                    Button(GoogleTasks.isConnected ? "Logga in igen" : "Logga in med Google") { store.signInGoogle() }
                    if GoogleTasks.isConnected { Button("Logga ut") { GoogleTasks.signOut(); store.googleStatus = "Utloggad" } }
                    Text(store.googleStatus.isEmpty ? (GoogleTasks.isConnected ? "Kopplad ✓" : "Inte kopplad") : store.googleStatus)
                        .foregroundColor(.secondary)
                }
            }

            Section("Slack") {
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
