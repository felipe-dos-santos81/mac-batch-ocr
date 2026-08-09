import Testing

@testable import BatchOCR

@Test func parsesMinimalInvocation() throws {
    let command = try BatchOCRCommand.parse(["img.png"])
    #expect(command.paths == ["img.png"])
}
