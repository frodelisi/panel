import AppKit
import CryptoKit
import Foundation
import Network

struct TaskItem: Identifiable, Hashable {
    var id: String
    var listID: String
    var listTitle: String
    var title: String
    var due: Date?          // Google sparar bara datumet (midnatt UTC)
}

/// Inloggning till ett eller flera Google-konton (t.ex. privat och jobb). Inloggningen sker i webbläsaren
/// en gång per konto; sedan sparas en "refresh token" per konto i den skyddade filen.
enum Google {
    static let scopes = [
        "https://www.googleapis.com/auth/tasks",
        "https://www.googleapis.com/auth/gmail.readonly",
        "https://www.googleapis.com/auth/calendar.events",
    ].joined(separator: " ")
    private static let port: UInt16 = 8977
    private static var redirect: String { "http://127.0.0.1:\(port)" }
    private static var access: [String: (token: String, expiry: Date)] = [:]

    /// Inloggade konton (mailadresser).
    static var accounts: [String] {
        (Keychain.get("google.accounts") ?? "").split(separator: ",").map(String.init).filter { !$0.isEmpty }
    }
    /// Den gamla inloggningen (bara Tasks) från första versionen.
    static var hasLegacy: Bool { Keychain.get("google.refresh") != nil }
    static var isConnected: Bool { !accounts.isEmpty || hasLegacy }

    private static func refreshToken(_ account: String?) -> String? {
        if let account, let t = Keychain.get("google.refresh.\(account)") { return t }
        return Keychain.get("google.refresh")
    }

    // MARK: Inloggning

    /// Loggar in ett konto i webbläsaren. Svarar med kontots mailadress.
    @discardableResult
    static func addAccount(clientID: String) async throws -> String {
        guard !clientID.isEmpty, let secret = Keychain.get("google.secret"), !secret.isEmpty else {
            throw PanelError("Fyll i Client ID och Client secret först")
        }
        let verifier = randomString(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        c.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent select_account"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        let receiver = try LoopbackReceiver(port: port)
        let url = c.url!
        await MainActor.run { _ = NSWorkspace.shared.open(url) }
        let code = try await receiver.waitForCode()
        let json = try await tokenRequest([
            "code": code, "client_id": clientID, "client_secret": secret,
            "redirect_uri": redirect, "grant_type": "authorization_code", "code_verifier": verifier,
        ])
        guard let refresh = json["refresh_token"] as? String, let token = json["access_token"] as? String else {
            throw PanelError("Google gav ingen nyckel. Försök igen.")
        }
        // Vilket konto var det? Gmail svarar med adressen.
        var request = URLRequest(url: URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/profile")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        let profile = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard let email = (profile["emailAddress"] as? String)?.lowercased() else {
            throw PanelError("Kunde inte läsa Gmail. Har du slagit på Gmail API i Google Cloud?")
        }
        Keychain.set(refresh, for: "google.refresh.\(email)")
        access[email] = (token, Date().addingTimeInterval((json["expires_in"] as? Double ?? 3600) - 60))
        var list = accounts
        if !list.contains(email) { list.append(email) }
        Keychain.set(list.joined(separator: ","), for: "google.accounts")
        return email
    }

    static func removeAccount(_ email: String) {
        Keychain.set(nil, for: "google.refresh.\(email)")
        Keychain.set(accounts.filter { $0 != email }.joined(separator: ","), for: "google.accounts")
        access[email] = nil
    }

    static func signOutAll() {
        for a in accounts { removeAccount(a) }
        Keychain.set(nil, for: "google.refresh")
        access = [:]
    }

    private static func token(_ account: String?, clientID: String) async throws -> String {
        let key = account ?? "legacy"
        if let a = access[key], Date() < a.expiry { return a.token }
        guard let refresh = refreshToken(account) else { throw PanelError("Logga in med Google i inställningarna") }
        let json = try await tokenRequest([
            "refresh_token": refresh, "client_id": clientID,
            "client_secret": Keychain.get("google.secret") ?? "", "grant_type": "refresh_token",
        ])
        guard let t = json["access_token"] as? String else { throw PanelError("Kunde inte förnya inloggningen till Google") }
        access[key] = (t, Date().addingTimeInterval((json["expires_in"] as? Double ?? 3600) - 60))
        return t
    }

    private static func tokenRequest(_ form: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form.map { "\($0.key)=\(formEncode($0.value))" }.joined(separator: "&").data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        if let error = json["error"] as? String {
            if error == "invalid_grant" { throw PanelError("Google-inloggningen har gått ut. Logga in igen i inställningarna.") }
            throw PanelError("Google: \(json["error_description"] as? String ?? error)")
        }
        return json
    }

    /// Anropar ett Google-API som kontot. url är hela adressen.
    static func request(_ method: String, _ url: String, account: String?, clientID: String, body: [String: Any]? = nil) async throws -> [String: Any] {
        guard let u = URL(string: url) else { throw PanelError("Fel adress") }
        var request = URLRequest(url: u)
        request.httpMethod = method
        let bearer = try await token(account, clientID: clientID)
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        if let http = response as? HTTPURLResponse, http.statusCode >= 300 {
            let message = (json["error"] as? [String: Any])?["message"] as? String ?? "fel \(http.statusCode)"
            if http.statusCode == 403 && message.lowercased().contains("insufficient") {
                throw PanelError("Logga in kontot igen i inställningarna, så att panelen får läsa Gmail och kalendern.")
            }
            throw PanelError("Google: \(message)")
        }
        return json
    }

    fileprivate static func randomString(_ n: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<n).map { _ in chars.randomElement()! })
    }

    fileprivate static func formEncode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}

