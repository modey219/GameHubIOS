import UIKit
import UniformTypeIdentifiers

enum DocumentScanner {
    static let ignoredDirectories: Set<String> = ["Containers", "Staging", "Library", "Inbox"]

    static func contents() -> [URL] {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return [] }

        var results: [URL] = []
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]

        guard let enumerator = fm.enumerator(
            at: docs,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        for case let url as URL in enumerator {
            let parent = url.deletingLastPathComponent().lastPathComponent
            if ignoredDirectories.contains(parent) || ignoredDirectories.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isDir = values?.isDirectory ?? false

            if isDir {
                results.append(url)
            } else {
                let ext = url.pathExtension.lowercased()
                let interesting = [ "exe", "msi", "zip", "rar", "7z", "iso", "bin", "dll",
                                    "conf", "cfg", "ini", "dat", "cab", "jar", "pak", "pkg" ]
                if interesting.contains(ext) {
                    results.append(url)
                }
            }
            if results.count >= 200 { break }
        }

        return results.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }
}
