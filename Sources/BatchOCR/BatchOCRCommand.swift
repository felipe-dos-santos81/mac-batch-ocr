import ArgumentParser
import Foundation

@main
struct BatchOCRCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "batch-ocr",
        abstract: "Batch OCR images using the Apple Vision framework, writing one .txt per image.",
        version: "1.0.0"
    )

    @Argument(help: "Image files and/or directories to process.")
    var paths: [String] = []

    @Flag(name: .shortAndLong, help: "Automatically detect the language.")
    var detectLanguage = false

    @Option(name: .shortAndLong, help: "Recognition language, repeatable (BCP-47, e.g. en-US). Default: en.")
    var language: [String] = []

    @Flag(name: [.customShort("c"), .long], help: "Enable language correction.")
    var languageCorrection = false

    @Option(name: .shortAndLong, help: "Write all .txt outputs into this directory.")
    var outputDir: String?

    @Flag(name: .shortAndLong, help: "Recurse into subdirectories.")
    var recursive = false

    @Option(name: .shortAndLong, help: "Max concurrent OCR tasks.")
    var jobs: Int = 4

    @Option(help: "Comma-separated image extensions to include when scanning directories.")
    var extensions: String = "png,jpg,jpeg,tif,tiff,heic,webp"

    @Flag(help: "Re-OCR images even if a non-empty .txt output already exists.")
    var overwrite = false

    @Option(help: "Append leveled log lines to this file.")
    var logFile: String?

    @Flag(name: .shortAndLong, help: "Suppress per-file progress lines.")
    var quiet = false

    @Flag(name: .customShort("v"), help: "Show the version.")
    var version = false

    func validate() throws {
        if version {
            throw CleanExit.message(Self.configuration.version)
        }
    }

    mutating func run() async throws {
        let (config, settings) = try makeConfig()
        let files = try discoverFiles(config: config)
        if let dir = config.outputDir {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let reporter = Reporter(quiet: quiet, logFileURL: logFile.map { URL(fileURLWithPath: $0) })
        let processor = BatchProcessor(engine: VisionOCREngine(), settings: settings, config: config, reporter: reporter)
        let start = ContinuousClock.now
        let summary = await processor.run(files: files)
        reporter.summary(summary, elapsed: ContinuousClock.now - start)
        if summary.failed > 0 {
            throw ExitCode(1)
        }
    }

    private func discoverFiles(config: OCRConfig) throws -> [URL] {
        do {
            return try FileDiscovery.discover(paths: paths, recursive: config.recursive, extensions: config.extensions)
        } catch let error as DiscoveryError {
            throw fail(String(describing: error))
        }
    }

    func makeConfig() throws -> (config: OCRConfig, settings: RecognitionSettings) {
        guard !paths.isEmpty else {
            throw fail("No input paths given. Pass image files and/or directories.")
        }
        guard jobs >= 1 else {
            throw fail("--jobs must be >= 1 (got \(jobs)).")
        }
        var config = OCRConfig()
        config.outputDir = outputDir.map { URL(fileURLWithPath: $0) }
        config.recursive = recursive
        config.jobs = jobs
        config.extensions = extensions
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        config.overwrite = overwrite
        var settings = RecognitionSettings()
        if !language.isEmpty {
            settings.languages = language
        }
        settings.usesLanguageCorrection = languageCorrection
        settings.automaticallyDetectsLanguage = detectLanguage
        return (config, settings)
    }

    private func fail(_ message: String) -> ExitCode {
        FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
        return ExitCode(2)
    }
}
