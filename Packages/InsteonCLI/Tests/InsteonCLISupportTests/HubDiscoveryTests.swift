import Testing
import InsteonCLISupport
import InsteonCore

@Suite(.timeLimit(.minutes(1)))
struct HubDiscoveryTests {

  struct Unreachable: Error, CustomStringConvertible {

    var description: String { "unreachable" }

  }

  /// What a search asked and said. A Hub here is its made-up address.
  final class Record {

    var notes: [String] = []

    var localStoppedAtFirst: [Bool] = []

  }

  private func search(
    _ options: DiscoverOptions,
    insteonConnect: Result<[String], any Error> = .success([]),
    localNetwork: Result<[String], any Error> = .success([]),
    record: Record = Record()
  ) async throws -> [String] {

    try await HubDiscovery.search(
      options,
      insteonConnect: { try insteonConnect.get() },
      localNetwork: { (stoppingAtFirst: Bool) throws -> [String] in

        record.localStoppedAtFirst.append(stoppingAtFirst)

        return try localNetwork.get()

      },
      merge: { (hub: String, hubs: inout [String]) -> Void in

        if !hubs.contains(hub) {

          hubs.append(hub)

        }

      },
      note: { record.notes.append($0) },
      message: { "\($0)" }
    )

  }

  // MARK: - Searching

  @Test func asksInsteonConnectFirstAndMergesWhatTheLocalSearchFinds() async throws {

    let record = Record()
    let hubs = try await search(
      DiscoverOptions(asksInsteonConnect: true),
      insteonConnect: .success(["192.168.0.20:25105"]),
      localNetwork: .success(["192.168.0.20:25105", "192.168.0.21:25105"]),
      record: record
    )

    #expect(hubs == ["192.168.0.20:25105", "192.168.0.21:25105"])
    #expect(record.notes == ["Asking Insteon Connect..."])

  }

  @Test func stopsTheLocalSearchAtTheFirstHubUnlessEveryAddressIsAsked() async throws {

    let record = Record()

    _ = try await search(DiscoverOptions(), record: record)
    _ = try await search(DiscoverOptions(searchesAllAddresses: true), record: record)

    #expect(record.localStoppedAtFirst == [true, false])

  }

  @Test func suggestsInsteonConnectWhenNoHubAnswersLocally() async throws {

    let record = Record()
    let hubs = try await search(DiscoverOptions(), record: record)

    #expect(hubs.isEmpty)
    #expect(
      record.notes == [
        "No Hub answered on the local network. 'insteon discover --insteon-connect' asks Insteon Connect "
          + "for the Hubs that reported from this network, which shares the network's public IP address with Insteon."
      ]
    )

  }

  @Test func doesntSuggestInsteonConnectWhenItWasAsked() async throws {

    let record = Record()

    _ = try await search(DiscoverOptions(asksInsteonConnect: true), record: record)

    #expect(record.notes == ["Asking Insteon Connect..."])

  }

  @Test func reportsWhatTheOtherWayFoundWhenOneFails() async throws {

    let record = Record()
    let hubs = try await search(
      DiscoverOptions(asksInsteonConnect: true),
      insteonConnect: .failure(Unreachable()),
      localNetwork: .success(["192.168.0.20:25105"]),
      record: record
    )

    #expect(hubs == ["192.168.0.20:25105"])
    #expect(record.notes == ["Asking Insteon Connect...", "Insteon Connect: unreachable"])

  }

  @Test func failsOnlyWhenEveryWayOfLookingFailed() async throws {

    let record = Record()

    await #expect(throws: Unreachable.self) {

      try await search(
        DiscoverOptions(asksInsteonConnect: true),
        insteonConnect: .failure(Unreachable()),
        localNetwork: .failure(Unreachable()),
        record: record
      )

    }

    #expect(record.notes == ["Asking Insteon Connect...", "Insteon Connect: unreachable", "Local network: unreachable"])

  }

  @Test func stopsWhenTheLocalSearchIsCanceled() async throws {

    let record = Record()

    await #expect(throws: CancellationError.self) {

      try await search(DiscoverOptions(asksInsteonConnect: true), localNetwork: .failure(CancellationError()), record: record)

    }

    #expect(record.notes == ["Asking Insteon Connect..."])

  }

}
