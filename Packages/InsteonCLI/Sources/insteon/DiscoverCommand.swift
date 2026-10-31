import InsteonCLISupport
import InsteonHubClient
import InsteonHubDiscovery
import InsteonProtocol

/// `insteon discover`: finds Hubs on the local network, and with Insteon Connect when asked.
///
/// The reusable parts, running local and Insteon Connect discovery, stopping at the first Hub,
/// merging duplicates, and the password policy for confirming a Hub, live in
/// `InsteonHubDiscovery`'s `HubFinder` and `HubIdentifier`. This command is the argument
/// parsing, the progress and prompts, and the output around them.
enum DiscoverCommand {

  /// A Hub as `--json` prints it. The identity is left out when it isn't known.
  struct FoundHub: Encodable {

    let host: String

    let port: Int

    var insteonID: String?

    /// How the Hub was found: `local`, `insteonConnect` or both.
    var foundBy: [String]

    var category: String?

    var subcategory: String?

    var firmwareVersion: String?

    var unitType: String?

    var product: String?

  }

  /// How often the local search says it's still going.
  private static let progressInterval: Duration = .seconds(5)

  static func run(_ options: DiscoverOptions, envFilePath: String?, printsJSON: Bool) async throws {

    // Read before searching, so a missing user name or password stops the command at once.
    let credentials: HubIdentifier.Credentials? = try options.identifiesHubs
      ? Self.credentials(envFilePath: envFilePath)
      : nil

    // Without a person to ask before each Hub is sent the password, it's sent only to the one
    // Hub named.
    if options.identifiesHubs, options.identifyTarget == nil, !Terminal.readsFromTerminal {

      throw CommandFailure(
        description: "'--identify' sends the Hub's password, and there's no terminal to ask before sending it to each Hub found. "
          + "Name the one Hub to send it to with '--identify HOST[:PORT]'."
      )

    }

    let names = ProductNames()
    let finder = HubFinder()
    var hubs: [DiscoveredHub] = []
    var failures: [any Error] = []

    if options.asksInsteonConnect {

      Output.note("Asking Insteon Connect...")

      do {

        for var hub in try await finder.lookup.hubs() {

          hub.foundBy = [.insteonConnect]
          HubFinder.merge(hub, into: &hubs)

        }

      } catch {

        Output.note("Insteon Connect: \(Names.message(for: error))")
        failures.append(error)

      }

    }

    if options.searchesLocalNetwork {

      do {

        let found = try await searchLocalNetwork(finder, stoppingAtFirst: !options.searchesAllAddresses)

        for hub in found {

          HubFinder.merge(hub, into: &hubs)

        }

        // Insteon Connect sees the network's public IP address, so it's only suggested.
        if found.isEmpty, !options.asksInsteonConnect {

          Output.note(
            "No Hub answered on the local network. 'insteon discover --insteon-connect' asks Insteon Connect "
              + "for the Hubs that reported from this network, which shares the network's public IP address with Insteon."
          )

        }

      } catch let error as CancellationError {

        throw error

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

    if let credentials {

      try await identifyHubs(&hubs, target: options.identifyTarget, credentials: credentials)

    }

    let found = hubs.map { foundHub($0, names: names) }

    if printsJSON {

      try Output.json(found)

      return

    }

    guard !found.isEmpty else {

      Output.line("No Hubs found.")

      return

    }

    let rows: [[String]] = found.map { hub in

      [
        "\(hub.host):\(hub.port)",
        hub.insteonID ?? "-",
        hub.product ?? hub.unitType ?? "-",
        hub.foundBy.compactMap { DiscoveryMethod(rawValue: $0)?.label }.joined(separator: ", ")
      ]

    }

    Output.table([["ADDRESS", "INSTEON ID", "PRODUCT", "FOUND BY"]] + rows)

    if options.searchesLocalNetwork, credentials == nil {

      Output.note("A Hub found on the local network is a candidate: check its address before using its password there.")

    }

  }

  /// Searches the local network, saying how it's going on standard error, and stops at the
  /// first Hub when asked to.
  private static func searchLocalNetwork(_ finder: HubFinder, stoppingAtFirst: Bool) async throws -> [DiscoveredHub] {

    let addressCount = try? finder.discovery.searchableAddressCount()

    Output.note(
      "Searching \(addressCount.map { Wording.count($0, "address", plural: "addresses") } ?? "the addresses") on the local network"
        + (stoppingAtFirst ? ", stopping at the first Hub..." : "; this can take a minute...")
    )

    let interval = progressInterval
    let progress = Task {

      let clock = ContinuousClock()
      let start = clock.now

      while true {

        try await Task.sleep(for: interval)

        Output.note("Still searching, \(start.duration(to: clock.now).components.seconds) seconds so far...")

      }

    }

    defer { progress.cancel() }

    let search = try await finder.searchLocalNetwork(stoppingAtFirstHub: stoppingAtFirst) { hub in

      Output.note("Found a Hub at \(hub.endpoint.host):\(hub.endpoint.port)")

    }

    if search.stoppedAtFirstHub {

      Output.note("Stopped at the first Hub; 'insteon discover --all' searches every address.")

    }

    return search.hubs

  }

  /// Asks the Hubs found for Get IM Info, with the Hub's user name and password: only the Hub
  /// named, or else each Hub on the Hub's port that the person agrees to send them to.
  ///
  /// Asking stops at the first Hub that rejects the credentials, so they aren't tried on the
  /// rest. The policy for where the credentials go lives in `HubIdentifier`; this asks the
  /// person and prints what came of each candidate.
  private static func identifyHubs(
    _ hubs: inout [DiscoveredHub],
    target: HubAddress?,
    credentials: HubIdentifier.Credentials
  ) async throws {

    let identifier = HubIdentifier()

    if let target {

      let port: Int = target.port ?? HubEndpoint.defaultPort
      let index: Int? = hubs.firstIndex { $0.endpoint.host == target.host && $0.endpoint.port == port }

      guard let index else {

        Output.note("\(target.host):\(port) wasn't among the Hubs found, so it wasn't sent the password.")

        return

      }

      let outcome = try await identifier.identify(hubs[index], credentials: credentials)
      report(outcome, for: hubs[index])

      if case let .identified(info) = outcome {

        apply(info, to: &hubs[index])

      }

      return

    }

    if !hubs.isEmpty {

      Output.note("Identifying a Hub sends it the Hub's user name and password, unencrypted. Answer y only for a Hub you trust.")

    }

    let results = try await identifier.identify(
      hubs,
      provideCredentials: { hub in

        let address = "\(hub.endpoint.host):\(hub.endpoint.port)"

        return try await Terminal.confirm("Send the Hub's credentials to \(address) to identify it? [y/N]") ? credentials : nil

      },
      onResult: { hub, outcome in

        report(outcome, for: hub)

      }
    )

    for (hub, outcome) in results {

      if case let .identified(info) = outcome, let index = hubs.firstIndex(where: { $0.endpoint == hub.endpoint }) {

        apply(info, to: &hubs[index])

      }

    }

    if results.contains(where: { $0.outcome.isAuthenticationFailure }) {

      Output.note("Stopped identifying Hubs, so the rejected credentials aren't sent to any more of them.")

    }

  }

  /// Prints what came of asking a candidate for Get IM Info, without its credentials.
  private static func report(_ outcome: HubIdentifier.Outcome, for hub: DiscoveredHub) {

    let address = "\(hub.endpoint.host):\(hub.endpoint.port)"

    switch outcome {
    case .identified, .declined:
      break
    case .skippedNonPrivateAddress:
      Output.note("\(hub.endpoint.host) isn't a private address, so it wasn't sent the password.")
    case .skippedNonHubPort:
      Output.note(
        "\(address) isn't on the Hub's port, \(HubEndpoint.defaultPort), so it wasn't sent the password. "
          + "'insteon discover --identify \(address)' sends it."
      )
    case .didNotAnswer:
      Output.note("\(address) didn't answer Get IM Info in time.")
    case let .rejected(error), let .failed(error):
      Output.note("\(address): \(Names.message(for: error))")
    }

  }

  /// Keeps the identity a Hub reported for Get IM Info.
  private static func apply(_ info: ModemInfo, to hub: inout DiscoveredHub) {

    hub.insteonID = info.address
    hub.category = info.category
    hub.subcategory = info.subcategory
    hub.modemFirmwareVersion = info.firmwareVersion

  }

  /// A found Hub as `--json` and the table show it, naming its product from the catalog.
  private static func foundHub(_ hub: DiscoveredHub, names: ProductNames) -> FoundHub {

    var product: String?

    if let category = hub.category, let subcategory = hub.subcategory {

      product = names.name(category: category, subcategory: subcategory, firmwareVersion: hub.modemFirmwareVersion)

    }

    return FoundHub(
      host: hub.endpoint.host,
      port: hub.endpoint.port,
      insteonID: hub.insteonID.map { "\($0)" },
      foundBy: foundByRawValues(hub.foundBy),
      category: hub.category.map { "\($0)" },
      subcategory: hub.subcategory.map { "\($0)" },
      firmwareVersion: hub.modemFirmwareVersion.map { "\($0)" },
      unitType: hub.unitType,
      product: product
    )

  }

  /// The ways a Hub was found, as the raw values the `--json` and table output use, with Insteon
  /// Connect before the local network when both found it.
  private static func foundByRawValues(_ sources: Set<DiscoverySource>) -> [String] {

    [DiscoverySource.insteonConnect, .localNetwork]
      .filter(sources.contains)
      .map { method(for: $0).rawValue }

  }

  /// The command's name for a discovery source.
  private static func method(for source: DiscoverySource) -> DiscoveryMethod {

    switch source {
    case .localNetwork: .local
    case .insteonConnect: .insteonConnect
    }

  }

  /// Reads the Hub's user name and password from the environment, for identifying Hubs.
  private static func credentials(envFilePath: String?) throws -> HubIdentifier.Credentials {

    let credentials = try HubCredentials(environment: ModemSession.loadEnvironment(explicitPath: envFilePath))

    return HubIdentifier.Credentials(user: credentials.user, password: credentials.password)

  }

}
