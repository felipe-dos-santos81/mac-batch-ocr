import Foundation

struct Reporter: Sendable {
    let quiet: Bool
    var logFileURL: URL? = nil

    func progress(_ result: FileResult, index: Int, count: Int) {
        switch result.outcome {
        case .ok(let output):
            announce(index: index, count: count, label: "ok", path: result.input.path)
            log("INFO", "ok: \(result.input.path) -> \(output.path)")
        case .skipped(let output):
            announce(index: index, count: count, label: "skip", path: result.input.path)
            log("INFO", "skip: \(result.input.path) (output exists: \(output.path))")
        case .empty:
            announce(index: index, count: count, label: "empty", path: result.input.path)
            log("WARN", "empty: \(result.input.path) (no text recognized)")
        case .failed(let message):
            FileHandle.standardError.write(Data("fail: \(result.input.path): \(message)\n".utf8))
            log("ERROR", "fail: \(result.input.path): \(message)")
        }
    }

    func summary(_ summary: BatchSummary, elapsed: Duration) {
        let seconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1e18
        let line = "done=\(summary.ok) skipped=\(summary.skipped) empty=\(summary.empty) failed=\(summary.failed) elapsed=\(String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), seconds))s"
        print(line)
        log("INFO", line)
    }

    private func announce(index: Int, count: Int, label: String, path: String) {
        guard !quiet else { return }
        print("[\(index)/\(count)] \(label) \(path)")
    }

    private func log(_ level: String, _ message: String) {
        guard let url = logFileURL else { return }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let line = "\(formatter.string(from: Date())) [\(level)] \(message)\n"
        append(line, to: url)
    }

    private func append(_ line: String, to url: URL) {
        do {
            if !FileManager.default.fileExists(atPath: url.path) {
                try line.write(to: url, atomically: true, encoding: .utf8)
                return
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
        } catch {
            FileHandle.standardError.write(Data("warn: could not write log file: \(error)\n".utf8))
        }
    }
}
