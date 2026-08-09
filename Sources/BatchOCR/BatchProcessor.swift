import Foundation

struct FileResult: Sendable {
    enum Outcome: Sendable {
        case ok(output: URL)
        case skipped(output: URL)
        case empty
        case failed(message: String)
    }

    let input: URL
    let outcome: Outcome
}

struct BatchSummary: Sendable {
    var ok = 0
    var skipped = 0
    var empty = 0
    var failed = 0

    var total: Int { ok + skipped + empty + failed }

    mutating func record(_ result: FileResult) {
        switch result.outcome {
        case .ok: ok += 1
        case .skipped: skipped += 1
        case .empty: empty += 1
        case .failed: failed += 1
        }
    }
}

struct BatchProcessor: Sendable {
    let engine: any OCREngine
    let config: OCRConfig
    let reporter: Reporter

    func run(files: [URL]) async -> BatchSummary {
        var summary = BatchSummary()
        for (index, file) in files.enumerated() {
            let result = await process(file)
            summary.record(result)
            reporter.progress(result, index: index + 1, count: files.count)
        }
        return summary
    }

    private func process(_ file: URL) async -> FileResult {
        let output = OutputPath.forImage(file, outputDir: config.outputDir)
        if !config.overwrite && OutputPath.hasExistingOutput(at: output) {
            return FileResult(input: file, outcome: .skipped(output: output))
        }
        do {
            let text = try await engine.recognize(imageURL: file, config: config)
            guard !text.isEmpty else {
                return FileResult(input: file, outcome: .empty)
            }
            try text.write(to: output, atomically: true, encoding: .utf8)
            return FileResult(input: file, outcome: .ok(output: output))
        } catch {
            return FileResult(input: file, outcome: .failed(message: String(describing: error)))
        }
    }
}
