import InsteonClient
import InsteonHubClient
import InsteonHubDiscovery
import InsteonService
import Testing

private func hub(_ host: String) -> DiscoveredHub { DiscoveredHub(endpoint: HubEndpoint(host: host)) }

@Suite("LocalHubPath reaches a Hub found on the local network", .timeLimit(.minutes(1)))
struct LocalHubPathTests {

  @Test func theFirstHubFoundIsOpened() async throws {
    let calls = ScriptedCalls(label: "local")
    let opened = OpenedHosts()
    let path = LocalHubPath(
      locate: { [hub("192.0.2.31"), hub("192.0.2.32")] },
      open: { found in await opened.add(found.endpoint.host); return calls }
    )

    let opening = try await path.open()

    #expect(await opened.hosts == ["192.0.2.31"], "the first Hub that opens is used and the rest are left alone")
    #expect(try await opening.devices().count == 1)
    #expect(path.name == "local network")
  }

  @Test func noHubFoundIsNotReached() async {
    let path = LocalHubPath(locate: { [] }, open: { _ in ScriptedCalls(label: "local") })

    await #expect(throws: ConnectionPathError.notReached("no Hub answered on the local network")) { _ = try await path.open() }
  }

  @Test func aSearchThatFailsIsNotReached() async {
    let path = LocalHubPath(locate: { throw Unplugged() }, open: { _ in ScriptedCalls(label: "local") })

    do { _ = try await path.open(); Issue.record("opened") } catch let error as ConnectionPathError {
      guard case .notReached = error else { Issue.record("expected notReached, got \(error)"); return }
    } catch { Issue.record("unexpected \(error)") }
  }

  @Test func aHubThatCannotBeOpenedIsNotReached() async {
    let path = LocalHubPath(locate: { [hub("192.0.2.31")] }, open: { _ in throw Unplugged() })

    do { _ = try await path.open(); Issue.record("opened") } catch let error as ConnectionPathError {
      guard case .notReached = error else { Issue.record("expected notReached, got \(error)"); return }
    } catch { Issue.record("unexpected \(error)") }
  }

  @Test func aPathErrorFromTheOpenerPassesThrough() async {
    let path = LocalHubPath(locate: { [hub("192.0.2.31")] }, open: { _ in throw ConnectionPathError.unauthorized })

    await #expect(throws: ConnectionPathError.unauthorized) { _ = try await path.open() }
  }

  @Test func eachHubIsTriedInOrderUntilOneOpens() async throws {
    let opened = OpenedHosts()
    let path = LocalHubPath(
      locate: { [hub("192.0.2.31"), hub("192.0.2.32"), hub("192.0.2.33")] },
      open: { found in
        await opened.add(found.endpoint.host)
        if found.endpoint.host == "192.0.2.33" { return ScriptedCalls(label: "local") }
        throw Unplugged()
      }
    )

    _ = try await path.open()

    #expect(await opened.hosts == ["192.0.2.31", "192.0.2.32", "192.0.2.33"])
  }

  @Test func whenNoHubOpensTheLastReasonIsGivenAndARefusedCredentialWins() async {
    let refused = LocalHubPath(
      locate: { [hub("192.0.2.31"), hub("192.0.2.32")] },
      open: { found in
        if found.endpoint.host == "192.0.2.31" { throw ConnectionPathError.unauthorized }
        throw Unplugged()
      }
    )
    await #expect(throws: ConnectionPathError.unauthorized) { _ = try await refused.open() }

    let none = LocalHubPath(locate: { [hub("192.0.2.31"), hub("192.0.2.32")] }, open: { _ in throw Unplugged() })
    await #expect(throws: ConnectionPathError.notReached("no Hub on the local network opened")) { _ = try await none.open() }
  }

  @Test func aScopeTooLowOrABadResponseFromEveryHubIsThePathsOwnFailure() async {
    let forbidden = LocalHubPath(locate: { [hub("192.0.2.31")] }, open: { _ in throw ConnectionPathError.forbidden })
    await #expect(throws: ConnectionPathError.forbidden) { _ = try await forbidden.open() }
    let bad = LocalHubPath(locate: { [hub("192.0.2.31"), hub("192.0.2.32")] }, open: { _ in throw ConnectionPathError.badResponse })
    await #expect(throws: ConnectionPathError.badResponse) { _ = try await bad.open() }
  }

  @Test func aRefusedCredentialOutranksAScopeTooLowOutranksABadResponse() async {
    let path = LocalHubPath(locate: { [hub("192.0.2.31"), hub("192.0.2.32"), hub("192.0.2.33")] }, open: { found in
      switch found.endpoint.host {
      case "192.0.2.31": throw ConnectionPathError.badResponse
      case "192.0.2.32": throw ConnectionPathError.forbidden
      default: throw ConnectionPathError.unauthorized
      }
    })
    await #expect(throws: ConnectionPathError.unauthorized) { _ = try await path.open() }
  }

  @Test func aLostPathFromAnOpenerCountsAsNotReached() async {
    let path = LocalHubPath(locate: { [hub("192.0.2.31")] }, open: { _ in throw ConnectionPathError.interrupted })

    await #expect(throws: ConnectionPathError.notReached("no Hub on the local network opened")) { _ = try await path.open() }
  }
}

actor OpenedHosts {
  private(set) var hosts: [String] = []
  func add(_ host: String) { hosts.append(host) }
}
