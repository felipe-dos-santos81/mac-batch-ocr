import Foundation

final class StandardOutput: TextOutputStream, @unchecked Sendable {
    func write(_ string: String) {
        FileHandle.standardOutput.write(Data(string.utf8))
    }
}

final class StandardError: TextOutputStream, @unchecked Sendable {
    func write(_ string: String) {
        FileHandle.standardError.write(Data(string.utf8))
    }
}

struct Reporter: Sendable {
    let quiet: Bool
    var logFileURL: URL?
    var out: any TextOutputStream & Sendable
    var err: any TextOutputStream & Sendable

    init(
        quiet: Bool,
        logFileURL: URL? = nil,
        out: any TextOutputStream & Sendable = StandardOutput(),
        err: any TextOutputStream & Sendable = StandardError()
    ) {
        self.quiet = quiet
        self.logFileURL = logFileURL
        self.out = out
        self.err = err
    }

    func progress(_ result: FileResult, index: Int, count: Int) {
        switch result.outcome {
        case .ok(let output):
            announce(Self.progressLine(index: index, count: count, label: "ok", path: result.input.path))
            log("INFO", "ok: \(result.input.path) -> \(output.path)")
        case .skipped(let output):
            announce(Self.progressLine(index: index, count: count, label: "skip", path: result.input.path))
            log("INFO", "skip: \(result.input.path) (output exists: \(output.path))")
        case .empty:
            announce(Self.progressLine(index: index, count: count, label: "empty", path: result.input.path))
            log("WARN", "empty: \(result.input.path) (no text recognized)")
        case .failed(let message):
            write("fail: \(result.input.path): \(message)", to: err)
            log("ERROR", "fail: \(result.input.path): \(message)")
        }
    }

    func summary(_ summary: BatchSummary, elapsed: Duration) {
        let line = Self.summaryLine(summary: summary, elapsed: elapsed)
        write(line, to: out)
        log("INFO", line)
    }

    static func progressLine(index: Int, count: Int, label: String, path: String) -> String {
        "[\(index)/\(count)] \(label) \(path)"
    }

    static func summaryLine(summary: BatchSummary, elapsed: Duration) -> String {
        let seconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1e18
        return "done=\(summary.ok) skipped=\(summary.skipped) empty=\(summary.empty) failed=\(summary.failed) elapsed=\(String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), seconds))s"
    }

    static func logLine(level: String, message: String, now: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return "\(formatter.string(from: now)) [\(level)] \(message)\n"
    }

    private func announce(_ line: String) {
        guard !quiet else { return }
        write(line, to: out)
    }

    private func log(_ level: String, _ message: String) {
        guard let url = logFileURL else { return }
        let line = Self.logLine(level: level, message: message, now: Date())
        append(line, to: url)
    }

    private func write(_ line: String, to sink: any TextOutputStream & Sendable) {
        var s = sink
        s.write(line + "\n")
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
