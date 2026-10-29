import InsteonCLICore
import InsteonHubClient
import InsteonHubDiscovery

/// `insteon discover`: finds Hubs on the local network, and with Insteon Connect when asked.
enum DiscoverCommand {

  /// A Hub as `--json` prints it.
  struct FoundHub: Encodable {

    let host: String

    let port: Int

    let insteonID: String?

    /// How the Hub was found: `local`, `insteonConnect` or both.
    let foundBy: [String]

  }

  static func run(_ options: DiscoverOptions, printsJSON: Bool) async throws {

    var hubs: [FoundHub] = []
    var failures: [any Error] = []

    if options.asksInsteonConnect {

      Output.note("Asking Insteon Connect...")

      do {

        for hub in try await InsteonConnectLookup().hubs() {

          merge(hub, foundBy: "insteonConnect", into: &hubs)

        }

      } catch {

        Output.note("Insteon Connect: \(Names.message(for: error))")
        failures.append(error)

      }

    }

    if options.searchesLocalNetwork {

      Output.note("Searching the local network; this can take a minute...")

      do {

        let found = try await HubDiscovery().discover { hub in

          Output.note("Found a Hub at \(hub.endpoint.host):\(hub.endpoint.port)")

        }

        for hub in found {

          merge(hub, foundBy: "local", into: &hubs)

        }

        // Insteon Connect sees the network's public IP address, so it's only suggested.
        if found.isEmpty, !options.asksInsteonConnect {

          Output.note(
            "No Hub answered on the local network. 'insteon discover --insteon-connect' asks Insteon Connect "
              + "for the Hubs that reported from this network, which shares the network's public IP address with Insteon."
          )

        }

      } catch {

        Output.note("Local network: \(Names.message(for: error))")
        failures.append(error)

      }

    }

    // Fail only when every way of looking failed, rather than reporting no Hubs.
    let ways = (options.asksInsteonConnect ? 1 : 0) + (options.searchesLocalNetwork ? 1 : 0)

    if let failure = failures.last, failures.count == ways {

      throw failure

    }

    if printsJSON {

      try Output.json(hubs)

      return

    }

    guard !hubs.isEmpty else {

      Output.line("No Hubs found.")

      return

    }

    let rows: [[String]] = hubs.map { hub in

      ["\(hub.host):\(hub.port)", hub.insteonID ?? "-", hub.foundBy.joined(separator: ", ")]

    }

    Output.table([["ADDRESS", "INSTEON ID", "FOUND BY"]] + rows)

    if options.searchesLocalNetwork {

      Output.note("A Hub found on the local network is a candidate: check its address before using its password there.")

    }

  }

  /// Adds a Hub, or merges it into the same Hub found another way, keeping its Insteon ID.
  private static func merge(_ hub: DiscoveredHub, foundBy way: String, into hubs: inout [FoundHub]) {

    let id = hub.insteonID.map { "\($0)" }

    guard let index = hubs.firstIndex(where: { $0.host == hub.endpoint.host && $0.port == hub.endpoint.port }) else {

      hubs.append(FoundHub(host: hub.endpoint.host, port: hub.endpoint.port, insteonID: id, foundBy: [way]))

      return

    }

    let existing = hubs[index]

    hubs[index] = FoundHub(
      host: existing.host,
      port: existing.port,
      insteonID: existing.insteonID ?? id,
      foundBy: existing.foundBy + [way]
    )

  }

}
