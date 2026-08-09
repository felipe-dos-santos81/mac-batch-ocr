import Foundation

struct OCRJob: Sendable {
    let file: URL
    let settings: RecognitionSettings
    let config: OCRConfig
    let engine: any OCREngine

    func run() async -> FileResult {
        let output = OutputPath.forImage(file, outputDir: config.outputDir)
        if !config.overwrite && OutputPath.hasExistingOutput(at: output) {
            return FileResult(input: file, outcome: .skipped(output: output))
        }
        do {
            let text = try await engine.recognize(imageURL: file, settings: settings)
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
