import Foundation
import InsteonCore
import InsteonService
import Testing
@testable import InsteonServerSupport

/// Schedules and timers over the real runner, router, service, files and a scripted modem. Nothing waits on time:
/// the wall clock is a date the test moves, and every wait ends on a frame the stream delivers.
@Suite(.timeLimit(.minutes(2)))
struct ScheduleServeTests: ServingTests {
  let gatewayPassword = String(repeating: "g", count: 40)
  let device = InsteonAddress(0x1A, 0x2B, 0x3C)
  /// Saturday, March 7, 2026, noon in Los Angeles.
  static let start = Date(timeIntervalSince1970: 1_772_913_600)
  static let location = ["--latitude", "34.05", "--longitude", "-118.24"]
  static let morning = #"{"name":"Morning","when":{"time":{"kind":"clock","hour":8,"minute":0}},"action":{"device":"1A.2B.3C","action":"on","levelPercent":50}}"#
  static let dusk = #"{"name":"Dusk","when":{"time":{"kind":"sunset","offsetSeconds":-900}},"action":{"device":"1A.2B.3C","action":"off"}}"#

  private func serve(_ directory: URL, extra: [String] = ["--time-zone", "America/Los_Angeles"], now: ManualNow = ManualNow(ScheduleServeTests.start), link: HubLink = HubLink()) async throws -> (server: RunningServer, link: HubLink) {
    let server = try await start(directory, extra: ["--hub", "192.168.1.20"] + extra, now: { now.now }, openModem: opener(ScriptedHubOpener([.connect(link)], catalog: nil, clock: SteppingClock())))
    _ = await server.code("modem_connected")
    return (server, link)
  }

  private func schedulesFile(_ directory: URL) -> URL {
    FileSchedulePersistence.url(besideState: directory.appendingPathComponent("state.json").path)
  }

  // MARK: Files and options