/// Google Tasks, för det konto som är valt för att göra-listan.
enum GoogleTasks {
    private static let base = "https://tasks.googleapis.com/tasks/v1/"

    static func lists(account: String?, clientID: String) async throws -> [(id: String, title: String)] {
        let json = try await Google.request("GET", base + "users/@me/lists?maxResults=100", account: account, clientID: clientID)
        return (json["items"] as? [[String: Any]] ?? []).compactMap { l in
            guard let id = l["id"] as? String else { return nil }
            return (id, l["title"] as? String ?? "")
        }
    }

    static func fetch(account: String?, clientID: String, count: Int) async throws -> [TaskItem] {
        var all: [TaskItem] = []
        for list in try await lists(account: account, clientID: clientID) {
            let json = try await Google.request("GET", base + "lists/\(list.id)/tasks?showCompleted=false&showHidden=false&maxResults=100",
                                                account: account, clientID: clientID)
            for t in json["items"] as? [[String: Any]] ?? [] {
                let title = (t["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard let id = t["id"] as? String, !title.isEmpty else { continue }
                all.append(TaskItem(id: id, listID: list.id, listTitle: list.title, title: title, due: parseDue(t["due"] as? String)))
            }
        }
        // Med datum först (tidigast överst), sedan resten i Googles ordning.
        let dated = all.filter { $0.due != nil }.sorted { $0.due! < $1.due! }
        return Array((dated + all.filter { $0.due == nil }).prefix(max(1, count)))
    }

    static func complete(_ task: TaskItem, account: String?, clientID: String) async throws {
        _ = try await Google.request("PATCH", base + "lists/\(task.listID)/tasks/\(task.id)", account: account, clientID: clientID, body: ["status": "completed"])
    }

    static func add(_ title: String, listTitle: String, account: String?, clientID: String) async throws {
        let id = try await lists(account: account, clientID: clientID).first { $0.title.caseInsensitiveCompare(listTitle) == .orderedSame }?.id ?? "@default"
        _ = try await Google.request("POST", base + "lists/\(id)/tasks", account: account, clientID: clientID, body: ["title": title])
    }

    static func parseDue(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

/// Tar emot svaret från Googles inloggningssida på http://127.0.0.1:8977.
final class LoopbackReceiver {
    private let listener: NWListener
    private var continuation: CheckedContinuation<String, Error>?

    init(port: UInt16) throws {
        listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
    }

    func waitForCode() async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            continuation = cont
            listener.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
            listener.stateUpdateHandler = { [weak self] state in
                if case .failed(let error) = state { self?.finish(.failure(error)) }
            }
            listener.start(queue: .main)
            DispatchQueue.main.asyncAfter(deadline: .now() + 300) { [weak self] in
                self?.finish(.failure(PanelError("Inloggningen tog för lång tid")))
            }
        }
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: .main)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            let request = String(decoding: data ?? Data(), as: UTF8.self)
            let path = request.split(separator: " ").dropFirst().first.map(String.init) ?? ""
            let items = URLComponents(string: "http://localhost\(path)")?.queryItems ?? []
            let code = items.first { $0.name == "code" }?.value
            let error = items.first { $0.name == "error" }?.value
            let text = code != nil ? "Klart! Panelen är kopplad till Google Tasks. Du kan stänga den här fliken." : "Inloggningen avbröts."
            let html = "<html><body style=\"font-family:-apple-system;padding:60px;font-size:20px\">\(text)</body></html>"
            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n\(html)"
            conn.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in conn.cancel() })
            if let code { self?.finish(.success(code)) }
            else if let error { self?.finish(.failure(PanelError("Google: \(error)"))) }
        }
    }

    private func finish(_ result: Result<String, Error>) {
        guard let cont = continuation else { return }
        continuation = nil
        listener.cancel()
        cont.resume(with: result)
    }
}
