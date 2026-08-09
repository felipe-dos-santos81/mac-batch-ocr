import Foundation
import Testing

@testable import BatchOCR

final class RecordingSink: TextOutputStream, @unchecked Sendable {
    var text = ""
    func write(_ string: String) {
        text += string
    }
}

private let inputURL = URL(fileURLWithPath: "/tmp/img.png")
private let outputURL = URL(fileURLWithPath: "/tmp/img.txt")

@Suite struct ReporterTests {
    @Test func progressLineFormat() {
        let out = RecordingSink()
        let reporter = Reporter(quiet: false, out: out, err: RecordingSink())
        reporter.progress(FileResult(input: inputURL, outcome: .ok(output: outputURL)), index: 1, count: 2)
        #expect(out.text == "[1/2] ok /tmp/img.png\n")
    }

    @Test func quietSuppressesProgressLines() {
        let out = RecordingSink()
        let reporter = Reporter(quiet: true, out: out, err: RecordingSink())
        reporter.progress(FileResult(input: inputURL, outcome: .ok(output: outputURL)), index: 1, count: 2)
        #expect(out.text.isEmpty)
    }

    @Test func failureGoesToStderr() {
        let out = RecordingSink()
        let err = RecordingSink()
        let reporter = Reporter(quiet: false, out: out, err: err)
        reporter.progress(FileResult(input: inputURL, outcome: .failed(message: "boom")), index: 1, count: 1)
        #expect(out.text.isEmpty)
        #expect(err.text == "fail: /tmp/img.png: boom\n")
    }

    @Test func summaryLineIsMachineReadable() {
        var summary = BatchSummary()
        summary.ok = 2
        summary.skipped = 1
        summary.empty = 1
        summary.failed = 1
        let line = Reporter.summaryLine(summary: summary, elapsed: Duration.seconds(1.5))
        #expect(line == "done=2 skipped=1 empty=1 failed=1 elapsed=1.5s")
    }

    @Test func summaryIsWrittenToOutSink() {
        let out = RecordingSink()
        let reporter = Reporter(quiet: true, out: out, err: RecordingSink())
        reporter.summary(BatchSummary(), elapsed: .zero)
        #expect(out.text == "done=0 skipped=0 empty=0 failed=0 elapsed=0.0s\n")
    }

    @Test func logLineFormatUsesPosixLocaleTimestamp() {
        let now = Calendar.current.date(
            from: DateComponents(year: 2026, month: 1, day: 2, hour: 15, minute: 4, second: 5)
        )!
        let line = Reporter.logLine(level: "WARN", message: "empty: /tmp/img.png (no text recognized)", now: now)
        #expect(line == "2026-01-02 15:04:05 [WARN] empty: /tmp/img.png (no text recognized)\n")
    }

    @Test func logLinesAppendToLogFile() throws {
        let dir = try FixtureFactory.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let logURL = dir.appendingPathComponent("run.log")
        let reporter = Reporter(quiet: true, logFileURL: logURL, out: RecordingSink(), err: RecordingSink())
        reporter.progress(FileResult(input: inputURL, outcome: .ok(output: outputURL)), index: 1, count: 1)
        let contents = try String(contentsOf: logURL, encoding: .utf8)
        #expect(contents.hasSuffix(" [INFO] ok: /tmp/img.png -> /tmp/img.txt\n"))
        #expect(contents.hasPrefix("20"))
    }
}
