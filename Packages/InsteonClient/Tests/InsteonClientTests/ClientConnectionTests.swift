import InsteonClient
import InsteonService
import Testing

@Suite("ClientConnection chooses a path and gives the same calls on each", .timeLimit(.minutes(1)))
struct ClientConnectionTests {

  @Test func theFirstPathThatOpensAnswersAndTheLaterOnesAreNeverOpened() async throws {
    let local = ScriptedPath("local")
    let remote = ScriptedPath("remote")
    let connection = ClientConnection(paths: [local, remote])

    let devices = try await connection.devices()

    #expect(devices.first?.value == 1)
    #expect(await remote.openCount == 0)
    #expect(await connection.currentPath == "local")
  }

  @Test func aPathThatCannotBeReachedPassesTheCallToTheNextPath() async throws {
    let local = ScriptedPath("local", openings: [.notReached("no Hub answered")])
    let remote = ScriptedPath("remote")
    let connection = ClientConnection(paths: [local, remote])

    let devices = try await connection.devices()

    #expect(devices.first?.value == 2)
    #expect(await connection.currentPath == "remote")
  }

  @Test func whenNoPathIsReachedTheErrorNamesEachPathAndWhy() async throws {
    let connection = ClientConnection(paths: [
      ScriptedPath("local", openings: [.notReached("no Hub answered")]),
      ScriptedPath("remote", openings: [.notReached("no route")])
    ])

    await #expect(throws: ConnectionError.noPathReached([
      PathFailure(path: "local", reason: "no Hub answered"),
      PathFailure(path: "remote", reason: "no route")
    ])) { try await connection.devices() }
    #expect(await connection.currentPath == nil)
  }

  @Test func aConnectionWithNoPathsReachesNothing() async {
    let connection = ClientConnection(paths: [])

    await #expect(throws: ConnectionError.noPathReached([])) { try await connection.devices() }
  }

  @Test func theOpenPathIsKeptBetweenCalls() async throws {
    let local = ScriptedPath("local")
    let connection = ClientConnection(paths: [local])

    _ = try await connection.devices()
    _ = try await connection.devices()

    #expect(await local.openCount == 1)
  }

  @Test func aReadThatLosesItsPathIsAskedAgainOnTheSamePathBeforeItIsDropped() async throws {
    let local = ScriptedPath("local", calls: ScriptedCalls(label: "local", script: [.interrupted]))
    let remote = ScriptedPath("remote")
    let connection = ClientConnection(paths: [local, remote])

    let devices = try await connection.devices()

    #expect(devices.first?.value == 1, "a blip on a healthy path does not drop it")
    #expect(await local.openCount == 1)
    #expect(await remote.openCount == 0)
    #expect(await connection.currentPath == "local")
  }

  @Test func aReadThatLosesItsPathTwiceMovesToTheNextPathAndClosesTheLostOne() async throws {
    let lostCalls = ScriptedCalls(label: "local", script: [.interrupted, .interrupted])
    let local = ScriptedPath("local", calls: lostCalls)
    let remote = ScriptedPath("remote")
    let connection = ClientConnection(paths: [local, remote])

    let devices = try await connection.devices()

    #expect(devices.first?.value == 2)
    #expect(await local.openCount == 1)
    #expect(await lostCalls.isClosed)
    #expect(await connection.currentPath == "remote")
  }

  @Test func aReadThatLosesEveryPathFailsAfterOneRetryOnEach() async throws {
    let local = ScriptedPath("local", calls: ScriptedCalls(label: "local", script: [.interrupted, .interrupted, .interrupted]))
    let connection = ClientConnection(paths: [local])

    await #expect(throws: ConnectionError.interrupted(path: "local")) { try await connection.devices() }
    #expect(await local.openCount == 1)
    #expect(await connection.currentPath == nil)
  }

  @Test func aCommandThatMayHaveBeenSentIsNeverRepeated() async throws {
    let calls = ScriptedCalls(label: "local", script: [.interrupted])
    let local = ScriptedPath("local", calls: calls)
    let connection = ClientConnection(paths: [local])

    await #expect(throws: ConnectionError.interrupted(path: "local")) {
      try await connection.execute(ServiceCommand(address: lampAddress, action: .on))
    }
    #expect(await calls.asked == ["execute"])
    #expect(await connection.currentPath == nil, "the next call opens a path again")
  }

  @Test func aCommandThatWasNeverSentMovesToTheNextPath() async throws {
    let local = ScriptedPath("local", openings: [nil, .notReached("gone")], calls: ScriptedCalls(label: "local", script: [.notReached]))
    let remote = ScriptedPath("remote")
    let connection = ClientConnection(paths: [local, remote])

    let receipt = try await connection.execute(ServiceCommand(address: lampAddress, action: .off))

    #expect(receipt.address == lampAddress)
    #expect(await remote.calls.asked == ["execute"])
  }

  @Test func aPathThatRefusesTheCredentialDoesNotStopTheSearchForAnotherPath() async throws {
    let remote = ScriptedPath("remote")
    let connection = ClientConnection(paths: [ScriptedPath("lan", openings: [.unauthorized]), remote])

    let devices = try await connection.devices()

    #expect(devices.first?.value == 2)
    #expect(await connection.currentPath == "remote")
  }

  @Test func whenEveryPathRefusedTheCredentialTheErrorNamesEachOne() async throws {
    let connection = ClientConnection(paths: [ScriptedPath("lan", openings: [.unauthorized]), ScriptedPath("remote", openings: [.unauthorized])])

    await #expect(throws: ConnectionError.unauthorized(paths: ["lan", "remote"])) { try await connection.devices() }
  }

  @Test func aRefusalAmongPathsThatWereNotReachedIsNamedInTheReasons() async throws {
    let connection = ClientConnection(paths: [ScriptedPath("lan", openings: [.unauthorized]), ScriptedPath("remote", openings: [.notReached("no route")])])

    await #expect(throws: ConnectionError.noPathReached([
      PathFailure(path: "lan", reason: "the credential was refused"),
      PathFailure(path: "remote", reason: "no route")
    ])) { try await connection.devices() }
  }

  @Test func theCallsAreTheServiceRolesSoAnyCodeThatUsesTheServiceUsesTheConnection() async throws {
    func list(_ source: some DeviceQuerying & DeviceCommanding) async throws -> Int { try await source.devices().count }
    let connection = ClientConnection(paths: [ScriptedPath("local")])

    #expect(try await list(connection) == 1)
  }

  @Test func aCredentialRefusedOnAnOpenPathIsReportedAndThePathIsDropped() async throws {
    let local = ScriptedPath("local", calls: ScriptedCalls(label: "local", script: [.unauthorized, .unauthorized]))
    let connection = ClientConnection(paths: [local])

    await #expect(throws: ConnectionError.unauthorized(paths: ["local"])) { try await connection.devices() }
    #expect(await connection.currentPath == nil)
    await #expect(throws: ConnectionError.unauthorized(paths: ["local"])) {
      try await connection.execute(ServiceCommand(address: lampAddress, action: .on))
    }
    #expect(await connection.currentPath == nil)
  }

  @Test func everyPathIsTriedOncePerCallAndTheLastLossIsReported() async throws {
    let local = ScriptedPath("local", calls: ScriptedCalls(label: "local", script: [.interrupted, .interrupted]))
    let remote = ScriptedPath("remote", calls: ScriptedCalls(label: "remote", script: [.interrupted, .interrupted]))
    let connection = ClientConnection(paths: [local, remote])

    await #expect(throws: ConnectionError.interrupted(path: "remote")) { try await connection.devices() }
    #expect(await local.openCount == 1)
    #expect(await remote.openCount == 1)
  }

  @Test func aReadThatGotABadResponseIsAskedOnAnotherPathAndTheBadPathIsDropped() async throws {
    let local = ScriptedPath("local", calls: ScriptedCalls(label: "local", script: [.badResponse]))
    let remote = ScriptedPath("remote")
    let connection = ClientConnection(paths: [local, remote])

    let devices = try await connection.devices()

    #expect(devices.first?.value == 2)
    #expect(await connection.currentPath == "remote")
  }

  @Test func aCommandThatGotABadResponseIsReportedAndNeverAskedAgain() async throws {
    let calls = ScriptedCalls(label: "local", script: [.badResponse])
    let remote = ScriptedPath("remote")
    let connection = ClientConnection(paths: [ScriptedPath("local", calls: calls), remote])

    await #expect(throws: ConnectionError.badResponse(path: "local")) { try await connection.execute(ServiceCommand(address: lampAddress, action: .on)) }
    #expect(await calls.asked == ["execute"])
    #expect(await remote.openCount == 0)
    #expect(await connection.currentPath == nil, "the next call checks the path again")
  }

  @Test func aScopeTooLowOnOnePathStillTriesTheOthersBeforeReportingIt() async throws {
    let local = ScriptedPath("local", calls: ScriptedCalls(label: "local", script: [.forbidden]))
    let remote = ScriptedPath("remote")
    let connection = ClientConnection(paths: [local, remote])

    let receipt = try await connection.execute(ServiceCommand(address: lampAddress, action: .on))

    #expect(receipt.address == lampAddress)
    #expect(await connection.currentPath == "remote")
  }

  @Test func aScopeTooLowOnEveryPathIsReportedAndNothingIsRepeated() async throws {
    let calls = ScriptedCalls(label: "local", script: [.forbidden])
    let connection = ClientConnection(paths: [ScriptedPath("local", calls: calls)])

    await #expect(throws: ConnectionError.forbidden(path: "local")) { try await connection.execute(ServiceCommand(address: lampAddress, action: .on)) }
    #expect(await calls.asked == ["execute"])
    #expect(await connection.currentPath == "local", "the forbidden path is kept when no other path takes over")
  }

  @Test func aPathWhoseScopeIsTooLowToOpenIsNamedAndTheSearchGoesOn() async throws {
    let connection = ClientConnection(paths: [ScriptedPath("lan", openings: [.forbidden]), ScriptedPath("remote")])

    _ = try await connection.devices()

    #expect(await connection.currentPath == "remote")
  }

  @Test func aStaleFailureDoesNotDropANewerHealthyPath() async throws {
    let gated = GatedCalls()
    let local = ScriptedPath("local", calls: nil, gated: gated)
    let remote = ScriptedPath("remote")
    let connection = ClientConnection(paths: [local, remote])

    let slow = Task { try await connection.devices() }
    await gated.waitUntilHeld()
    // A second read fails on the same path, drops it and finds the remote one.
    let fast = try await connection.devices()
    #expect(fast.first?.value == 2)
    #expect(await connection.currentPath == "remote")

    await gated.letGo()
    let slowResult = try await slow.value

    #expect(slowResult.first?.value == 2)
    #expect(await connection.currentPath == "remote")
    #expect(await remote.openCount == 1, "the late failure of the old path did not drop the healthy one")
  }

  @Test func aReadThatWasNeverSentIsTreatedLikeACommandThatWasNeverSent() async throws {
    let local = ScriptedPath("local", calls: ScriptedCalls(label: "local", script: [.notReached]))
    let connection = ClientConnection(paths: [local])

    await #expect(throws: ConnectionError.noPathReached([PathFailure(path: "local", reason: "scripted")])) { try await connection.devices() }
    #expect(await connection.currentPath == nil)
  }

  @Test func whenTwoCallsOpenTheSamePathTheLoserIsClosedAndTheWinnerIsUsed() async throws {
    let path = GatedOpenPath()
    let connection = ClientConnection(paths: [path])

    let first = Task { try await connection.devices() }
    await path.waitUntilFirstOpeningIsWaiting()
    _ = try await connection.devices()
    await path.letFirstOpeningGo()
    _ = try await first.value

    let opened = await path.opened
    #expect(opened.count == 2)
    #expect(await opened[0].isClosed, "the opening that lost the race is closed")
    #expect(await !opened[1].isClosed)
    #expect(await opened[0].asked.isEmpty, "the loser's calls were never used")
  }

  @Test func whenEveryAttemptRunsOutTheReasonsAreKept() async throws {
    let local = ScriptedPath("local", calls: ScriptedCalls(label: "local", script: [.notReached]))
    let connection = ClientConnection(paths: [local], skipped: [PathFailure(path: "mystery", reason: "no transport")])

    await #expect(throws: ConnectionError.noPathReached([
      PathFailure(path: "mystery", reason: "no transport"),
      PathFailure(path: "local", reason: "scripted")
    ])) { try await connection.execute(ServiceCommand(address: lampAddress, action: .on)) }
  }

  @Test func anyOtherErrorFromOpeningAPathIsThatPathsFailureAndTheSearchGoesOn() async throws {
    let connection = ClientConnection(paths: [BrokenPath(), ScriptedPath("remote")])

    _ = try await connection.devices()

    #expect(await connection.currentPath == "remote")
  }

  @Test func whenOnlyBrokenPathsRemainTheirFailureIsNamed() async throws {
    let connection = ClientConnection(paths: [BrokenPath()])

    await #expect(throws: ConnectionError.noPathReached([PathFailure(path: "broken", reason: "the path failed to open")])) { try await connection.devices() }
  }

  @Test func cancellationWhileOpeningStillPropagates() async throws {
    let connection = ClientConnection(paths: [CancelingPath(), ScriptedPath("remote")])

    await #expect(throws: CancellationError.self) { _ = try await connection.devices() }
  }
  @Test func aScopeTooLowOnOnePathClosesItsCallsWhenAnotherPathTakesOver() async throws {
    let forbiddenCalls = ScriptedCalls(label: "local", script: [.forbidden])
    let connection = ClientConnection(paths: [ScriptedPath("local", calls: forbiddenCalls), ScriptedPath("remote")])

    _ = try await connection.execute(ServiceCommand(address: lampAddress, action: .on))

    #expect(await forbiddenCalls.isClosed)
  }

  @Test func closingTheConnectionClosesTheOpenCalls() async throws {
    let calls = ScriptedCalls(label: "local")
    let connection = ClientConnection(paths: [ScriptedPath("local", calls: calls)])
    _ = try await connection.devices()

    await connection.close()

    #expect(await calls.isClosed)
    #expect(await connection.currentPath == nil)
  }

  @Test func aCredentialRefusedOnTheOpenPathTriesTheOtherPathsAndClosesTheRefusedOne() async throws {
    let refused = ScriptedCalls(label: "local", script: [.unauthorized])
    let connection = ClientConnection(paths: [ScriptedPath("local", calls: refused), ScriptedPath("remote")])

    let devices = try await connection.devices()

    #expect(devices.first?.value == 2)
    #expect(await refused.isClosed)
  }

  @Test func whenEveryOpenPathRefusesTheCredentialOnACallTheErrorNamesThemAll() async throws {
    let connection = ClientConnection(paths: [
      ScriptedPath("local", calls: ScriptedCalls(label: "local", script: [.unauthorized])),
      ScriptedPath("remote", calls: ScriptedCalls(label: "remote", script: [.unauthorized]))
    ])

    await #expect(throws: ConnectionError.unauthorized(paths: ["local", "remote"])) { try await connection.devices() }
  }

  @Test func aCommandThatWasNeverSentWalksEveryRemainingPath() async throws {
    let paths = ["a", "b", "c"].map { ScriptedPath($0, calls: ScriptedCalls(label: $0, script: $0 == "c" ? [] : [.notReached])) }
    let connection = ClientConnection(paths: paths)

    let receipt = try await connection.execute(ServiceCommand(address: lampAddress, action: .on))

    #expect(receipt.address == lampAddress)
    #expect(await connection.currentPath == "c")
  }

  @Test func aScopeTooLowIsReportedEvenWhenTheOtherPathsCannotBeReached() async throws {
    let connection = ClientConnection(paths: [
      ScriptedPath("local", calls: ScriptedCalls(label: "local", script: [.forbidden])),
      ScriptedPath("remote", openings: [.notReached("no route")])
    ])

    await #expect(throws: ConnectionError.forbidden(path: "local")) { try await connection.execute(ServiceCommand(address: lampAddress, action: .on)) }
  }

  @Test func aScopeTooLowIsReportedEvenWhenAnotherPathRefusesTheCredential() async throws {
    let connection = ClientConnection(paths: [
      ScriptedPath("local", calls: ScriptedCalls(label: "local", script: [.forbidden])),
      ScriptedPath("remote", openings: [.unauthorized])
    ])

    await #expect(throws: ConnectionError.forbidden(path: "local")) { try await connection.devices() }
  }

}

struct BrokenPath: ConnectionPath {
  let name = "broken"
  func open() async throws -> any ConnectionCalls { throw Unplugged() }
}

struct CancelingPath: ConnectionPath {
  let name = "canceling"
  func open() async throws -> any ConnectionCalls { throw CancellationError() }
}
