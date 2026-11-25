import AppKit
import Foundation

// MARK: - Väder (Open-Meteo: gratis, ingen nyckel)

struct WeatherHour: Hashable {
    var hour: String        // "14"
    var temp: Int
    var symbol: String
}

struct WeatherNow: Hashable {
    var place: String
    var temp: Int
    var text: String
    var symbol: String
    var high: Int
    var low: Int
    var hours: [WeatherHour]
}

enum WeatherSource {
    private static var place: (city: String, name: String, lat: Double, lon: Double)?

    static func fetch(city: String) async throws -> WeatherNow {
        let city = city.trimmingCharacters(in: .whitespaces).isEmpty ? "Stockholm" : city.trimmingCharacters(in: .whitespaces)
        if place?.city != city {
            var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
            c.queryItems = [URLQueryItem(name: "name", value: city), URLQueryItem(name: "count", value: "1"), URLQueryItem(name: "language", value: "sv")]
            let json = try await getJSON(c.url!)
            guard let r = (json["results"] as? [[String: Any]])?.first,
                  let lat = r["latitude"] as? Double, let lon = r["longitude"] as? Double else {
                throw PanelError("Hittar inte \(city). Skriv en annan stad i inställningarna.")
            }
            place = (city, r["name"] as? String ?? city, lat, lon)
        }
        guard let p = place else { throw PanelError("Ingen plats") }

        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            URLQueryItem(name: "latitude", value: "\(p.lat)"),
            URLQueryItem(name: "longitude", value: "\(p.lon)"),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "2"),
        ]
        let json = try await getJSON(c.url!)
        let current = json["current"] as? [String: Any] ?? [:]
        let code = current["weather_code"] as? Int ?? 0
        let day = (current["is_day"] as? Int ?? 1) == 1
        let daily = json["daily"] as? [String: Any] ?? [:]
        let high = (daily["temperature_2m_max"] as? [Double])?.first ?? 0
        let low = (daily["temperature_2m_min"] as? [Double])?.first ?? 0

        // De kommande timmarna (från nästa hela timme).
        let hourly = json["hourly"] as? [String: Any] ?? [:]
        let times = hourly["time"] as? [String] ?? []
        let temps = hourly["temperature_2m"] as? [Double] ?? []
        let codes = hourly["weather_code"] as? [Int] ?? []
        let days = hourly["is_day"] as? [Int] ?? []
        let local = DateFormatter()
        local.dateFormat = "yyyy-MM-dd'T'HH:mm"
        if let tz = json["timezone"] as? String { local.timeZone = TimeZone(identifier: tz) }
        var hours: [WeatherHour] = []
        for i in times.indices where hours.count < 5 {
            guard let t = local.date(from: times[i]), t > Date(), i < temps.count, i < codes.count else { continue }
            let isDay = i < days.count ? days[i] == 1 : true
            hours.append(WeatherHour(hour: String(times[i].suffix(5).prefix(2)), temp: Int(temps[i].rounded()), symbol: symbol(codes[i], day: isDay)))
        }

        return WeatherNow(place: p.name, temp: Int((current["temperature_2m"] as? Double ?? 0).rounded()),
                          text: text(code), symbol: symbol(code, day: day),
                          high: Int(high.rounded()), low: Int(low.rounded()), hours: hours)
    }

    private static func getJSON(_ url: URL) async throws -> [String: Any] {
        let (data, _) = try await URLSession.shared.data(from: url)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// WMO-väderkoder → SF Symbols.
    static func symbol(_ code: Int, day: Bool) -> String {
        switch code {
        case 0: return day ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return day ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 80...82: return "cloud.heavyrain.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    static func text(_ code: Int) -> String {
        switch code {
        case 0: return "Klart"
        case 1: return "Mest klart"
        case 2: return "Halvklart"
        case 3: return "Mulet"
        case 45, 48: return "Dimma"
        case 51...57: return "Duggregn"
        case 61...67: return "Regn"
        case 71...77: return "Snö"
        case 80...82: return "Regnskurar"
        case 85, 86: return "Snöbyar"
        case 95...99: return "Åska"
        default: return ""
        }
    }
}

// MARK: - Musik (Spotify eller Musik-appen)

struct MusicNow: Hashable {
    var app: String         // "Spotify" eller "Music"
    var playing: Bool
    var title: String
    var artist: String
    var artwork: URL?
}

enum MusicSource {
    private static let queue = DispatchQueue(label: "panel.music")
    private static var hasSpotify: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") != nil
    }

    static func fetch() async -> MusicNow? {
        let spotify = hasSpotify ? """
        if application "Spotify" is running then
            tell application "Spotify"
                set s to player state as string
                if s is "stopped" then return "Spotify" & tab & s & tab & "" & tab & "" & tab & ""
                set t to current track
                return "Spotify" & tab & s & tab & (name of t) & tab & (artist of t) & tab & (artwork url of t)
            end tell
        end if
        """ : ""
        let script = spotify + """

        if application "Music" is running then
            tell application "Music"
                set s to player state as string
                if s is "stopped" then return "Music" & tab & s & tab & "" & tab & "" & tab & ""
                set t to current track
                return "Music" & tab & s & tab & (name of t) & tab & (artist of t) & tab & ""
            end tell
        end if
        return ""
        """
        let out = await run(script)
        let f = out.components(separatedBy: "\t")
        guard f.count >= 5, !f[2].isEmpty else { return nil }
        return MusicNow(app: f[0], playing: f[1] == "playing", title: f[2], artist: f[3], artwork: URL(string: f[4]))
    }

    static func command(_ command: String, app: String) async {
        _ = await run("tell application \"\(app)\" to \(command)")
    }

    static func openSpotify() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Music.app"))
        }
    }

    private static func run(_ source: String) async -> String {
        await withCheckedContinuation { cont in
            queue.async {
                var error: NSDictionary?
                let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
                cont.resume(returning: result?.stringValue ?? "")
            }
        }
    }
}

