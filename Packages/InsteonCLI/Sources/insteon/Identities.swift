import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import InsteonCLISupport
import InsteonCore

/// Reads and writes the per-user cache of the identities devices reported, at the path
/// `IdentityCache` gives, through InsteonCore's `DeviceRegistry`, `DeviceNetwork` and
/// `JSONFileDeviceRegistryStore`.
///
/// The cache holds Insteon addresses and identities, and what a `DeviceNetwork` learned: copies
/// of ALL-Link databases, engines, levels, last-seen times and the Hub's host, port and Insteon
/// ID. It never holds credentials. It's written readable only by the
/// current user, in a directory only they can open when the command creates it, and a cache
/// that can't be read or written only means devices go unnamed. A warning that an identity
/// can't be remembered is printed at most once a run.
enum IdentityStore {

  /// Runs `body` with a network that starts from what the cache holds, then saves what the
  /// network learned, even when `body` throws, such as after Control-C. `body` can save
  /// sooner with `CachedNetwork.save()`, such as after each device it identifies.
  ///
  /// - Parameters:
  ///   - modem: The session whose modem the devices are reached through.
  ///   - hub: The Hub's host and port, or `nil` for a serial modem.
  ///   - names: The catalog's product names, which describe the devices.
  ///   - body: The work to do with the network.
  static func withNetwork(
    modem: ModemSession,
    hub: HubLocation?,
    names: ProductNames,
    _ body: (CachedNetwork) async throws -> Void
  ) async throws {

    let start: NetworkSnapshot = loadNetwork()
    let network = CachedNetwork(
      network: modem.network(catalog: names.catalog, snapshot: start, hub: hub),
      start: start
    )

    do {

      try await body(network)

    } catch {

      await network.save()

      throw error

    }

    await network.save()

  }

  private static func path() -> String? {

    IdentityCache.path(environment: ProcessInfo.processInfo.environment)

  }

  /// Everything in the cache, or nothing if there's no cache or it can't be read.
  private static func loadNetwork() -> NetworkSnapshot {

    guard let path = path(), let snapshot = try? JSONFileDeviceRegistryStore(fileURL: URL(fileURLWithPath: path)).loadNetwork() else {

      return NetworkSnapshot()

    }

    return snapshot

  }

  /// Writes to the cache only what changed from `start` to `learned`, as
  /// `IdentityCache.save(_:since:to:path:)` decides, printing its warning at most once a run.
  ///
  /// - Returns: `false` if the changes couldn't be written, so they're still to be saved, and
  ///   `true` otherwise.
  @discardableResult
  static func save(_ learned: NetworkSnapshot, since start: NetworkSnapshot) -> Bool {

    guard let path = path() else {

      return true

    }

    let store = JSONFileDeviceRegistryStore(fileURL: URL(fileURLWithPath: path))

    switch IdentityCache.save(learned, since: start, to: store, path: path) {
    case .unchanged, .saved:
      return true
    case let .notSaved(warning):
      if let warning, self.warning.claim() {

        Output.note(warning)

      }

      return false
    }

  }

  /// Whether the warning has been printed in this run.
  private static let warning: Latch = Latch()

}

/// A network that starts from what the identity cache holds, and saves what it learns back
/// to the cache, writing only what changed since it last saved.
actor CachedNetwork {

  /// The network.
  nonisolated let network: DeviceNetwork

  /// Saves one at a time, from what the network knew when it last saved, or when it
  /// started: what the cache holds of it.
  private let saver: OrderedSaver<NetworkSnapshot>

  /// Creates a network to save.
  ///
  /// - Parameters:
  ///   - network: The network, which started from `start`.
  ///   - start: What the cache held when the network started.
  init(network: DeviceNetwork, start: NetworkSnapshot) {

    self.network = network
    self.saver = OrderedSaver(saved: start)

  }

  /// Writes what the network learned since it last saved to the cache, merged with what the
  /// cache holds when it saves. What couldn't be written is tried again the next time. Saves called at
  /// once run one after another, so neither undoes the other.
  func save() async {

    let network: DeviceNetwork = network

    await saver.save(
      reading: { () async -> NetworkSnapshot in await network.snapshot() },
      writing: { (learned: NetworkSnapshot, since: NetworkSnapshot) -> Bool in IdentityStore.save(learned, since: since) }
    )

  }

}

/// A flag that's set once, safely from any task.
final class Latch: @unchecked Sendable {

  private let lock: NSLock = NSLock()

  private var isSet: Bool = false

  /// Sets the flag.
  ///
  /// - Returns: `true` the first time it's called, and `false` after that.
  func claim() -> Bool {

    lock.lock()
    defer { lock.unlock() }

    guard !isSet else {

      return false

    }

    isSet = true

    return true

  }

}

/// Finds out what devices are, from the identity cache or by asking them.
enum Identities {

  /// A device's description from the network's registry, or else, when `asking`, from an ID
  /// Request through the network, which records the identity it reports.
  ///
  /// A device that doesn't answer is only left unnamed, but cancellation, such as by
  /// Control-C, stops the command.
  ///
  /// - Returns: What the catalog says about the device, or `nil` if its identity isn't known
  ///   and it didn't report one.
  /// - Throws: `CancellationError` if the task was canceled.
  static func known(_ device: InsteonAddress, network: DeviceNetwork, asking: Bool) async throws -> DeviceInfo? {

    if let known = await network.registry.device(device) {

      return known.info

    }

    guard asking else {

      return nil

    }

    Output.note("Asking \(device) for its identity with ID Request...")

    do {

      _ = try await network.identify(device)

    } catch let error as CancellationError {

      throw error

    } catch {

      return nil

    }

    return await network.registry.device(device)?.info

  }

}
