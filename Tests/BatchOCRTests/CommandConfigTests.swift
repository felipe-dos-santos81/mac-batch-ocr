import ArgumentParser
import Foundation
import Testing

@testable import BatchOCR

@Test func mapsFlagsToConfig() throws {
    let command = try BatchOCRCommand.parse([
        "-d", "-c", "-l", "pt-BR", "-l", "en-US",
        "-j", "8", "-r", "--overwrite", "-o", "/tmp/out", "img.png"
    ])
    let (config, settings) = try command.makeConfig()
    #expect(settings.automaticallyDetectsLanguage)
    #expect(settings.usesLanguageCorrection)
    #expect(settings.languages == ["pt-BR", "en-US"])
    #expect(config.jobs == 8)
    #expect(config.recursive)
    #expect(config.overwrite)
    #expect(config.outputDir == URL(fileURLWithPath: "/tmp/out"))
}

@Test func defaultsMatchLegacyScript() throws {
    let command = try BatchOCRCommand.parse(["img.png"])
    let (config, settings) = try command.makeConfig()
    #expect(settings.languages == ["en"])
    #expect(!settings.usesLanguageCorrection)
    #expect(!settings.automaticallyDetectsLanguage)
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
