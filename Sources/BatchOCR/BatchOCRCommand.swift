import ArgumentParser
import Foundation

@main
struct BatchOCRCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "batch-ocr",
        abstract: "Batch OCR images using the Apple Vision framework, writing one .txt per image.",
        version: "0.1.0"
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
        let config = try makeConfig()
        guard paths.count == 1 else {
            throw configError("This milestone accepts exactly one image file; batch support lands in M3.")
        }
        let url = URL(fileURLWithPath: paths[0])
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw configError("Not an existing path: \(paths[0])")
        }
        guard !isDirectory.boolValue else {
            throw configError("Directories are not supported yet (lands in M3): \(paths[0])")
        }
        if let dir = config.outputDir {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let text = try await VisionOCREngine().recognize(imageURL: url, config: config)
        guard !text.isEmpty else {
            FileHandle.standardError.write(Data("warn: no text recognized in \(url.path)\n".utf8))
            return
        }
        try text.write(to: OutputPath.forImage(url, outputDir: config.outputDir), atomically: true, encoding: .utf8)
    }

    func makeConfig() throws -> OCRConfig {
        guard !paths.isEmpty else {
            throw configError("No input paths given. Pass image files and/or directories.")
        }
        guard jobs >= 1 else {
            throw configError("--jobs must be >= 1 (got \(jobs)).")
        }
        var config = OCRConfig()
        if !language.isEmpty {
            config.languages = language
        }
        config.usesLanguageCorrection = languageCorrection
        config.automaticallyDetectsLanguage = detectLanguage
        config.outputDir = outputDir.map { URL(fileURLWithPath: $0) }
        config.recursive = recursive
        config.jobs = jobs
        config.extensions = extensions
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        config.overwrite = overwrite
        return config
    }

    private func configError(_ message: String) -> ExitCode {
        FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
        return ExitCode(2)
    }
}
