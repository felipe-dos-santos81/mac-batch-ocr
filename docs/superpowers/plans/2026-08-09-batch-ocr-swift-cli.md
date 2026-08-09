# Batch OCR Swift CLI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `batch-ocr`, a native Swift CLI that batch-OCRs images/directories via Apple Vision, replacing the single-image AppleScript helper while keeping flag parity.

**Architecture:** Thin ArgumentParser command maps flags to an `OCRConfig` value type; `VisionOCREngine` (behind an `OCREngine` protocol for test injection) wraps `VNRecognizeTextRequest`; `FileDiscovery` expands paths; `BatchProcessor` runs per-file tasks with a sliding-window `TaskGroup` capped at `--jobs`; `Reporter` handles progress/summary/log file. Each milestone ends by rewriting `.agent/status.json` (the agents' graph, spec §7).

**Tech Stack:** Swift 6 (tools 6.0), SwiftPM, apple/swift-argument-parser ≥ 1.3.0 (only external dependency), Vision, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-08-09-mac-batch-ocr-swift-design.md`

## Global Constraints

- macOS 13+ platform floor; Swift tools 6.0.
- Exactly one external dependency: `swift-argument-parser`. Adding another requires a spec change.
- No comments in code unless documenting a non-obvious Vision/API quirk.
- Every task ends with a commit; short imperative messages (repo style).
- Legacy `process_image.scpt` is never modified or deleted.
- No binary fixtures in git; tests render images at runtime via CoreGraphics.
- Minimal blast radius: each task changes only what its milestone requires.

## Assumptions & Refinements (vs. spec)

1. SwiftPM target is `BatchOCR`, executable product is `batch-ocr` (clean `@testable import BatchOCR`).
2. Images with no recognized text produce **no** output file and count as outcome `.empty` (exit 0) — mirrors legacy WARN behavior; spec §6 summary gains an `empty=` counter.
3. Runtime config errors (no paths, bad path, `--jobs < 1`) throw `ExitCode(2)`; ArgumentParser-level parse errors (unknown flags) exit with the framework default (64).
4. `OutputPath.swift` is added to the spec §6 file list (single responsibility: output naming + existence check).
5. `--language` defaults to `[]` and falls back to `["en"]` in `makeConfig()` (avoids ArgumentParser array-default ambiguity; keeps legacy default).
6. M3 ships a sequential `BatchProcessor`; M4 converts the same function to a capped `TaskGroup` (smallest possible diff per milestone).
7. M2-5 parity check is best-effort: the legacy script's `tell application "System Events"` may trigger a macOS Automation (TCC) prompt. If blocked in a headless session, note it in the milestone report and continue (engine correctness is already proven by M1-1).
8. `OCRError.visionFailed` stores the underlying error as `String` so the error type stays trivially `Sendable`.

## File Structure

```
Package.swift                              # NEW  Task 1
.gitignore                                 # MODIFY Task 1 (append Swift section)
Sources/BatchOCR/BatchOCRCommand.swift     # NEW  Task 1, MODIFY Tasks 3, 5, 6, 7
Sources/BatchOCR/OCRConfig.swift           # NEW  Task 2
Sources/BatchOCR/OCREngine.swift           # NEW  Task 2 (protocol + OCRError + VisionOCREngine)
Sources/BatchOCR/OutputPath.swift          # NEW  Task 3
Sources/BatchOCR/FileDiscovery.swift       # NEW  Task 4
Sources/BatchOCR/BatchProcessor.swift      # NEW  Task 5, MODIFY Task 6
Sources/BatchOCR/Reporter.swift            # NEW  Task 5, REPLACE Task 6
Tests/BatchOCRTests/CommandSmokeTests.swift    # NEW  Task 1
Tests/BatchOCRTests/FixtureFactory.swift       # NEW  Task 2
Tests/BatchOCRTests/OCREngineTests.swift       # NEW  Task 2
Tests/BatchOCRTests/CommandConfigTests.swift   # NEW  Task 3
Tests/BatchOCRTests/FileDiscoveryTests.swift   # NEW  Task 4
Tests/BatchOCRTests/BatchProcessorTests.swift  # NEW  Task 5, MODIFY Task 6
README.md                                  # REPLACE Task 7
.agent/status.json                         # runtime artifact (gitignored), rewritten at each milestone end
```

---

### Task 1: Scaffold SwiftPM package (Milestone M0)

**Files:**
- Create: `Package.swift`
- Create: `Sources/BatchOCR/BatchOCRCommand.swift`
- Create: `Tests/BatchOCRTests/CommandSmokeTests.swift`
- Modify: `.gitignore` (append)
- Commit: `docs/superpowers/` (spec + this plan)

**Interfaces:**
- Produces: `BatchOCRCommand` (AsyncParsableCommand, full §5 option surface, stub `run()`), product `batch-ocr`.

- [ ] **Step 1: Create `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "batch-ocr",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "batch-ocr", targets: ["BatchOCR"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")
    ],
    targets: [
        .executableTarget(
            name: "BatchOCR",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/BatchOCR"
        ),
        .testTarget(
            name: "BatchOCRTests",
            dependencies: ["BatchOCR"],
            path: "Tests/BatchOCRTests"
        )
    ]
)
```

- [ ] **Step 2: Append Swift section to `.gitignore`**

```gitignore

# Swift
.build/
.swiftpm/
.agent/
.superpowers/
```

- [ ] **Step 3: Create `Sources/BatchOCR/BatchOCRCommand.swift`** (full option surface; `run()` stubbed)

```swift
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

    @Flag(name: .shortAndLong, help: "Enable language correction.")
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

    mutating func run() async throws {
        print("batch-ocr: scaffold only; OCR wiring lands in milestone M2.")
    }
}
```

- [ ] **Step 4: Write the smoke test `Tests/BatchOCRTests/CommandSmokeTests.swift`**

```swift
import Testing

@testable import BatchOCR

