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
