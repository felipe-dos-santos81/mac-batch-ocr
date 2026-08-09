import Foundation
import Testing

@testable import BatchOCR

actor InFlightTracker {
    private(set) var current = 0
    private(set) var peak = 0

    func enter() {
        current += 1
        peak = max(peak, current)
    }

    func leave() {
        current -= 1
    }
}

struct MockEngine: OCREngine {
    var tracker: InFlightTracker? = nil
    var text = "mock text"
    var delay: Duration = .zero

    func recognize(imageURL: URL, config: OCRConfig) async throws -> String {
        if let tracker {
            await tracker.enter()
        }
        if delay > .zero {
            try? await Task.sleep(for: delay)
        }
        if let tracker {
            await tracker.leave()
        }
        return text
    }
}

private func makeFakeImages(count: Int) throws -> (dir: URL, files: [URL]) {
    let dir = try FixtureFactory.makeTempDirectory()
    var files: [URL] = []
    for i in 0..<count {
        let url = dir.appendingPathComponent(String(format: "img-%02d.png", i))
        try Data().write(to: url)
        files.append(url)
    }
    return (dir, files)
}

@Test func writesOutputBesideImage() async throws {
    let (dir, files) = try makeFakeImages(count: 1)
    defer { try? FileManager.default.removeItem(at: dir) }
    let processor = BatchProcessor(
        engine: MockEngine(),
        config: OCRConfig(),
        reporter: Reporter(quiet: true)
    )
    let summary = await processor.run(files: files)
    #expect(summary.ok == 1)
    let output = dir.appendingPathComponent("img-00.txt")
    #expect(try String(contentsOf: output, encoding: .utf8) == "mock text")
}

@Test func routesOutputToOutputDir() async throws {
    let (dir, files) = try makeFakeImages(count: 1)
    let outDir = try FixtureFactory.makeTempDirectory()
    defer {
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.removeItem(at: outDir)
    }
    var config = OCRConfig()
    config.outputDir = outDir
    let processor = BatchProcessor(
        engine: MockEngine(),
        config: config,
        reporter: Reporter(quiet: true)
    )
    _ = await processor.run(files: files)
    #expect(FileManager.default.fileExists(atPath: outDir.appendingPathComponent("img-00.txt").path))
}

@Test func skipsExistingOutputUnlessOverwrite() async throws {
    let (dir, files) = try makeFakeImages(count: 1)
    defer { try? FileManager.default.removeItem(at: dir) }
    let output = dir.appendingPathComponent("img-00.txt")
    try "previous".write(to: output, atomically: true, encoding: .utf8)

    let skipProcessor = BatchProcessor(
        engine: MockEngine(),
        config: OCRConfig(),
        reporter: Reporter(quiet: true)
    )
    let skipSummary = await skipProcessor.run(files: files)
    #expect(skipSummary.skipped == 1)
    #expect(try String(contentsOf: output, encoding: .utf8) == "previous")

    var config = OCRConfig()
    config.overwrite = true
    let overwriteProcessor = BatchProcessor(
        engine: MockEngine(),
        config: config,
        reporter: Reporter(quiet: true)
    )
    let overwriteSummary = await overwriteProcessor.run(files: files)
    #expect(overwriteSummary.ok == 1)
    #expect(try String(contentsOf: output, encoding: .utf8) == "mock text")
}

@Test func failureDoesNotAbortBatch() async throws {
    let (dir, files) = try makeFakeImages(count: 2)
    defer { try? FileManager.default.removeItem(at: dir) }
    struct FailingEngine: OCREngine {
        let failing: URL
        func recognize(imageURL: URL, config: OCRConfig) async throws -> String {
            if imageURL == failing {
                throw OCRError.visionFailed(imageURL, message: "boom")
            }
            return "ok"
        }
    }
    let processor = BatchProcessor(
        engine: FailingEngine(failing: files[0]),
        config: OCRConfig(),
        reporter: Reporter(quiet: true)
    )
    let summary = await processor.run(files: files)
    #expect(summary.ok == 1)
    #expect(summary.failed == 1)
}
