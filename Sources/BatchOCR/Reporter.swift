import Foundation

struct Reporter: Sendable {
    let quiet: Bool

    func progress(_ result: FileResult, index: Int, count: Int) {
        switch result.outcome {
        case .ok:
            announce(index: index, count: count, label: "ok", path: result.input.path)
        case .skipped:
            announce(index: index, count: count, label: "skip", path: result.input.path)
        case .empty:
            announce(index: index, count: count, label: "empty", path: result.input.path)
        case .failed(let message):
            FileHandle.standardError.write(Data("fail: \(result.input.path): \(message)\n".utf8))
        }
    }

    func summary(_ summary: BatchSummary, elapsed: Duration) {
        let seconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1e18
        print("done=\(summary.ok) skipped=\(summary.skipped) empty=\(summary.empty) failed=\(summary.failed) elapsed=\(String(format: "%.1f", seconds))s")
    }

    private func announce(index: Int, count: Int, label: String, path: String) {
        guard !quiet else { return }
        print("[\(index)/\(count)] \(label) \(path)")
    }
}
