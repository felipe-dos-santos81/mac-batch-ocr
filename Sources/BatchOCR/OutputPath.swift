import Foundation

enum OutputPath {
    static func forImage(_ imageURL: URL, outputDir: URL?) -> URL {
        let name = imageURL.deletingPathExtension().lastPathComponent + ".txt"
        let directory = outputDir ?? imageURL.deletingLastPathComponent()
        return directory.appendingPathComponent(name)
    }

    static func hasExistingOutput(at url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int else {
            return false
        }
        return size > 0
    }
}
