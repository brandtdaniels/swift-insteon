import InsteonClient
import InsteonProtocol
import InsteonService
import Testing

@Suite("ClientConnection gives the scene calls the rules of the other calls", .timeLimit(.minutes(1)))
struct ClientConnectionSceneTests {

  // MARK: Reads

  @Test func theListingComesFromTheFirstPathThatAnswers() async throws {
    let remote = ScriptedPath("remote")
    let connection = ClientConnection(paths: [ScriptedPath("local", openings: [.notReached("no Hub answered")]), remote])

    let list = try await connection.scenes()

    #expect(list.scenes.map(\.number) == [2])
    #expect(await connection.currentPath == "remote")
  }

  @Test func aListingThatLosesItsPathIsAskedAgainOnTheSamePath() async throws {
    let calls = ScriptedCalls(label: "local", script: [.interrupted])
    let connection = ClientConnection(paths: [ScriptedPath("local", calls: calls)])

    let list = try await connection.scenes()

    #expect(list.scenes.map(\.number) == [1])
    #expect(await calls.asked == ["scenes", "scenes"])
    #expect(await connection.currentPath == "local")
  }

  @Test func aListingThatLosesEveryPathIsInterruptedAfterOneRetryOnEach() async throws {
    let calls = ScriptedCalls(label: "local", script: [.interrupted, .interrupted])
    let connection = ClientConnection(paths: [ScriptedPath("local", calls: calls)])

    await #expect(throws: ConnectionError.interrupted(path: "local")) { try await connection.scenes() }
    #expect(await calls.asked == ["scenes", "scenes"])
  }

  // MARK: Refresh

  @Test func aRefreshIsNeverRepeatedAfterItMayHaveReachedTheHardware() async throws {
    let calls = ScriptedCalls(label: "local", script: [.interrupted])
    let connection = ClientConnection(paths: [ScriptedPath("local", calls: calls), ScriptedPath("remote")])

    await #expect(throws: ConnectionError.interrupted(path: "local")) { try await connection.refreshScenes() }
    #expect(await calls.asked == ["refreshScenes"])
    #expect(await connection.currentPath == nil, "the next call opens a path again")
  }

  @Test func aRefreshThatWasNeverSentMovesToTheNextPath() async throws {
    let local = ScriptedPath("local", calls: ScriptedCalls(label: "local", script: [.notReached]))
    let remote = ScriptedPath("remote")
    let connection = ClientConnection(paths: [local, remote])

    let list = try await connection.refreshScenes()

    #expect(list.scenes.map(\.number) == [2])
    #expect(await remote.calls.asked == ["refreshScenes"])
  }

  // MARK: Runs

  @Test func aRunThatMayHaveBeenSentIsNeverRepeatedOnAnyPath() async throws {
    let calls = ScriptedCalls(label: "local", script: [.interrupted])
    let remote = ScriptedPath("remote")
    let connection = ClientConnection(paths: [ScriptedPath("local", calls: calls), remote])

    await #expect(throws: ConnectionError.interrupted(path: "local")) { try await connection.runScene(3, action: .on) }
    #expect(await calls.asked == ["runScene"])
    #expect(await remote.openCount == 0)
    #expect(await connection.currentPath == nil)
  }

  @Test func aRunThatGotABadResponseIsReportedAndNeverAskedAgain() async throws {
    let calls = ScriptedCalls(label: "local", script: [.badResponse])
    let connection = ClientConnection(paths: [ScriptedPath("local", calls: calls)])

    await #expect(throws: ConnectionError.badResponse(path: "local")) { try await connection.runScene(3, action: .off) }
    #expect(await calls.asked == ["runScene"])
  }

  @Test func aRunThatWasNeverSentMovesToTheNextPathWithTheSameKey() async throws {
    let local = ScriptedPath("local", calls: ScriptedCalls(label: "local", script: [.notReached]))
    let remote = ScriptedPath("remote")
    let connection = ClientConnection(paths: [local, remote])

    let receipt = try await connection.runScene(3, action: .on)

    #expect(receipt.scene == 3 && receipt.action == .on)
    let first = await local.calls.sceneKeys
    let second = await remote.calls.sceneKeys
    #expect(first.count == 1 && first == second)
  }

  @Test func eachRunGetsAKeyOfItsOwnThatThePathAcceptsAsAnIdempotencyKey() async throws {
    let calls = ScriptedCalls(label: "local")
    let connection = ClientConnection(paths: [ScriptedPath("local", calls: calls)])

    _ = try await connection.runScene(3, action: .on)
    _ = try await connection.runScene(3, action: .on)

    let keys = await calls.sceneKeys
    #expect(keys.count == 2 && keys[0] != keys[1])
    for key in keys {
      #expect((1...128).contains(key.count))
      #expect(key.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._~:-".contains($0)) })
    }
  }

  @Test func aKeyTheCallerGivesIsUsedSoARetryAfterALostAnswerSendsNothingTwice() async throws {
    let calls = ScriptedCalls(label: "local", script: [.interrupted])
    let connection = ClientConnection(paths: [ScriptedPath("local", calls: calls)])

    await #expect(throws: ConnectionError.interrupted(path: "local")) { try await connection.runScene(3, action: .on, idempotencyKey: "evening-1") }
    _ = try await connection.runScene(3, action: .on, idempotencyKey: "evening-1")

    #expect(await calls.sceneKeys == ["evening-1", "evening-1"])
  }

  // MARK: Credentials and paths that don't carry scenes

  @Test func aScopeTooLowOnEveryPathIsReportedForARunAndARefreshAndNothingIsRepeated() async throws {
    let calls = ScriptedCalls(label: "local", script: [.forbidden, .forbidden])
    let connection = ClientConnection(paths: [ScriptedPath("local", calls: calls)])

    await #expect(throws: ConnectionError.forbidden(path: "local")) { try await connection.runScene(3, action: .on) }
    await #expect(throws: ConnectionError.forbidden(path: "local")) { try await connection.refreshScenes() }
    #expect(await calls.asked == ["runScene", "refreshScenes"])
  }

  @Test func aPathThatCarriesNoScenesIsUnsupported() async throws {
    let connection = ClientConnection(paths: [EventPath("local", subscriptions: [])])

    await #expect(throws: ConnectionError.unsupported(paths: ["local"])) { try await connection.scenes() }
    await #expect(throws: ConnectionError.unsupported(paths: ["local"])) { try await connection.refreshScenes() }
    await #expect(throws: ConnectionError.unsupported(paths: ["local"])) { try await connection.runScene(3, action: .on) }
  }
}
