import Foundation

enum DocumentScanner {
    static let ignoredDirectories: Set<String> = ["Containers", "Staging", "Library", "Box64", "Wine", "Graphics"]
    static let interestingExtensions: Set<String> = [
        "exe", "msi", "zip", "rar", "7z", "iso", "bin", "dll",
        "conf", "cfg", "ini", "dat", "cab", "jar", "pak", "pkg"
    ]

    static var gamesFolder: URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let games = docs.appendingPathComponent("games")
        try? FileManager.default.createDirectory(at: games, withIntermediateDirectories: true)
        return games
    }

    static func contents() -> [URL] {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return [] }

        var results: [URL] = []

        if let gamesDir = gamesFolder,
           let entries = try? fm.contentsOfDirectory(at: gamesDir, includingPropertiesForKeys: [.isDirectoryKey]) {
            results.append(contentsOf: entries)
        }

        let inbox = docs.appendingPathComponent("Inbox")
        if let entries = try? fm.contentsOfDirectory(at: inbox, includingPropertiesForKeys: [.isDirectoryKey]) {
            results.append(contentsOf: entries)
        }

        if let entries = try? fm.contentsOfDirectory(at: docs, includingPropertiesForKeys: [.isDirectoryKey]) {
            for url in entries where !ignoredDirectories.contains(url.lastPathComponent) {
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
                let isDir = values?.isDirectory ?? false
                if isDir {
                    results.append(url)
                } else {
                    let ext = url.pathExtension.lowercased()
                    if interestingExtensions.contains(ext) {
                        results.append(url)
                    }
                }
            }
        }

        var seen = Set<String>()
        return results
            .filter { seen.insert($0.path).inserted }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }
}