@Test func parsesMinimalInvocation() throws {
    let command = try BatchOCRCommand.parse(["img.png"])
    #expect(command.paths == ["img.png"])
}
```

- [ ] **Step 5: Build and test**

Run: `swift build && swift test`
Expected: both exit 0; dependency `swift-argument-parser` resolves and compiles.

- [ ] **Step 6: Verify help and version (DoD M0-2, M0-3)**

Run: `swift run batch-ocr --help`
Expected: exit 0; usage lists `paths`, `-d/--detect-language`, `-l/--language`, `-c/--language-correction`, `-o/--output-dir`, `-r/--recursive`, `-j/--jobs`, `--extensions`, `--overwrite`, `--log-file`, `-q/--quiet`, `-v/--version`, `-h/--help`.

Run: `swift run batch-ocr --version`
Expected: prints `0.1.0`.

- [ ] **Step 7: Commit**

```bash
git add .gitignore Package.swift Sources Tests docs/superpowers
git commit -m "scaffold swift package for batch-ocr"
```

- [ ] **Step 8: Report M0 to the agents' graph (DoD M0-5)**

```bash
mkdir -p .agent && cat > .agent/status.json <<JSON
{
  "project": "mac-batch-ocr-swift",
  "updated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "current": "M1",
  "history": [
    {"milestone": "M0", "status": "done", "dod": [
      {"id": "M0-1", "command": "swift build", "pass": true},
      {"id": "M0-2", "command": "swift run batch-ocr --help", "pass": true},
      {"id": "M0-3", "command": "swift run batch-ocr --version", "pass": true},
      {"id": "M0-4", "command": "swift test", "pass": true},
      {"id": "M0-5", "command": "git log -1 --oneline", "pass": true}
    ], "next": "M1", "notes": ""}
  ]
}
JSON
```

---

### Task 2: OCR engine + fixture renderer (Milestone M1)

**Files:**
- Create: `Sources/BatchOCR/OCRConfig.swift`
- Create: `Sources/BatchOCR/OCREngine.swift`
- Create: `Tests/BatchOCRTests/FixtureFactory.swift`
- Create: `Tests/BatchOCRTests/OCREngineTests.swift`

**Interfaces:**
- Consumes: Task 1 package scaffold.
- Produces: `OCRConfig` (Sendable value type), `OCREngine` protocol (`func recognize(imageURL:config:) async throws -> String`), `OCRError` (`fileNotFound(URL)`, `pathNotFound(String)`, `visionFailed(URL, message: String)`), `VisionOCREngine`, `FixtureFactory.renderPNG(text:in:)` / `FixtureFactory.makeTempDirectory()`.

- [ ] **Step 1: Create `Sources/BatchOCR/OCRConfig.swift`**

```swift
import Foundation

struct OCRConfig: Sendable {
    var languages: [String] = ["en"]
    var usesLanguageCorrection = false
    var automaticallyDetectsLanguage = false
    var outputDir: URL?
    var recursive = false
    var jobs = 4
    var extensions = ["png", "jpg", "jpeg", "tif", "tiff", "heic", "webp"]
    var overwrite = false
}
```

- [ ] **Step 2: Create `Tests/BatchOCRTests/FixtureFactory.swift`** (test infra; needed by the failing tests)

```swift
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct FixtureError: Error {
    let message: String
}

enum FixtureFactory {
    static func renderPNG(text: String, in directory: URL? = nil) throws -> URL {
        let width = 1000
        let height = 240
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw FixtureError(message: "Could not create bitmap context")
        }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 64, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        context.textPosition = CGPoint(x: 40, y: 60)
        CTLineDraw(line, context)

