import Foundation
import Testing

@testable import BatchOCR

@Test func recognizesRenderedText() async throws {
    let image = try FixtureFactory.renderPNG(text: "BATCH OCR 2026")
    defer { try? FileManager.default.removeItem(at: image) }
    let text = try await VisionOCREngine().recognize(imageURL: image, settings: RecognitionSettings())
    #expect(text.contains("BATCH OCR 2026"))
}

@Test func imageWithoutTextReturnsEmptyString() async throws {
    let image = try FixtureFactory.renderPNG(text: " ")
    defer { try? FileManager.default.removeItem(at: image) }
    let text = try await VisionOCREngine().recognize(imageURL: image, settings: RecognitionSettings())
    #expect(text.isEmpty)
}

@Test func missingFileThrowsFileNotFound() async {
    let missing = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).png")
    do {
        _ = try await VisionOCREngine().recognize(imageURL: missing, settings: RecognitionSettings())
        Issue.record("Expected OCRError.fileNotFound")
    } catch let error as OCRError {
        guard case .fileNotFound = error else {
            Issue.record("Expected .fileNotFound, got \(error)")
            return
        }
    } catch {
        Issue.record("Expected OCRError, got \(error)")
    }
}
