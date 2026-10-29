import InsteonCLICore
import InsteonHubClient
import InsteonHubDiscovery
import InsteonModem
import InsteonProtocol

/// `insteon discover`: finds Hubs on the local network, and with Insteon Connect when asked.
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

  /// How long a Hub has to answer Get IM Info with `--identify`.
  private static let identifyTimeout: Duration = .seconds(15)

  static func run(_ options: DiscoverOptions, envFilePath: String?, printsJSON: Bool) async throws {

    // Read before searching, so a missing user name or password stops the command at once.
    let credentials = try options.identifiesHubs
      ? HubCredentials(environment: ModemSession.loadEnvironment(explicitPath: envFilePath))
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
    var hubs: [FoundHub] = []
    var failures: [any Error] = []

    if options.asksInsteonConnect {

      Output.note("Asking Insteon Connect...")

      do {

        for hub in try await InsteonConnectLookup().hubs() {

          merge(hub, foundBy: .insteonConnect, names: names, into: &hubs)

        }

      } catch {

        Output.note("Insteon Connect: \(Names.message(for: error))")
        failures.append(error)

      }

    }

    if options.searchesLocalNetwork {

      do {

        let found = try await searchLocalNetwork(stoppingAtFirst: !options.searchesAllAddresses)

        for hub in found {

          merge(hub, foundBy: .local, names: names, into: &hubs)

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

      try await identifyHubs(&hubs, target: options.identifyTarget, credentials: credentials, names: names)

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
  private static func searchLocalNetwork(stoppingAtFirst: Bool) async throws -> [DiscoveredHub] {

    let addressCount = (try? InterfaceNetwork().subnets())
      .map { subnets in

        Set(subnets.filter { $0.isPrivate && $0.prefixLength >= HubDiscovery.shortestPrefixLength }.flatMap(\.hosts)).count

      }

    Output.note(
      "Searching \(addressCount.map { Wording.count($0, "address", plural: "addresses") } ?? "the addresses") on the local network"
        + (stoppingAtFirst ? ", stopping at the first Hub..." : "; this can take a minute...")
    )

    let (found, continuation) = AsyncStream<DiscoveredHub>.makeStream()

    let search = Task {

      defer { continuation.finish() }

      return try await HubDiscovery().discover { hub in

        continuation.yield(hub)

      }

    }

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

    return try await withTaskCancellationHandler {

      var hubs: [DiscoveredHub] = []

      for await hub in found {

        Output.note("Found a Hub at \(hub.endpoint.host):\(hub.endpoint.port)")
        hubs.append(hub)

        if stoppingAtFirst {

          search.cancel()
          Output.note("Stopped at the first Hub; 'insteon discover --all' searches every address.")

          return hubs

        }

      }

      // Every address was asked; the search's own list is in address order.
      return try await search.value

    } onCancel: {

      search.cancel()

    }

  }

  /// Asks the Hubs found for Get IM Info, with the Hub's user name and password: only the Hub
  /// named, or else each Hub on the Hub's port that the person agrees to send them to.
  ///
  /// Asking stops at the first Hub that rejects the credentials, so they aren't tried on the
  /// rest.
  private static func identifyHubs(
    _ hubs: inout [FoundHub],
    target: HubAddress?,
    credentials: HubCredentials,
    names: ProductNames
  ) async throws {

    if let target {

      let port: Int = target.port ?? HubEndpoint.defaultPort
      let index: Int? = hubs.firstIndex { $0.host == target.host && $0.port == port }

      guard let index else {

        Output.note("\(target.host):\(port) wasn't among the Hubs found, so it wasn't sent the password.")

        return

      }

      _ = try await identify(&hubs[index], credentials: credentials, names: names)

      return

    }

    if !hubs.isEmpty {

      Output.note("Identifying a Hub sends it the Hub's user name and password, unencrypted. Answer y only for a Hub you trust.")

    }

    for index in hubs.indices {

      let address = "\(hubs[index].host):\(hubs[index].port)"

      // Hubs answer on their own port. Another port is sent the password only when named.
      guard hubs[index].port == HubEndpoint.defaultPort else {

        Output.note(
          "\(address) isn't on the Hub's port, \(HubEndpoint.defaultPort), so it wasn't sent the password. "
            + "'insteon discover --identify \(address)' sends it."
        )

        continue

      }

      guard isPrivate(hubs[index].host) else {

        Output.note("\(hubs[index].host) isn't a private address, so it wasn't sent the password.")

        continue

      }

      let question = "Send the Hub's credentials to \(address) to identify it? [y/N]"

      guard try await Terminal.confirm(question) else {

        continue

      }

      let rejected: Bool = try await identify(&hubs[index], credentials: credentials, names: names)

      if rejected {

        Output.note("Stopped identifying Hubs, so the rejected credentials aren't sent to any more of them.")

        return

      }

    }

  }

  /// Asks a Hub at a private address for Get IM Info, and keeps its Insteon ID and identity.
  ///
  /// - Returns: Whether the Hub rejected the credentials.
  /// - Throws: `CancellationError` if the task was canceled.
  private static func identify(_ hub: inout FoundHub, credentials: HubCredentials, names: ProductNames) async throws -> Bool {

    // The password goes only to a private address, where a Hub on the local network is.
    guard isPrivate(hub.host) else {

      Output.note("\(hub.host) isn't a private address, so it wasn't sent the password.")

      return false

    }

    let endpoint = HubEndpoint(host: hub.host, port: hub.port)
    let connection = HubConnection(hub: Hub(endpoint: endpoint, user: credentials.user, password: credentials.password))
    let info: ModemInfo?

    do {

      info = try await modemInfo(over: connection, timeout: identifyTimeout)

    } catch let error as CancellationError {

      throw error

    } catch {

      Output.note("\(hub.host):\(hub.port): \(Names.message(for: error))")

      return isRejection(error)

    }

    guard let info else {

      Output.note("\(hub.host):\(hub.port) didn't answer Get IM Info in time.")

      return false

    }

    hub.insteonID = "\(info.address)"
    hub.category = "\(info.category)"
    hub.subcategory = "\(info.subcategory)"
    hub.firmwareVersion = "\(info.firmwareVersion)"
    hub.product = names.name(category: info.category, subcategory: info.subcategory, firmwareVersion: info.firmwareVersion)

    return false

  }

  /// Asks a Hub for Get IM Info, giving up after a timeout.
  ///
  /// The request runs in a task of its own that isn't waited for once the time is up, so a
  /// request that doesn't stop when canceled can't hold up the command.
  ///
  /// - Returns: The modem's information, or `nil` if the Hub didn't answer in time.
  private static func modemInfo(over connection: HubConnection, timeout: Duration) async throws -> ModemInfo? {

    let result = OneShot<ModemInfo?>()

    let request = Task {

      do {

        let info: ModemInfo = try await Modem.withConnection(connection) { modem in

          try await modem.modemInfo()

        }

        result.finish(.success(info))

      } catch {

        result.finish(.failure(error))

      }

    }

    let timer = Task {

      try? await Task.sleep(for: timeout)
      result.finish(.success(nil))

    }

    defer {

      request.cancel()
      timer.cancel()

    }

    return try await withTaskCancellationHandler {

      try await result.value()

    } onCancel: {

      result.finish(.failure(CancellationError()))

    }

  }

  /// Whether a host is a private IPv4 address, where a Hub on the local network is.
  private static func isPrivate(_ host: String) -> Bool {

    IPv4Subnet(address: host, prefixLength: 32)?.isPrivate == true

  }

  /// Whether an error is the Hub rejecting the user name and password.
  private static func isRejection(_ error: any Error) -> Bool {

    switch error {
    case HubError.unexpectedStatus(401), HubError.unexpectedStatus(403):
      true
    default:
      false
    }

  }

  /// Adds a Hub, or merges it into the same Hub found another way, keeping what either way
  /// knows about it.
  private static func merge(_ hub: DiscoveredHub, foundBy way: DiscoveryMethod, names: ProductNames, into hubs: inout [FoundHub]) {

    var product: String?

    if let category = hub.category, let subcategory = hub.subcategory {

      product = names.name(category: category, subcategory: subcategory, firmwareVersion: hub.modemFirmwareVersion)

    }

    let found = FoundHub(
      host: hub.endpoint.host,
      port: hub.endpoint.port,
      insteonID: hub.insteonID.map { "\($0)" },
      foundBy: [way.rawValue],
      category: hub.category.map { "\($0)" },
      subcategory: hub.subcategory.map { "\($0)" },
      firmwareVersion: hub.modemFirmwareVersion.map { "\($0)" },
      unitType: hub.unitType,
      product: product
    )

    guard let index = hubs.firstIndex(where: { $0.host == found.host && $0.port == found.port }) else {

      hubs.append(found)

      return

    }

    var existing = hubs[index]

    existing.insteonID = existing.insteonID ?? found.insteonID
    existing.foundBy += found.foundBy
    existing.category = existing.category ?? found.category
    existing.subcategory = existing.subcategory ?? found.subcategory
    existing.firmwareVersion = existing.firmwareVersion ?? found.firmwareVersion
    existing.unitType = existing.unitType ?? found.unitType
    existing.product = existing.product ?? found.product

    hubs[index] = existing

  }

}
