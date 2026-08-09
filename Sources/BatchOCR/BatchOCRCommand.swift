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

    mutating func run() async throws {
        if version {
            print(Self.configuration.version)
            return
        }
        print("batch-ocr: scaffold only; OCR wiring lands in milestone M2.")
    }
}
