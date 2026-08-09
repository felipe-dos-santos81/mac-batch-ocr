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
    let settings: RecognitionSettings
    let config: OCRConfig
    let reporter: Reporter

    func run(files: [URL]) async -> BatchSummary {
        var summary = BatchSummary()
        var pending = files.makeIterator()

        await withTaskGroup(of: FileResult.self) { group in
            for _ in 0..<max(config.jobs, 1) {
                guard let file = pending.next() else { break }
                group.addTask { await OCRJob(file: file, settings: settings, config: config, engine: engine).run() }
            }
            while let result = await group.next() {
                summary.record(result)
                reporter.progress(result, index: summary.total, count: files.count)
                if let file = pending.next() {
                    group.addTask { await OCRJob(file: file, settings: settings, config: config, engine: engine).run() }
                }
            }
        }
        return summary
    }
}
