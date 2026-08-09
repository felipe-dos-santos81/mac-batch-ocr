import Foundation
import Testing

@testable import BatchOCR

private func makeFakeImage() throws -> (dir: URL, file: URL) {
    let dir = try FixtureFactory.makeTempDirectory()
    let file = dir.appendingPathComponent("img-00.png")
    try Data().write(to: file)
    return (dir, file)
}

@Suite struct OCRJobTests {
    @Test func emptyTextYieldsEmptyOutcome() async throws {
        let (dir, file) = try makeFakeImage()
        defer { try? FileManager.default.removeItem(at: dir) }
        let job = OCRJob(file: file, settings: RecognitionSettings(), config: OCRConfig(), engine: MockEngine(text: ""))
        let result = await job.run()
        guard case .empty = result.outcome else {
            Issue.record("Expected .empty, got \(result.outcome)")
            return
        }
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("img-00.txt").path))
    }

    @Test func failureYieldsFailedOutcome() async throws {
        let (dir, file) = try makeFakeImage()
        defer { try? FileManager.default.removeItem(at: dir) }
        struct FailingEngine: OCREngine {
            func recognize(imageURL: URL, settings: RecognitionSettings) async throws -> String {
                throw OCRError.visionFailed(imageURL, message: "boom")
            }
        }
        let job = OCRJob(file: file, settings: RecognitionSettings(), config: OCRConfig(), engine: FailingEngine())
        let result = await job.run()
        guard case .failed(let message) = result.outcome else {
            Issue.record("Expected .failed, got \(result.outcome)")
            return
        }
        #expect(message.contains("boom"))
    }

    @Test func skipsExistingNonEmptyOutput() async throws {
        let (dir, file) = try makeFakeImage()
        defer { try? FileManager.default.removeItem(at: dir) }
        let output = dir.appendingPathComponent("img-00.txt")
        try "previous".write(to: output, atomically: true, encoding: .utf8)
        let job = OCRJob(file: file, settings: RecognitionSettings(), config: OCRConfig(), engine: MockEngine(text: "new"))
        let result = await job.run()
        guard case .skipped = result.outcome else {
            Issue.record("Expected .skipped, got \(result.outcome)")
            return
        }
        #expect(try String(contentsOf: output, encoding: .utf8) == "previous")
    }
}
