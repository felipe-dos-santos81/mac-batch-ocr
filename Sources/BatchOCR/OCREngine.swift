import Foundation
import Vision

protocol OCREngine: Sendable {
    func recognize(imageURL: URL, config: OCRConfig) async throws -> String
}

enum OCRError: Error, CustomStringConvertible {
    case fileNotFound(URL)
    case pathNotFound(String)
    case visionFailed(URL, message: String)

    var description: String {
        switch self {
        case .fileNotFound(let url):
            "File not found: \(url.path)"
        case .pathNotFound(let path):
            "Path not found: \(path)"
        case .visionFailed(let url, let message):
            "Vision failed for \(url.path): \(message)"
        }
    }
}

struct VisionOCREngine: OCREngine {
    func recognize(imageURL: URL, config: OCRConfig) async throws -> String {
        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            throw OCRError.fileNotFound(imageURL)
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = config.languages
        request.usesLanguageCorrection = config.usesLanguageCorrection
        request.automaticallyDetectsLanguage = config.automaticallyDetectsLanguage
        let handler = VNImageRequestHandler(url: imageURL)
        do {
            try handler.perform([request])
        } catch {
            throw OCRError.visionFailed(imageURL, message: String(describing: error))
        }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }
}
