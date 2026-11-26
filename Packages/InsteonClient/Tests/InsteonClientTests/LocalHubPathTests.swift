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

    #expect(await opened.hosts == ["192.0.2.31"])
    #expect(try await opening.devices().count == 1)
    #expect(path.name == "local network")
  }

  @Test func noHubFoundIsNotReached() async {
    let path = LocalHubPath(locate: { [] }, open: { _ in ScriptedCalls(label: "local") })

    await #expect(throws: HomePathError.notReached("no Hub answered on the local network")) { _ = try await path.open() }
  }

  @Test func aSearchThatFailsIsNotReached() async {
    let path = LocalHubPath(locate: { throw Unplugged() }, open: { _ in ScriptedCalls(label: "local") })

    do { _ = try await path.open(); Issue.record("opened") } catch let error as HomePathError {
      guard case .notReached = error else { Issue.record("expected notReached, got \(error)"); return }
    } catch { Issue.record("unexpected \(error)") }
  }

  @Test func aHubThatCannotBeOpenedIsNotReached() async {
    let path = LocalHubPath(locate: { [hub("192.0.2.31")] }, open: { _ in throw Unplugged() })

    do { _ = try await path.open(); Issue.record("opened") } catch let error as HomePathError {
      guard case .notReached = error else { Issue.record("expected notReached, got \(error)"); return }
    } catch { Issue.record("unexpected \(error)") }
  }

  @Test func aPathErrorFromTheOpenerPassesThrough() async {
    let path = LocalHubPath(locate: { [hub("192.0.2.31")] }, open: { _ in throw HomePathError.unauthorized })

    await #expect(throws: HomePathError.unauthorized) { _ = try await path.open() }
  }
}

actor OpenedHosts {
  private(set) var hosts: [String] = []
  func add(_ host: String) { hosts.append(host) }
}
