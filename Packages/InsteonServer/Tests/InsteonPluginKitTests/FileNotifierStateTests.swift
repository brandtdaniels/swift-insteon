import Foundation
import Testing
@testable import InsteonPluginKit

/// The notifier's own state file.
@Suite(.timeLimit(.minutes(1)))
struct FileNotifierStateTests {
  private func url() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("insteon-plugin-state-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("notifier.json")
  }

  @Test func noFileMeansNoPlace() throws {
    #expect(try FileNotifierState(url: try url()).lastEventID() == nil)
  }

  @Test func theLastIdIsKeptAndReplaced() throws {
    let state = FileNotifierState(url: try url())
    try state.record(lastEventID: "run-1")
    try state.record(lastEventID: "run-2")
    #expect(try state.lastEventID() == "run-2")
  }

  @Test func theFileIsReadableOnlyByTheCurrentUser() throws {
    let url = try url()
    try FileNotifierState(url: url).record(lastEventID: "run-1")
    #expect(try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int == 0o600)
  }

  @Test(arguments: ["not json", #"{"version":2,"lastEventId":"run-1"}"#, #"{"version":1}"#])
  func aFileThatCannotBeReadIsLeftAsItIs(_ contents: String) throws {
    let url = try url()
    try Data(contents.utf8).write(to: url)
    let state = FileNotifierState(url: url)
    #expect(throws: NotifierStateError.unreadable) { try state.lastEventID() }
    #expect(throws: NotifierStateError.unreadable) { try state.record(lastEventID: "run-9") }
    #expect(try Data(contentsOf: url) == Data(contents.utf8))
  }

  @Test func aSymbolicLinkIsNotFollowed() throws {
    let url = try url()
    let target = url.deletingLastPathComponent().appendingPathComponent("elsewhere.json")
    try Data(#"{"version":1,"lastEventId":"run-1"}"#.utf8).write(to: target)
    try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
    #expect(throws: NotifierStateError.unreadable) { try FileNotifierState(url: url).lastEventID() }
  }
}
