import Foundation
import InsteonProtocol
import InsteonScheduling
import InsteonService
import Testing
@testable import InsteonServerSupport

@Suite(.timeLimit(.minutes(1)))
struct ScheduleFileTests {
  private func directory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("insteon-schedule-file-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  private let lamp = InsteonAddress(0x1A, 0x2B, 0x3C)

  private var stored: StoredSchedules {
    StoredSchedules(
      schedules: [
        ServiceSchedule(id: "porch", name: "Porch light", when: Schedule(time: .clock(hour: 18, minute: 30), weekdays: [.monday, .friday]), action: ScheduledAction(device: lamp, kind: .on(levelPercent: 80)), catchUp: true),
        ServiceSchedule(id: "dusk", name: "Dusk", isEnabled: false, when: Schedule(time: .sunset(offset: .seconds(-900))), action: ScheduledAction(device: lamp, kind: .off))
      ],
      timers: [StoredTimer(timer: ServiceTimer(id: "off", name: "Off", delaySeconds: 600, action: ScheduledAction(device: lamp, kind: .off)), remainingSeconds: 212.5)],
      checkedThrough: Date(timeIntervalSince1970: 1_800_000_000),
      settings: ScheduleSettings(timeZoneIdentifier: "America/Los_Angeles", location: GeographicCoordinate(latitude: 34.05, longitude: -118.24))
    )
  }

  @Test func theScheduleFileSitsBesideTheStateFileUnderItsOwnName() {
    #expect(FileSchedulePersistence.url(besideState: "/var/lib/insteon/gateway.json").path == "/var/lib/insteon/gateway-schedules.json")
    #expect(FileSchedulePersistence.url(besideState: "/tmp/noextension").path == "/tmp/noextension-schedules.json")
  }

  @Test func everythingTheServiceKeepsRoundTripsThroughTheFile() async throws {
    let file = FileSchedulePersistence(url: try directory().appendingPathComponent("schedules.json"))
    #expect(try await file.load() == nil)
    try await file.save(stored)
    #expect(try await file.load() == stored)
  }

  @Test func theFileAndItsDirectoryAreReadableOnlyByTheCurrentUser() async throws {
    let url = try directory().appendingPathComponent("created").appendingPathComponent("schedules.json")
    try await FileSchedulePersistence(url: url).save(stored)
    #expect(try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int == 0o600)
    #expect(try FileManager.default.attributesOfItem(atPath: url.deletingLastPathComponent().path)[.posixPermissions] as? Int == 0o700)
  }

  @Test(arguments: [
    "not a document",
    #"{"version":2,"schedules":[],"timers":[],"settings":{}}"#,
    #"{"version":1,"schedules":[{"id":"x","name":"X","enabled":true,"when":{"time":{"kind":"moonrise"},"weekdays":["monday"]},"action":{"device":"1A.2B.3C","action":"off"},"catchUp":false}],"timers":[],"settings":{}}"#,
    #"{"version":1,"schedules":[],"timers":[],"settings":{"latitude":34.0}}"#
  ])
  func aFileThatCannotBeUsedIsLeftAsItIs(_ text: String) async throws {
    let url = try directory().appendingPathComponent("schedules.json")
    let original = Data(text.utf8)
    try original.write(to: url)
    let file = FileSchedulePersistence(url: url)

    await #expect(throws: (any Error).self) { try await file.load() }
    await #expect(throws: (any Error).self) { try await file.save(stored) }
    #expect(try Data(contentsOf: url) == original)
  }
}
