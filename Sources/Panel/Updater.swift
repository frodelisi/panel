import Foundation

/// Hämtar nya versioner från GitHub (frodelisi/panel), bygger om och startar om panelen.
/// installera.command sparar var mappen ligger; finns den inte görs ingenting.
enum Updater {
    private static var pathFile: URL { Config.folder.appendingPathComponent("repo-path") }
    private static var versionFile: URL { Config.folder.appendingPathComponent("version") }

    static var repoPath: String? {
        guard let s = try? String(contentsOf: pathFile, encoding: .utf8) else { return nil }
        let path = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return FileManager.default.fileExists(atPath: path + "/.git") ? path : nil
    }

    /// "24 nov 22:58 · Kugghjulet öppnar chatten" – skrivs av installera.command.
    static var version: String {
        (try? String(contentsOf: versionFile, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Senaste installationen var den senaste dygnet?
    static var updatedRecently: Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: versionFile.path),
              let date = attrs[.modificationDate] as? Date else { return false }
        return Date().timeIntervalSince(date) < 24 * 3600
    }

    static func check() {
        guard let repo = repoPath else { return }
        let quoted = "'" + repo.replacingOccurrences(of: "'", with: "'\\''") + "'"
        // Bygget görs innan den gamla panelen stängs, så misslyckas det fortsätter den gamla att gå.
        let script = """
        cd \(quoted) || exit 0
        git fetch -q origin 2>/dev/null || exit 0
        [ "$(git rev-parse HEAD)" = "$(git rev-parse @{u})" ] && exit 0
        git pull -q --ff-only && ./installera.command --tyst > /tmp/panel-uppdatering.log 2>&1
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
        process.arguments = ["/bin/zsh", "-c", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}
