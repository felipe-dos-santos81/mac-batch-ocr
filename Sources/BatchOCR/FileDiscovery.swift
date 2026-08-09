import Foundation

enum FileDiscovery {
    static func discover(paths: [String], recursive: Bool, extensions: [String]) throws -> [URL] {
        let allowed = Set(extensions.map { $0.lowercased() })
        var seen = Set<String>()
        var files: [URL] = []
        let fileManager = FileManager.default

        func add(_ url: URL) {
            let standardized = url.standardizedFileURL
            if seen.insert(standardized.path).inserted {
                files.append(standardized)
            }
        }

        for path in paths {
            let url = URL(fileURLWithPath: path)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                throw OCRError.pathNotFound(path)
            }
            if isDirectory.boolValue {
                let candidates: [URL]
                if recursive {
                    candidates = fileManager.enumerator(at: url, includingPropertiesForKeys: nil)?
                        .compactMap { $0 as? URL } ?? []
                } else {
                    candidates = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                }
                for candidate in candidates where allowed.contains(candidate.pathExtension.lowercased()) {
                    add(candidate)
                }
            } else {
                add(url)
            }
        }
        return files.sorted { $0.path < $1.path }
    }
}
