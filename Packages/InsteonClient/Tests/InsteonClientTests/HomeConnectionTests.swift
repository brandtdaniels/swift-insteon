import InsteonClient
import InsteonService
import Testing

@Suite("HomeConnection chooses a path and gives the same calls on each", .timeLimit(.minutes(1)))
struct HomeConnectionTests {

  @Test func theFirstPathThatOpensAnswersAndTheLaterOnesAreNeverOpened() async throws {
    let local = ScriptedPath("local")
    let remote = ScriptedPath("remote")
    let home = HomeConnection(paths: [local, remote])

    let devices = try await home.devices()

    #expect(devices.first?.value == 1)
    #expect(await remote.openCount == 0)
    #expect(await home.currentPath == "local")
  }

  @Test func aPathThatCannotBeReachedPassesTheCallToTheNextPath() async throws {
    let local = ScriptedPath("local", openings: [.notReached("no Hub answered")])
    let remote = ScriptedPath("remote")
    let home = HomeConnection(paths: [local, remote])

    let devices = try await home.devices()

    #expect(devices.first?.value == 2)
    #expect(await home.currentPath == "remote")
  }

  @Test func whenNoPathIsReachedTheErrorNamesEachPathAndWhy() async throws {
    let home = HomeConnection(paths: [
      ScriptedPath("local", openings: [.notReached("no Hub answered")]),
      ScriptedPath("remote", openings: [.notReached("no route")])
    ])

    await #expect(throws: HomeError.noPathReached([
      PathFailure(path: "local", reason: "no Hub answered"),
      PathFailure(path: "remote", reason: "no route")
    ])) { try await home.devices() }
    #expect(await home.currentPath == nil)
  }

  @Test func aConnectionWithNoPathsReachesNothing() async {
    let home = HomeConnection(paths: [])

    await #expect(throws: HomeError.noPathReached([])) { try await home.devices() }
  }

  @Test func theOpenPathIsKeptBetweenCalls() async throws {
    let local = ScriptedPath("local")
    let home = HomeConnection(paths: [local])

    _ = try await home.devices()
    _ = try await home.devices()

    #expect(await local.openCount == 1)
  }

  @Test func aReadThatLosesItsPathIsAskedAgainOnTheNextPath() async throws {
    let local = ScriptedPath("local", calls: ScriptedCalls(label: "local", script: [.interrupted]))
    let remote = ScriptedPath("remote")
    let home = HomeConnection(paths: [local, remote])

    let devices = try await home.devices()

    #expect(devices.first?.value == 1, "the local path is tried first again and answers the second time")
    #expect(await local.openCount == 2)
    #expect(await remote.openCount == 0)
  }

  @Test func aReadThatLosesEveryPathFailsAfterOneRetry() async throws {
    let local = ScriptedPath("local", calls: ScriptedCalls(label: "local", script: [.interrupted, .interrupted, .interrupted]))
    let home = HomeConnection(paths: [local])

    await #expect(throws: HomeError.interrupted(path: "local")) { try await home.devices() }
    #expect(await local.openCount == 2)
    #expect(await home.currentPath == nil)
  }

  @Test func aCommandThatMayHaveBeenSentIsNeverRepeated() async throws {
    let calls = ScriptedCalls(label: "local", script: [.interrupted])
    let local = ScriptedPath("local", calls: calls)
    let home = HomeConnection(paths: [local])

    await #expect(throws: HomeError.interrupted(path: "local")) {
      try await home.execute(ServiceCommand(address: lampAddress, action: .on))
    }
    #expect(await calls.asked == ["execute"])
    #expect(await home.currentPath == nil, "the next call opens a path again")
  }

  @Test func aCommandThatWasNeverSentMovesToTheNextPath() async throws {
    let local = ScriptedPath("local", openings: [nil, .notReached("gone")], calls: ScriptedCalls(label: "local", script: [.notReached]))
    let remote = ScriptedPath("remote")
    let home = HomeConnection(paths: [local, remote])

    let receipt = try await home.execute(ServiceCommand(address: lampAddress, action: .off))

    #expect(receipt.address == lampAddress)
    #expect(await remote.calls.asked == ["execute"])
  }

  @Test func aPathThatRefusesTheCredentialStopsTheSearchInsteadOfTryingTheNext() async throws {
    let remote = ScriptedPath("remote")
    let home = HomeConnection(paths: [ScriptedPath("lan", openings: [.unauthorized]), remote])

    await #expect(throws: HomeError.unauthorized(path: "lan")) { try await home.devices() }
    #expect(await remote.openCount == 0)
  }

  @Test func theCallsAreTheServiceRolesSoAnyCodeThatUsesTheServiceUsesTheConnection() async throws {
    func list(_ source: some DeviceQuerying & DeviceCommanding) async throws -> Int { try await source.devices().count }
    let home = HomeConnection(paths: [ScriptedPath("local")])

    #expect(try await list(home) == 1)
  }

  @Test func aCredentialRefusedOnAnOpenPathIsReportedAndThePathIsDropped() async throws {
    let local = ScriptedPath("local", calls: ScriptedCalls(label: "local", script: [.unauthorized, .unauthorized]))
    let home = HomeConnection(paths: [local])

    await #expect(throws: HomeError.unauthorized(path: "local")) { try await home.devices() }
    #expect(await home.currentPath == nil)
    await #expect(throws: HomeError.unauthorized(path: "local")) {
      try await home.execute(ServiceCommand(address: lampAddress, action: .on))
    }
    #expect(await home.currentPath == nil)
  }
}