  @Test func schedulesAndTimersSurviveARestartInAPrivateFileBesideTheStateFile() async throws {
    let directory = try scratch()
    let (first, _) = try await serve(directory)
    _ = try await first.request("/api/v1/schedules/morning", method: "PUT", body: Self.morning, password: gatewayPassword)
    _ = try await first.request("/api/v1/timers/porch-off", method: "PUT", body: #"{"name":"Porch off","delaySeconds":3600,"action":{"device":"1A.2B.3C","action":"off"}}"#, password: gatewayPassword)
    await first.stop()

    let url = schedulesFile(directory)
    #expect(url.lastPathComponent == "state-schedules.json")
    #expect(try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int == 0o600)

    let (second, _) = try await serve(directory)
    let schedules = try await second.request("/api/v1/schedules", password: gatewayPassword)
    #expect((schedules.json["schedules"] as? [[String: Any]])?.map { $0["id"] as? String } == ["morning"])
    let timers = try await second.request("/api/v1/timers", password: gatewayPassword)
    let timer = try #require((timers.json["timers"] as? [[String: Any]])?.first)
    #expect(timer["id"] as? String == "porch-off")
    // The first server stopped at once, so the timer has nearly all of its hour left, counted in elapsed time.
    #expect((3590...3600).contains(try #require(timer["remainingSeconds"] as? Int)))
    await second.stop()
  }

  @Test func theTimeZoneAndLocationTheServerRanWithAreRememberedAndANewOptionRecomputesTheNextRun() async throws {
    let directory = try scratch()
    let (first, _) = try await serve(directory, extra: ["--time-zone", "America/Los_Angeles"] + Self.location)
    let stored = try await first.request("/api/v1/schedules/morning", method: "PUT", body: Self.morning, password: gatewayPassword)
    #expect(((stored.json["schedule"] as? [String: Any])?["nextRun"]) as? String == "2026-03-08T15:00:00Z")
    await first.stop()

    // No options: the time zone and the location are remembered.
    let (second, _) = try await serve(directory, extra: [])
    let remembered = try await second.request("/api/v1/schedules", password: gatewayPassword)
    #expect((remembered.json["schedules"] as? [[String: Any]])?.first?["nextRun"] as? String == "2026-03-08T15:00:00Z")
    let dusk = try await second.request("/api/v1/schedules/dusk", method: "PUT", body: Self.dusk, password: gatewayPassword)
    #expect(dusk.status == 200)
    await second.stop()

    // A new time zone moves every schedule: 8:00 a.m. in London is 08:00 UTC.
    let (third, _) = try await serve(directory, extra: ["--time-zone", "Europe/London"])
    let moved = try await third.request("/api/v1/schedules", password: gatewayPassword)
    let morning = try #require((moved.json["schedules"] as? [[String: Any]])?.first { $0["id"] as? String == "morning" })
    #expect(morning["nextRun"] as? String == "2026-03-08T08:00:00Z")
    await third.stop()
  }

  @Test func aSunScheduleWithoutALocationIsRefusedNamingWhatIsMissing() async throws {
    let (server, _) = try await serve(try scratch())
    let refused = try await server.request("/api/v1/schedules/dusk", method: "PUT", body: Self.dusk, password: gatewayPassword)
    #expect(refused.status == 409)
    #expect(refused.json["code"] as? String == "locationNotConfigured")
    #expect((refused.json["message"] as? String)?.contains("--latitude") == true)
    let clock = try await server.request("/api/v1/schedules/morning", method: "PUT", body: Self.morning, password: gatewayPassword)
    #expect(clock.status == 200)
    await server.stop()
  }

  @Test func aTimeZoneTheHostDoesntHaveIsAHealthNoteAndClockSchedulesAreRefused() async throws {
    let (server, _) = try await serve(try scratch(), extra: ["--time-zone", "Not/AZone"])
    let health = try await server.request("/api/v1/health", password: gatewayPassword)
    #expect((health.json["notes"] as? [[String: Any]])?.map { $0["code"] as? String } == ["timeZoneUnavailable"])
    let refused = try await server.request("/api/v1/schedules/morning", method: "PUT", body: Self.morning, password: gatewayPassword)
    #expect(refused.status == 409)
    #expect(refused.json["code"] as? String == "timeZoneUnavailable")
    await server.stop()
  }

  @Test func aSchedulesFileThatCannotBeReadStopsTheServerBeforeItListens() async throws {
    let directory = try scratch()
    try Data("garbage".utf8).write(to: schedulesFile(directory))
    let environment = ["HOME": directory.path, "INSTEON_GATEWAY_PASSWORD": gatewayPassword, "INSTEON_HUB_USERNAME": "hub-user", "INSTEON_HUB_PASSWORD": "hub-secret-pass"]
    do {
      try await ServerRunner.run(arguments: ["--state", directory.appendingPathComponent("state.json").path, "--hub", "192.168.1.20"], environment: environment, openModem: opener(ScriptedHubOpener([])))
      Issue.record("the server should not start")
    } catch {
      #expect(ServerFailure(error).code == .schedulesFileUnusable)
    }
  }

  // MARK: Running

  @Test func aScheduleThatIsDueSendsItsCommandAndPublishesOneScheduleEvent() async throws {
    let now = ManualNow(Self.start)
    let (server, _) = try await serve(try scratch(), now: now)
    let created = try await server.request("/api/v1/clients", method: "POST", body: #"{"name":"Watcher","scope":"read"}"#, password: gatewayPassword)
    let token = try #require((created.json["pairing"] as? [String: Any])?["credential"] as? String)
    let reader = EventStreamReader(port: server.port, password: gatewayPassword, bearer: token)
    var ready = reader.ready.makeAsyncIterator()
    _ = await ready.next()
    var frames = reader.frames.makeAsyncIterator()

    _ = try await server.request("/api/v1/schedules/morning", method: "PUT", body: Self.morning, password: gatewayPassword)
    // 8:00 a.m. on March 8 is 15:00 UTC, 19 hours after the start. Any change wakes the scheduler, which then
    // looks at the clock.
    now.advance(by: 19 * 3600)
    _ = try await server.request("/api/v1/schedules/spare", method: "PUT", body: #"{"name":"Spare","enabled":false,"when":{"time":{"kind":"clock","hour":9,"minute":0}},"action":{"device":"1A.2B.3C","action":"off"}}"#, password: gatewayPassword)

    var seen: [[String: Any]] = []
    while let frame = await frames.next() {
      seen.append(frame.json)
      if frame.json["kind"] as? String == "schedule" { break }
    }
    reader.close()
    await server.stop()

    let kinds = seen.compactMap { $0["kind"] as? String }
    #expect(kinds == ["commandCompleted", "schedule"])
    let run = try #require(seen.last)
    #expect(run["scheduleId"] as? String == "morning" && run["name"] as? String == "Morning" && run["source"] as? String == "schedule")
    #expect(run["address"] as? String == "1A.2B.3C" && run["outcome"] as? String == "acknowledged")
    #expect(run["nextRun"] as? String == "2026-03-09T15:00:00Z")
    let completion = try #require(seen.first?["completion"] as? [String: Any])
    #expect(completion["action"] as? String == "on" && completion["levelPercent"] as? Int == 50)
  }
}