// MARK: - Ekonomi (från dashboarden på Mac minin)

struct EconomyNow: Hashable {
    struct Goal: Hashable { var name: String; var saved: Double; var target: Double? }
    var pott: Double?           // lön + CSN − fasta poster, när lönen är ifylld
    var month: String
    var goals: [Goal]
    var subscriptions: Double
}

enum EconomySource {
    static func fetch(base: String) async throws -> EconomyNow {
        let b = base.trimmingCharacters(in: .whitespaces)
        guard !b.isEmpty else { throw PanelError("Skriv in dashboardens adress i inställningarna") }
        guard let password = Keychain.get("dashboard.password") else { throw PanelError("Skriv in dashboardens lösenord i inställningarna") }
        guard let url = URL(string: (b.hasPrefix("http") ? b : "http://" + b) + "/api/all") else { throw PanelError("Fel adress till dashboarden") }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("Basic " + Data("panel:\(password)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 401 { throw PanelError("Fel lösenord till dashboarden") }
        let all = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let e = all["ekonomi"] as? [String: Any] ?? [:]
        let manad = e["manad"] as? [String: Any] ?? [:]
        let fixed = ((e["regel"] as? [String: Any])?["fordelning"] as? [[String: Any]] ?? []).reduce(0.0) { $0 + (($1["belopp"] as? NSNumber)?.doubleValue ?? 0) }
        let lon = (manad["lon"] as? NSNumber)?.doubleValue
        let csn = (manad["csn"] as? NSNumber)?.doubleValue ?? 0
        let goals = (e["sparmal"] as? [[String: Any]] ?? []).map {
            EconomyNow.Goal(name: $0["namn"] as? String ?? "", saved: ($0["sparat"] as? NSNumber)?.doubleValue ?? 0, target: ($0["mal"] as? NSNumber)?.doubleValue)
        }
        let subs = (e["prenumerationer"] as? [[String: Any]] ?? []).reduce(0.0) { $0 + (($1["pris"] as? NSNumber)?.doubleValue ?? 0) }
        return EconomyNow(pott: lon.map { $0 + csn - fixed }, month: Date().formatted(.dateTime.month(.wide)), goals: goals, subscriptions: subs)
    }
}

/// "6 150 kr"
func kronor(_ v: Double?) -> String {
    guard let v else { return "–" }
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.locale = Locale(identifier: "sv_SE")
    f.maximumFractionDigits = 0
    return (f.string(from: NSNumber(value: v)) ?? "\(Int(v))") + " kr"
}