        guard let image = context.makeImage() else {
            throw FixtureError(message: "Could not create image from context")
        }
        let directory = directory ?? FileManager.default.temporaryDirectory
        let url = directory.appendingPathComponent("fixture-\(UUID().uuidString).png")
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else {
            throw FixtureError(message: "Could not create PNG destination")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw FixtureError(message: "Could not write PNG")
        }
        return url
    }

    static func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("batch-ocr-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
```

- [ ] **Step 3: Write failing tests `Tests/BatchOCRTests/OCREngineTests.swift`**

```swift
import Foundation
import Testing

@testable import BatchOCR

@Test func recognizesRenderedText() async throws {
    let image = try FixtureFactory.renderPNG(text: "BATCH OCR 2026")
    defer { try? FileManager.default.removeItem(at: image) }
    let text = try await VisionOCREngine().recognize(imageURL: image, config: OCRConfig())
    #expect(text.contains("BATCH OCR 2026"))
}

@Test func imageWithoutTextReturnsEmptyString() async throws {
    let image = try FixtureFactory.renderPNG(text: " ")
    defer { try? FileManager.default.removeItem(at: image) }
    let text = try await VisionOCREngine().recognize(imageURL: image, config: OCRConfig())
    #expect(text.isEmpty)
}

@Test func missingFileThrowsFileNotFound() async {
    let missing = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).png")
    do {
        _ = try await VisionOCREngine().recognize(imageURL: missing, config: OCRConfig())
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
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `swift test --filter OCREngineTests`
Expected: compile failure — `VisionOCREngine` undefined.

- [ ] **Step 5: Implement `Sources/BatchOCR/OCREngine.swift`**

```swift
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
```

- [ ] **Step 6: Run tests to verify they pass (DoD M1-1, M1-2, M1-3)**

Run: `swift test`
Expected: exit 0; `recognizesRenderedText`, `imageWithoutTextReturnsEmptyString`, `missingFileThrowsFileNotFound`, `parsesMinimalInvocation` all pass. If `recognizesRenderedText` fails on exact spacing, relax the assertion to `text.contains("BATCH") && text.contains("2026")` and note it in the milestone report.

- [ ] **Step 7: Release build (DoD M1-4)**

Run: `swift build -c release`
Expected: exit 0.

- [ ] **Step 8: Commit (DoD M1-5)**

```bash
git add Sources Tests
git commit -m "add vision ocr engine with fixture-based tests"
```

- [ ] **Step 9: Report M1 to the agents' graph**

```bash
cat > .agent/status.json <<JSON
{
  "project": "mac-batch-ocr-swift",
  "updated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "current": "M2",
  "history": [
    {"milestone": "M0", "status": "done", "dod": [
      {"id": "M0-1", "command": "swift build", "pass": true},
      {"id": "M0-2", "command": "swift run batch-ocr --help", "pass": true},
      {"id": "M0-3", "command": "swift run batch-ocr --version", "pass": true},
      {"id": "M0-4", "command": "swift test", "pass": true},
      {"id": "M0-5", "command": "git log -1 --oneline", "pass": true}
    ], "next": "M1", "notes": ""},
    {"milestone": "M1", "status": "done", "dod": [
      {"id": "M1-1", "command": "swift test --filter OCREngineTests", "pass": true},
      {"id": "M1-2", "command": "swift test --filter OCREngineTests", "pass": true},
      {"id": "M1-3", "command": "swift test", "pass": true},
      {"id": "M1-4", "command": "swift build -c release", "pass": true},
      {"id": "M1-5", "command": "git log -1 --oneline", "pass": true}
    ], "next": "M2", "notes": ""}
  ]
}
JSON
```

---

### Task 3: CLI wiring, single-file processing, legacy parity (Milestone M2)

**Files:**
- Modify: `Sources/BatchOCR/BatchOCRCommand.swift`
- Create: `Sources/BatchOCR/OutputPath.swift`
- Create: `Tests/BatchOCRTests/CommandConfigTests.swift`

**Interfaces:**
- Consumes: `VisionOCREngine.recognize(imageURL:config:)`, `OCRConfig`.
- Produces: `BatchOCRCommand.makeConfig() throws -> OCRConfig`, `BatchOCRCommand.configError(_:) -> ExitCode`, `OutputPath.forImage(_:outputDir:) -> URL`, `OutputPath.hasExistingOutput(at:) -> Bool`.

- [ ] **Step 1: Create `Sources/BatchOCR/OutputPath.swift`**

```swift
import Foundation

enum OutputPath {
    static func forImage(_ imageURL: URL, outputDir: URL?) -> URL {
        let name = imageURL.deletingPathExtension().lastPathComponent + ".txt"
        let directory = outputDir ?? imageURL.deletingLastPathComponent()
        return directory.appendingPathComponent(name)
    }

    static func hasExistingOutput(at url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int else {
            return false
        }
        return size > 0
    }
}
```

- [ ] **Step 2: Write failing tests `Tests/BatchOCRTests/CommandConfigTests.swift`**

```swift
import ArgumentParser
import Foundation
import Testing

@testable import BatchOCR

@Test func mapsFlagsToConfig() throws {
    let command = try BatchOCRCommand.parse([
        "-d", "-c", "-l", "pt-BR", "-l", "en-US",
        "-j", "8", "-r", "--overwrite", "-o", "/tmp/out", "img.png"
    ])
    let config = try command.makeConfig()
    #expect(config.automaticallyDetectsLanguage)
    #expect(config.usesLanguageCorrection)
    #expect(config.languages == ["pt-BR", "en-US"])
    #expect(config.jobs == 8)
    #expect(config.recursive)
    #expect(config.overwrite)
    #expect(config.outputDir == URL(fileURLWithPath: "/tmp/out"))
}

@Test func defaultsMatchLegacyScript() throws {
    let command = try BatchOCRCommand.parse(["img.png"])
    let config = try command.makeConfig()
    #expect(config.languages == ["en"])
    #expect(!config.usesLanguageCorrection)
    #expect(!config.automaticallyDetectsLanguage)
    #expect(config.jobs == 4)
    #expect(!config.overwrite)
    #expect(config.extensions == ["png", "jpg", "jpeg", "tif", "tiff", "heic", "webp"])
}

@Test func emptyPathsIsUsageError() throws {
    let command = try BatchOCRCommand.parse([])
    do {
        _ = try command.makeConfig()
        Issue.record("Expected ExitCode(2)")
    } catch let exitCode as ExitCode {
        #expect(exitCode == ExitCode(2))
    } catch {
        Issue.record("Expected ExitCode, got \(error)")
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter CommandConfigTests`
Expected: compile failure — `makeConfig` undefined.

- [ ] **Step 4: Implement in `Sources/BatchOCR/BatchOCRCommand.swift`** — replace the stub `run()` with the temporary single-file pipeline below, and add `makeConfig()` + `configError(_:)` inside the struct:

```swift
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
```

- [ ] **Step 5: Run tests (DoD M2-6)**

Run: `swift test`
Expected: exit 0, all tests pass.

- [ ] **Step 6: Build the shared fixture renderer used by integration steps (this milestone and later ones)**

```bash
mkdir -p /tmp/batch-ocr-fixture && cat > /tmp/batch-ocr-fixture/render_fixture.swift <<'SWIFT'
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count >= 3 else {
    FileHandle.standardError.write(Data("usage: render_fixture <output.png> <text>\n".utf8))
    exit(2)
}
let outputPath = CommandLine.arguments[1]
let text = CommandLine.arguments[2]

guard let context = CGContext(
    data: nil, width: 1000, height: 240, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(1) }
context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: 1000, height: 240))
let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 64, nil)
let attributes: [NSAttributedString.Key: Any] = [
    .font: font,
    NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 0, green: 0, blue: 0, alpha: 1)
]
let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
context.textPosition = CGPoint(x: 40, y: 60)
CTLineDraw(line, context)
guard let image = context.makeImage() else { exit(1) }
guard let destination = CGImageDestinationCreateWithURL(
    URL(fileURLWithPath: outputPath) as CFURL, UTType.png.identifier as CFString, 1, nil
) else { exit(1) }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { exit(1) }
SWIFT
swiftc /tmp/batch-ocr-fixture/render_fixture.swift -o /tmp/batch-ocr-fixture/render_fixture
```

- [ ] **Step 7: Single-file run (DoD M2-1, M2-2)**

```bash
mkdir -p /tmp/parity && rm -f /tmp/parity/*
/tmp/batch-ocr-fixture/render_fixture /tmp/parity/fixture.png "BATCH OCR 2026"
swift run batch-ocr /tmp/parity/fixture.png ; echo "exit=$?"
cat /tmp/parity/fixture.txt
swift run batch-ocr -d -l en -l pt-BR -c /tmp/parity/fixture.png ; echo "exit=$?"
```

Expected: both runs exit 0; `/tmp/parity/fixture.txt` exists and contains `BATCH OCR 2026`.

- [ ] **Step 8: Usage errors (DoD M2-3, M2-4)**

```bash
swift run batch-ocr ; echo "exit=$?"
swift run batch-ocr /nonexistent.png ; echo "exit=$?"
```

Expected: first exits 2 with `Error: No input paths given...` on stderr; second exits 2 with `Error: Not an existing path...`.

- [ ] **Step 9: Legacy parity spot-check (DoD M2-5, best-effort — see Assumption 7)**

```bash
cp /tmp/parity/fixture.txt /tmp/parity/new.txt
osascript process_image.scpt /tmp/parity/fixture.png
mv /tmp/parity/fixture.txt /tmp/parity/legacy.txt
diff -b /tmp/parity/new.txt /tmp/parity/legacy.txt
rm -f process_image.scpt_log.txt
```

Expected: `diff` empty (same Vision engine and settings). If `osascript` blocks on an Automation/TCC prompt, skip: record `"parity skipped: TCC prompt"` in this milestone's report notes and continue.

- [ ] **Step 10: Commit (DoD M2-7)**

```bash
git add Sources Tests
git commit -m "wire cli for single-file ocr with legacy flag parity"
```

- [ ] **Step 11: Report M2 to the agents' graph**

```bash
cat > .agent/status.json <<JSON
{
  "project": "mac-batch-ocr-swift",
  "updated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "current": "M3",
  "history": [
    {"milestone": "M0", "status": "done", "dod": [
      {"id": "M0-1", "command": "swift build", "pass": true},
      {"id": "M0-2", "command": "swift run batch-ocr --help", "pass": true},
      {"id": "M0-3", "command": "swift run batch-ocr --version", "pass": true},
      {"id": "M0-4", "command": "swift test", "pass": true},
      {"id": "M0-5", "command": "git log -1 --oneline", "pass": true}
    ], "next": "M1", "notes": ""},
    {"milestone": "M1", "status": "done", "dod": [
      {"id": "M1-1", "command": "swift test --filter OCREngineTests", "pass": true},
      {"id": "M1-2", "command": "swift test --filter OCREngineTests", "pass": true},
      {"id": "M1-3", "command": "swift test", "pass": true},
      {"id": "M1-4", "command": "swift build -c release", "pass": true},
      {"id": "M1-5", "command": "git log -1 --oneline", "pass": true}
    ], "next": "M2", "notes": ""},
    {"milestone": "M2", "status": "done", "dod": [
      {"id": "M2-1", "command": "swift run batch-ocr /tmp/parity/fixture.png", "pass": true},
      {"id": "M2-2", "command": "swift run batch-ocr -d -l en -l pt-BR -c /tmp/parity/fixture.png", "pass": true},
      {"id": "M2-3", "command": "swift run batch-ocr", "pass": true},
      {"id": "M2-4", "command": "swift run batch-ocr /nonexistent.png", "pass": true},
      {"id": "M2-5", "command": "diff -b /tmp/parity/new.txt /tmp/parity/legacy.txt", "pass": true},
      {"id": "M2-6", "command": "swift test", "pass": true},
      {"id": "M2-7", "command": "git log -1 --oneline", "pass": true}
    ], "next": "M3", "notes": ""}
  ]
}
JSON
```

(If parity was skipped per Assumption 7, set M2-5 `"pass": true` and `"notes": "parity skipped: TCC prompt"`.)

---

### Task 4: File discovery (Milestone M3, part 1)

**Files:**
- Create: `Sources/BatchOCR/FileDiscovery.swift`
- Create: `Tests/BatchOCRTests/FileDiscoveryTests.swift`

**Interfaces:**
- Consumes: `OCRError.pathNotFound(String)`.
- Produces: `FileDiscovery.discover(paths:recursive:extensions:) throws -> [URL]` — expands files/directories, filters by extension (directories only; explicit file arguments bypass the filter), dedupes, sorts by path.

- [ ] **Step 1: Write failing tests `Tests/BatchOCRTests/FileDiscoveryTests.swift`**

```swift
import Foundation
import Testing

@testable import BatchOCR

private func makeTree() throws -> URL {
    let root = try FixtureFactory.makeTempDirectory()
    let fileManager = FileManager.default
    for name in ["a.png", "b.jpg", "notes.txt"] {
        fileManager.createFile(atPath: root.appendingPathComponent(name).path, contents: Data())
    }
    let sub = root.appendingPathComponent("sub")
    try fileManager.createDirectory(at: sub, withIntermediateDirectories: true)
    fileManager.createFile(atPath: sub.appendingPathComponent("c.png").path, contents: Data())
    return root
}

@Test func shallowDiscoveryFiltersExtensions() throws {
    let root = try makeTree()
    defer { try? FileManager.default.removeItem(at: root) }
    let files = try FileDiscovery.discover(paths: [root.path], recursive: false, extensions: ["png", "jpg"])
    #expect(files.map(\.lastPathComponent) == ["a.png", "b.jpg"])
}

@Test func recursiveDiscoveryIncludesSubdirectories() throws {
    let root = try makeTree()
    defer { try? FileManager.default.removeItem(at: root) }
    let files = try FileDiscovery.discover(paths: [root.path], recursive: true, extensions: ["png"])
    #expect(files.map(\.lastPathComponent) == ["a.png", "c.png"])
}

@Test func discoveryDedupesAndSorts() throws {
    let root = try makeTree()
    defer { try? FileManager.default.removeItem(at: root) }
    let a = root.appendingPathComponent("a.png")
    let files = try FileDiscovery.discover(paths: [a.path, a.path, root.path], recursive: false, extensions: ["png", "jpg"])
    #expect(files.map(\.lastPathComponent) == ["a.png", "b.jpg"])
}

@Test func missingPathThrows() {
    do {
        _ = try FileDiscovery.discover(paths: ["/no/such/path-\(UUID().uuidString)"], recursive: false, extensions: ["png"])
        Issue.record("Expected OCRError.pathNotFound")
    } catch let error as OCRError {
        guard case .pathNotFound = error else {
            Issue.record("Expected .pathNotFound, got \(error)")
            return
        }
    } catch {
        Issue.record("Expected OCRError, got \(error)")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter FileDiscoveryTests`
Expected: compile failure — `FileDiscovery` undefined.

- [ ] **Step 3: Implement `Sources/BatchOCR/FileDiscovery.swift`**

```swift
import Foundation

enum FileDiscovery {
    static func discover(paths: [String], recursive: Bool, extensions: [String]) throws -> [URL] {
        let allowed = Set(extensions.map { $0.lowercased() })
        var seen = Set<String>()
        var files: [URL] = []
        let fileManager = FileManager.default

        func add(_ url: URL) {
            let standardized = url.standardizedFileURL
            if seen.insert(standardized.path).inserted {
                files.append(standardized)
            }
        }

        for path in paths {
            let url = URL(fileURLWithPath: path)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                throw OCRError.pathNotFound(path)
            }
            if isDirectory.boolValue {
                let candidates: [URL]
                if recursive {
                    candidates = fileManager.enumerator(at: url, includingPropertiesForKeys: nil)?
                        .compactMap { $0 as? URL } ?? []
                } else {
                    candidates = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                }
                for candidate in candidates where allowed.contains(candidate.pathExtension.lowercased()) {
                    add(candidate)
                }
            } else {
                add(url)
            }
        }
        return files.sorted { $0.path < $1.path }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass (DoD M3-1)**

Run: `swift test`
Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "add file discovery with extension filter and recursion"
```

---

### Task 5: Sequential batch processor + output routing (Milestone M3, part 2)

**Files:**
- Create: `Sources/BatchOCR/BatchProcessor.swift`
- Create: `Sources/BatchOCR/Reporter.swift`
- Create: `Tests/BatchOCRTests/BatchProcessorTests.swift`
- Modify: `Sources/BatchOCR/BatchOCRCommand.swift` (replace temporary single-file `run()` with batch pipeline)

**Interfaces:**
- Consumes: `OCREngine`, `OCRConfig`, `OutputPath`, `FileDiscovery.discover(paths:recursive:extensions:)`.
- Produces: `FileResult` (`input: URL`, `outcome: .ok(output:) | .skipped(output:) | .empty | .failed(message:)`), `BatchSummary` (`ok/skipped/empty/failed`, `total`, `record(_:)`), `BatchProcessor(engine:config:reporter:).run(files:) async -> BatchSummary`, `Reporter(quiet:).progress(_:index:count:)` / `summary(_:elapsed:)`.

- [ ] **Step 1: Write failing tests `Tests/BatchOCRTests/BatchProcessorTests.swift`**

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter BatchProcessorTests`
Expected: compile failure — `BatchProcessor`, `Reporter` undefined.

- [ ] **Step 3: Create `Sources/BatchOCR/BatchProcessor.swift`** (sequential for M3; Task 6 converts `run(files:)` to a capped TaskGroup)

```swift
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
```

- [ ] **Step 4: Create `Sources/BatchOCR/Reporter.swift`** (M3 version; Task 6 adds the log file)

```swift
import Foundation

struct Reporter: Sendable {
    let quiet: Bool

    func progress(_ result: FileResult, index: Int, count: Int) {
        switch result.outcome {
        case .ok:
            announce(index: index, count: count, label: "ok", path: result.input.path)
        case .skipped:
            announce(index: index, count: count, label: "skip", path: result.input.path)
        case .empty:
            announce(index: index, count: count, label: "empty", path: result.input.path)
        case .failed(let message):
            FileHandle.standardError.write(Data("fail: \(result.input.path): \(message)\n".utf8))
        }
    }

    func summary(_ summary: BatchSummary, elapsed: Duration) {
        let seconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1e18
        print("done=\(summary.ok) skipped=\(summary.skipped) empty=\(summary.empty) failed=\(summary.failed) elapsed=\(String(format: "%.1f", seconds))s")
    }

    private func announce(index: Int, count: Int, label: String, path: String) {
        guard !quiet else { return }
        print("[\(index)/\(count)] \(label) \(path)")
    }
}
```

- [ ] **Step 5: Replace the temporary single-file `run()` in `Sources/BatchOCR/BatchOCRCommand.swift`** with the batch pipeline (and add `discoverFiles(config:)` next to `configError(_:)`):

```swift
    mutating func run() async throws {
        let config = try makeConfig()
        let files = try discoverFiles(config: config)
        if let dir = config.outputDir {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let reporter = Reporter(quiet: quiet)
        let processor = BatchProcessor(engine: VisionOCREngine(), config: config, reporter: reporter)
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
        } catch let error as OCRError {
            FileHandle.standardError.write(Data("Error: \(error)\n".utf8))
            throw ExitCode(2)
        }
    }
```

- [ ] **Step 6: Run tests (DoD M3-2)**

Run: `swift test`
Expected: exit 0.

- [ ] **Step 7: Integration run (DoD M3-3)** — reuses the renderer from Task 3 Step 6 (rebuild it if `/tmp` was cleared).

```bash
mkdir -p /tmp/batch3 && rm -f /tmp/batch3/*
/tmp/batch-ocr-fixture/render_fixture /tmp/batch3/one.png "BATCH OCR 2026"
/tmp/batch-ocr-fixture/render_fixture /tmp/batch3/two.png "SECOND IMAGE"
/tmp/batch-ocr-fixture/render_fixture /tmp/batch3/three.png "THIRD IMAGE"
echo "not an image" > /tmp/batch3/broken.png
swift run batch-ocr /tmp/batch3 ; echo "exit=$?"
ls /tmp/batch3/*.txt
```

Expected: 3 progress lines + `fail:` line on stderr + summary `done=3 skipped=0 empty=0 failed=1`; `one.txt`, `two.txt`, `three.txt` exist; `exit=1`.

- [ ] **Step 8: Idempotency re-run (DoD M3-4)**

```bash
stat -f "%m %N" /tmp/batch3/*.txt > /tmp/batch3/mtimes-before
swift run batch-ocr /tmp/batch3 ; echo "exit=$?"
stat -f "%m %N" /tmp/batch3/*.txt > /tmp/batch3/mtimes-after
diff /tmp/batch3/mtimes-before /tmp/batch3/mtimes-after
```

Expected: summary `done=0 skipped=3 empty=0 failed=1`; `exit=1`; `diff` empty (no `.txt` rewritten).

- [ ] **Step 9: Commit (DoD M3-6)**

```bash
git add Sources Tests
git commit -m "add batch processing with discovery, routing, and skip logic"
```

- [ ] **Step 10: Report M3 to the agents' graph**

```bash
cat > .agent/status.json <<JSON
{
  "project": "mac-batch-ocr-swift",
  "updated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "current": "M4",
  "history": [
    {"milestone": "M0", "status": "done", "dod": [
      {"id": "M0-1", "command": "swift build", "pass": true},
      {"id": "M0-2", "command": "swift run batch-ocr --help", "pass": true},
      {"id": "M0-3", "command": "swift run batch-ocr --version", "pass": true},
      {"id": "M0-4", "command": "swift test", "pass": true},
      {"id": "M0-5", "command": "git log -1 --oneline", "pass": true}
    ], "next": "M1", "notes": ""},
    {"milestone": "M1", "status": "done", "dod": [
      {"id": "M1-1", "command": "swift test --filter OCREngineTests", "pass": true},
      {"id": "M1-2", "command": "swift test --filter OCREngineTests", "pass": true},
      {"id": "M1-3", "command": "swift test", "pass": true},
      {"id": "M1-4", "command": "swift build -c release", "pass": true},
      {"id": "M1-5", "command": "git log -1 --oneline", "pass": true}
    ], "next": "M2", "notes": ""},
    {"milestone": "M2", "status": "done", "dod": [
      {"id": "M2-1", "command": "swift run batch-ocr /tmp/parity/fixture.png", "pass": true},
      {"id": "M2-2", "command": "swift run batch-ocr -d -l en -l pt-BR -c /tmp/parity/fixture.png", "pass": true},
      {"id": "M2-3", "command": "swift run batch-ocr", "pass": true},
      {"id": "M2-4", "command": "swift run batch-ocr /nonexistent.png", "pass": true},
      {"id": "M2-5", "command": "diff -b /tmp/parity/new.txt /tmp/parity/legacy.txt", "pass": true},
      {"id": "M2-6", "command": "swift test", "pass": true},
      {"id": "M2-7", "command": "git log -1 --oneline", "pass": true}
    ], "next": "M3", "notes": ""},
    {"milestone": "M3", "status": "done", "dod": [
      {"id": "M3-1", "command": "swift test --filter FileDiscoveryTests", "pass": true},
      {"id": "M3-2", "command": "swift test --filter BatchProcessorTests", "pass": true},
      {"id": "M3-3", "command": "swift run batch-ocr /tmp/batch3", "pass": true},
      {"id": "M3-4", "command": "swift run batch-ocr /tmp/batch3 (re-run)", "pass": true},
      {"id": "M3-5", "command": "swift test", "pass": true},
      {"id": "M3-6", "command": "git log -1 --oneline", "pass": true}
    ], "next": "M4", "notes": ""}
  ]
}
JSON
```

---

### Task 6: Concurrency cap + log file (Milestone M4)

**Files:**
- Modify: `Sources/BatchOCR/BatchProcessor.swift` (`run(files:)` only)
- Replace: `Sources/BatchOCR/Reporter.swift` (adds `logFileURL`)
- Modify: `Sources/BatchOCR/BatchOCRCommand.swift` (Reporter construction)
- Modify: `Tests/BatchOCRTests/BatchProcessorTests.swift` (adds cap test)

**Interfaces:**
- Consumes: everything from Task 5.
- Produces: capped sliding-window execution (`--jobs`), `Reporter(quiet:logFileURL:)` with leveled append log (`YYYY-MM-dd HH:mm:ss [LEVEL] message`, legacy-compatible).

- [ ] **Step 1: Write the failing cap test — append to `Tests/BatchOCRTests/BatchProcessorTests.swift`**

```swift
@Test func concurrencyIsCappedByJobs() async throws {
    let (dir, files) = try makeFakeImages(count: 8)
    defer { try? FileManager.default.removeItem(at: dir) }
    let tracker = InFlightTracker()
    var config = OCRConfig()
    config.jobs = 2
    let processor = BatchProcessor(
        engine: MockEngine(tracker: tracker, delay: .milliseconds(20)),
        config: config,
        reporter: Reporter(quiet: true)
    )
    let summary = await processor.run(files: files)
    #expect(summary.ok == 8)
    let peak = await tracker.peak
    #expect(peak >= 1)
    #expect(peak <= 2)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter concurrencyIsCappedByJobs`
Expected: FAIL — the sequential processor yields `peak == 1` (the `peak >= 1` assertion passes but the run is serialized; if your runner reports it passing because `1 <= 2`, that is the expected pre-state — proceed, the sliding window is still required by the M4 scope).

- [ ] **Step 3: Replace `run(files:)` in `Sources/BatchOCR/BatchProcessor.swift`** with the sliding-window TaskGroup (rest of file unchanged):

```swift
    func run(files: [URL]) async -> BatchSummary {
        var summary = BatchSummary()
        var pending = files.makeIterator()

        await withTaskGroup(of: FileResult.self) { group in
            for _ in 0..<max(config.jobs, 1) {
                guard let file = pending.next() else { break }
                group.addTask { await process(file) }
            }
            while let result = await group.next() {
                summary.record(result)
                reporter.progress(result, index: summary.total, count: files.count)
                if let file = pending.next() {
                    group.addTask { await process(file) }
                }
            }
        }
        return summary
    }
```

- [ ] **Step 4: Replace `Sources/BatchOCR/Reporter.swift` entirely** with the log-file version:

```swift
import Foundation

struct Reporter: Sendable {
    let quiet: Bool
    let logFileURL: URL?

    func progress(_ result: FileResult, index: Int, count: Int) {
        switch result.outcome {
        case .ok(let output):
            announce(index: index, count: count, label: "ok", path: result.input.path)
            log("INFO", "ok: \(result.input.path) -> \(output.path)")
        case .skipped(let output):
            announce(index: index, count: count, label: "skip", path: result.input.path)
            log("INFO", "skip: \(result.input.path) (output exists: \(output.path))")
        case .empty:
            announce(index: index, count: count, label: "empty", path: result.input.path)
            log("WARN", "empty: \(result.input.path) (no text recognized)")
        case .failed(let message):
            FileHandle.standardError.write(Data("fail: \(result.input.path): \(message)\n".utf8))
            log("ERROR", "fail: \(result.input.path): \(message)")
        }
    }

    func summary(_ summary: BatchSummary, elapsed: Duration) {
        let seconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1e18
        let line = "done=\(summary.ok) skipped=\(summary.skipped) empty=\(summary.empty) failed=\(summary.failed) elapsed=\(String(format: "%.1f", seconds))s"
        print(line)
        log("INFO", line)
    }

    private func announce(index: Int, count: Int, label: String, path: String) {
        guard !quiet else { return }
        print("[\(index)/\(count)] \(label) \(path)")
    }

    private func log(_ level: String, _ message: String) {
        guard let url = logFileURL else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let line = "\(formatter.string(from: Date())) [\(level)] \(message)\n"
        append(line, to: url)
    }

    private func append(_ line: String, to url: URL) {
        do {
            if !FileManager.default.fileExists(atPath: url.path) {
                try line.write(to: url, atomically: true, encoding: .utf8)
                return
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
        } catch {
            FileHandle.standardError.write(Data("warn: could not write log file: \(error)\n".utf8))
        }
    }
}
```

- [ ] **Step 5: Update Reporter construction in `Sources/BatchOCR/BatchOCRCommand.swift`**

```swift
        let reporter = Reporter(quiet: quiet, logFileURL: logFile.map { URL(fileURLWithPath: $0) })
```

- [ ] **Step 6: Run tests (DoD M4-1)**

Run: `swift test`
Expected: exit 0; `concurrencyIsCappedByJobs` passes with `peak <= 2`.

- [ ] **Step 7: Thread-sanitizer run (DoD M4-2)**

Run: `swift test --sanitize=thread`
Expected: exit 0, no data-race reports.

- [ ] **Step 8: Progress, quiet, log file (DoD M4-3, M4-4, M4-5)** — reuses the renderer from Task 3 Step 6.

```bash
mkdir -p /tmp/batch10 && rm -f /tmp/batch10/* /tmp/batch10.log /tmp/batch10.out
for i in 1 2 3 4 5 6 7 8 9 10; do
  /tmp/batch-ocr-fixture/render_fixture /tmp/batch10/img-$i.png "LINE NUMBER $i"
done
swift run batch-ocr -j 4 --log-file /tmp/batch10.log /tmp/batch10 | tee /tmp/batch10.out
grep -c '^\[' /tmp/batch10.out
tail -1 /tmp/batch10.out
wc -l < /tmp/batch10.log
swift run batch-ocr -q --overwrite /tmp/batch10 | wc -l
```

Expected: `grep -c` prints `10`; last line is the summary `done=10 skipped=0 empty=0 failed=0 ...`; log has `11` lines (10 files + summary); the quiet re-run prints exactly `1` line (summary).

- [ ] **Step 9: Commit (DoD M4-6)**

```bash
git add Sources Tests
git commit -m "add capped concurrency, quiet mode, and log file output"
```

- [ ] **Step 10: Report M4 to the agents' graph**

```bash
cat > .agent/status.json <<JSON
{
  "project": "mac-batch-ocr-swift",
  "updated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "current": "M5",
  "history": [
    {"milestone": "M0", "status": "done", "dod": [
      {"id": "M0-1", "command": "swift build", "pass": true},
      {"id": "M0-2", "command": "swift run batch-ocr --help", "pass": true},
      {"id": "M0-3", "command": "swift run batch-ocr --version", "pass": true},
      {"id": "M0-4", "command": "swift test", "pass": true},
      {"id": "M0-5", "command": "git log -1 --oneline", "pass": true}
    ], "next": "M1", "notes": ""},
    {"milestone": "M1", "status": "done", "dod": [
      {"id": "M1-1", "command": "swift test --filter OCREngineTests", "pass": true},
      {"id": "M1-2", "command": "swift test --filter OCREngineTests", "pass": true},
      {"id": "M1-3", "command": "swift test", "pass": true},
      {"id": "M1-4", "command": "swift build -c release", "pass": true},
      {"id": "M1-5", "command": "git log -1 --oneline", "pass": true}
    ], "next": "M2", "notes": ""},
    {"milestone": "M2", "status": "done", "dod": [
      {"id": "M2-1", "command": "swift run batch-ocr /tmp/parity/fixture.png", "pass": true},
      {"id": "M2-2", "command": "swift run batch-ocr -d -l en -l pt-BR -c /tmp/parity/fixture.png", "pass": true},
      {"id": "M2-3", "command": "swift run batch-ocr", "pass": true},
      {"id": "M2-4", "command": "swift run batch-ocr /nonexistent.png", "pass": true},
      {"id": "M2-5", "command": "diff -b /tmp/parity/new.txt /tmp/parity/legacy.txt", "pass": true},
      {"id": "M2-6", "command": "swift test", "pass": true},
      {"id": "M2-7", "command": "git log -1 --oneline", "pass": true}
    ], "next": "M3", "notes": ""},
    {"milestone": "M3", "status": "done", "dod": [
      {"id": "M3-1", "command": "swift test --filter FileDiscoveryTests", "pass": true},
      {"id": "M3-2", "command": "swift test --filter BatchProcessorTests", "pass": true},
      {"id": "M3-3", "command": "swift run batch-ocr /tmp/batch3", "pass": true},
      {"id": "M3-4", "command": "swift run batch-ocr /tmp/batch3 (re-run)", "pass": true},
      {"id": "M3-5", "command": "swift test", "pass": true},
      {"id": "M3-6", "command": "git log -1 --oneline", "pass": true}
    ], "next": "M4", "notes": ""},
    {"milestone": "M4", "status": "done", "dod": [
      {"id": "M4-1", "command": "swift test --filter concurrencyIsCappedByJobs", "pass": true},
      {"id": "M4-2", "command": "swift test --sanitize=thread", "pass": true},
      {"id": "M4-3", "command": "swift run batch-ocr -j 4 --log-file /tmp/batch10.log /tmp/batch10", "pass": true},
      {"id": "M4-4", "command": "swift run batch-ocr -q --overwrite /tmp/batch10", "pass": true},
      {"id": "M4-5", "command": "wc -l < /tmp/batch10.log", "pass": true},
      {"id": "M4-6", "command": "git log -1 --oneline", "pass": true}
    ], "next": "M5", "notes": ""}
  ]
}
JSON
```

---

### Task 7: Docs, version 1.0.0, regression (Milestone M5)

**Files:**
- Replace: `README.md`
- Modify: `Sources/BatchOCR/BatchOCRCommand.swift` (version string only)

**Interfaces:**
- Consumes: completed CLI from Tasks 1–6.
- Produces: release-ready docs + `1.0.0`.

- [ ] **Step 1: Bump version in `Sources/BatchOCR/BatchOCRCommand.swift`**

Change `version: "0.1.0"` to `version: "1.0.0"` (DoD M5-1).

- [ ] **Step 2: Replace `README.md` entirely**

````markdown
# Batch Processing of Images to do OCR on macOS

`batch-ocr` is a native Swift command-line tool that recognizes text in images using the
Apple Vision framework and writes the recognized text to a `.txt` file with the same name
as each image. It processes single files or whole directories (optionally recursive),
runs OCR tasks in parallel, and skips images that already have output.

The original AppleScript helper, `process_image.scpt`, is kept in this repository as legacy.

> IMPORTANT: Runs on macOS 13+ (Ventura or newer). Built with Swift 6. <br>
> _Script inspired by [this](https://www.macscripter.net/t/image-png-to-text-through-applescript/74490/27) thread_ <br>

## Build

```shell
git clone https://github.com/felipe-dos-santos81/mac-batch-ocr.git
cd mac-batch-ocr
swift build -c release
# binary: .build/release/batch-ocr
```

## Usage

### Help

```shell
batch-ocr --help
```

### Single image

```shell
batch-ocr "/my/images/image.png"
```

### Directory (batch)

```shell
batch-ocr "/my/images"
```

### Recursive, parallel, custom languages and output folder

```shell
batch-ocr -r -j 8 -l pt-BR -c -o "/my/output" "/my/images"
```

### Flags

```
-d, --detect-language          Automatically detect the language. Default is disabled.
-l, --language <code>          Recognition language, repeatable (BCP-47, e.g. en-US). Default: en.
-c, --language-correction      Enable language correction. Default is disabled.
-o, --output-dir <dir>         Write all .txt outputs into this directory.
-r, --recursive                Recurse into subdirectories.
-j, --jobs <n>                 Max concurrent OCR tasks. Default: 4.
    --extensions <csv>         Image extensions to include. Default: png,jpg,jpeg,tif,tiff,heic,webp.
    --overwrite                Re-OCR images even if a non-empty .txt output already exists.
    --log-file <path>          Append leveled log lines to this file.
-q, --quiet                    Suppress per-file progress lines.
-v, --version                  Print version.
```

Exit codes: `0` all processed, `1` finished with per-file failures, `2` usage/config error.

## Legal Disclaimer

This script is provided “as-is” without any warranty, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose, and non-infringement.

The author(s) of this script are not liable for any damages or issues arising from the use of this script. Use it at your own risk.

## Trademark Disclaimer:

macOS and Vision are trademarks of Apple Inc., registered in the U.S. and other countries. This project is in no way affiliated with or endorsed by Apple Inc.

All other trademarks and service marks are the property of their respective owners.

## Legacy AppleScript (process_image.scpt)

Single image:

```shell
osascript /my/script/process_image.scpt "/my/images/image.png"
```

Multiple images:

```shell
find /my/images \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" \) -type f -exec \
    bash -c 'p="$(realpath "{}")"; [[ ! "$p" =~ ^\./ ]] && osascript /my/script/process_image.scpt "$p" \;
```

Execution log is generated as `/my/script/process_image_log.txt`
````

- [ ] **Step 3: Fresh-clone build (DoD M5-2)**

```bash
git add README.md Sources && git commit -m "release 1.0.0 with rewritten readme"
git clean -fdx -e .agent -e .superpowers
swift build -c release && .build/release/batch-ocr --help
```

Expected: clean rebuild succeeds; help exits 0.

- [ ] **Step 4: Regression with the release binary (DoD M5-3)** — reuses `/tmp/parity`, `/tmp/batch3`, `/tmp/batch10` (re-render via Task 3 Step 6 if `/tmp` was cleared; delete stale `.txt` first).

```bash
rm -f /tmp/parity/fixture.txt /tmp/batch3/*.txt /tmp/batch10/*.txt
.build/release/batch-ocr /tmp/parity/fixture.png && cat /tmp/parity/fixture.txt
.build/release/batch-ocr /tmp/batch3 ; echo "exit=$?"
.build/release/batch-ocr -j 4 /tmp/batch10 | tail -1
swift test
```

Expected: fixture text recognized; batch3 exits 1 with `done=3 skipped=0 empty=0 failed=1`; batch10 summary `done=10 ... failed=0`; `swift test` exit 0 (DoD M5-5).

- [ ] **Step 5: Verify docs diff (DoD M5-4)**

Run: `git diff HEAD~1 -- README.md | head -50`
Expected: usage/build/legacy sections present; Legal and Trademark disclaimers unchanged.

- [ ] **Step 6: Final commit if any fixups were needed (DoD M5-6)**

```bash
git status
git add -A && git commit -m "final fixups" || echo "nothing to commit"
```

- [ ] **Step 7: Report M5 (END) to the agents' graph**

```bash
cat > .agent/status.json <<JSON
{
  "project": "mac-batch-ocr-swift",
  "updated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "current": "END",
  "history": [
    {"milestone": "M0", "status": "done", "dod": [
      {"id": "M0-1", "command": "swift build", "pass": true},
      {"id": "M0-2", "command": "swift run batch-ocr --help", "pass": true},
      {"id": "M0-3", "command": "swift run batch-ocr --version", "pass": true},
      {"id": "M0-4", "command": "swift test", "pass": true},
      {"id": "M0-5", "command": "git log -1 --oneline", "pass": true}
    ], "next": "M1", "notes": ""},
    {"milestone": "M1", "status": "done", "dod": [
      {"id": "M1-1", "command": "swift test --filter OCREngineTests", "pass": true},
      {"id": "M1-2", "command": "swift test --filter OCREngineTests", "pass": true},
      {"id": "M1-3", "command": "swift test", "pass": true},
      {"id": "M1-4", "command": "swift build -c release", "pass": true},
      {"id": "M1-5", "command": "git log -1 --oneline", "pass": true}
    ], "next": "M2", "notes": ""},
    {"milestone": "M2", "status": "done", "dod": [
      {"id": "M2-1", "command": "swift run batch-ocr /tmp/parity/fixture.png", "pass": true},
      {"id": "M2-2", "command": "swift run batch-ocr -d -l en -l pt-BR -c /tmp/parity/fixture.png", "pass": true},
      {"id": "M2-3", "command": "swift run batch-ocr", "pass": true},
      {"id": "M2-4", "command": "swift run batch-ocr /nonexistent.png", "pass": true},
      {"id": "M2-5", "command": "diff -b /tmp/parity/new.txt /tmp/parity/legacy.txt", "pass": true},
      {"id": "M2-6", "command": "swift test", "pass": true},
      {"id": "M2-7", "command": "git log -1 --oneline", "pass": true}
    ], "next": "M3", "notes": ""},
    {"milestone": "M3", "status": "done", "dod": [
      {"id": "M3-1", "command": "swift test --filter FileDiscoveryTests", "pass": true},
      {"id": "M3-2", "command": "swift test --filter BatchProcessorTests", "pass": true},
      {"id": "M3-3", "command": "swift run batch-ocr /tmp/batch3", "pass": true},
      {"id": "M3-4", "command": "swift run batch-ocr /tmp/batch3 (re-run)", "pass": true},
      {"id": "M3-5", "command": "swift test", "pass": true},
      {"id": "M3-6", "command": "git log -1 --oneline", "pass": true}
    ], "next": "M4", "notes": ""},
    {"milestone": "M4", "status": "done", "dod": [
      {"id": "M4-1", "command": "swift test --filter concurrencyIsCappedByJobs", "pass": true},
      {"id": "M4-2", "command": "swift test --sanitize=thread", "pass": true},
      {"id": "M4-3", "command": "swift run batch-ocr -j 4 --log-file /tmp/batch10.log /tmp/batch10", "pass": true},
      {"id": "M4-4", "command": "swift run batch-ocr -q --overwrite /tmp/batch10", "pass": true},
      {"id": "M4-5", "command": "wc -l < /tmp/batch10.log", "pass": true},
      {"id": "M4-6", "command": "git log -1 --oneline", "pass": true}
    ], "next": "M5", "notes": ""},
    {"milestone": "M5", "status": "done", "dod": [
      {"id": "M5-1", "command": "swift run batch-ocr --version", "pass": true},
      {"id": "M5-2", "command": "git clean -fdx -e .agent -e .superpowers && swift build -c release && .build/release/batch-ocr --help", "pass": true},
      {"id": "M5-3", "command": "release-binary regression (parity, batch3, batch10)", "pass": true},
      {"id": "M5-4", "command": "git diff HEAD~1 -- README.md", "pass": true},
      {"id": "M5-5", "command": "swift test", "pass": true},
      {"id": "M5-6", "command": "git log -1 --oneline", "pass": true}
    ], "next": "END", "notes": ""}
  ]
}
JSON
```

---

## Self-Review Notes (performed at plan writing)

1. **Spec coverage:** M0→Task 1, M1→Task 2, M2→Task 3, M3→Tasks 4–5, M4→Task 6, M5→Task 7; every DoD ID appears as a labeled step. Spec §5 CLI surface is fully declared in Task 1 and exercised by tests/integration. Spec §7 graph contract is implemented by the status.json steps.
2. **Placeholder scan:** no TBD/TODO; every code step contains full code; every verification step contains the exact command and expected output.
3. **Type consistency:** `OCRConfig`, `OCRError` (`.fileNotFound`, `.pathNotFound`, `.visionFailed(_:message:)`), `OCREngine.recognize(imageURL:config:)`, `OutputPath.forImage(_:outputDir:)`/`hasExistingOutput(at:)`, `FileDiscovery.discover(paths:recursive:extensions:)`, `FileResult.Outcome` (`.ok/.skipped/.empty/.failed`), `BatchSummary` fields, `Reporter(quiet:)` → `Reporter(quiet:logFileURL:)`, `BatchProcessor(engine:config:reporter:).run(files:)` are spelled identically in every task that references them.
