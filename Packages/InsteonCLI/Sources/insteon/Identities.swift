import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import InsteonCLISupport
import InsteonCore
import InsteonDeviceCatalog
import InsteonLinking
import InsteonModem
import InsteonProtocol

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
  ///   - modem: The modem the devices are reached through.
  ///   - hub: The Hub's host and port, or `nil` for a serial modem.
  ///   - names: The catalog's product names, which describe the devices.
  ///   - body: The work to do with the network.
  static func withNetwork(
    modem: Modem,
    hub: HubLocation?,
    names: ProductNames,
    _ body: (CachedNetwork) async throws -> Void
  ) async throws {

    let start: NetworkSnapshot = loadNetwork()
    let network = CachedNetwork(
      network: DeviceNetwork(modem: modem, catalog: names.catalog, snapshot: start, hub: hub),
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

  /// Writes to the cache only what changed from `start` to `learned`, such as what a network
  /// learned since it started or since it last saved.
  ///
  /// The cache is read again first, and the changes are merged into it with
  /// `NetworkSnapshot.merging(changesFrom:to:)`: each identity, each field of each device's
  /// state, the modem's ALL-Link database and the Hub are written only when they changed, so
  /// what another command saved in the meantime is kept unless this one changed the same
  /// value. A cache that can't be read isn't replaced, so it isn't lost, and the warning about
  /// it is printed only when a device reported an identity that would have been remembered.
  ///
  /// - Returns: `false` if the changes couldn't be written, so they're still to be saved, and
  ///   `true` otherwise.
  @discardableResult
  static func save(_ learned: NetworkSnapshot, since start: NetworkSnapshot) -> Bool {

    guard learned != start, let path = path() else {

      return true

    }

    let store = JSONFileDeviceRegistryStore(fileURL: URL(fileURLWithPath: path))
    let current: NetworkSnapshot

    do {

      current = try store.loadNetwork()

    } catch {

      if learned.registry != start.registry {

        warn(about: error, path: path)

      }

      return false

    }

    let merged: NetworkSnapshot = current.merging(changesFrom: start, to: learned)

    guard merged != current else {

      return true

    }

    do {

      try store.saveNetwork(merged)

      return true

    } catch {

      warn(about: error, path: path)

      return false

    }

  }

  /// Prints a warning that identities won't be remembered, the first time it's called in a run.
  private static func warn(about error: any Error, path: String) {

    guard warning.claim() else {

      return

    }

    switch error as? DeviceRegistryStoreError {
    case .malformedContents?, .unsupportedVersion(_)?:
      Output.note("insteon: warning: the identity cache \(path) isn't in a format this command reads, so it's left as it is and the identities devices report won't be remembered. Delete it to start a new one.")
    case .unreadableFile?:
      Output.note("insteon: warning: the identity cache \(path) couldn't be read, so it's left as it is and the identities devices report won't be remembered.")
    default:
      Output.note("insteon: warning: the identity cache \(path) couldn't be written, so the identities devices report won't be remembered.")
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

  /// What the network knew when it last saved, or when it started: what the cache holds of
  /// it.
  private var saved: NetworkSnapshot

  /// Creates a network to save.
  ///
  /// - Parameters:
  ///   - network: The network, which started from `start`.
  ///   - start: What the cache held when the network started.
  init(network: DeviceNetwork, start: NetworkSnapshot) {

    self.network = network
    self.saved = start

  }

  /// Writes what the network learned since it last saved to the cache, merged with what the
  /// cache holds now. What couldn't be written is tried again the next time.
  func save() async {

    let learned: NetworkSnapshot = await network.snapshot()

    if IdentityStore.save(learned, since: saved) {

      saved = learned

    }

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
  static func known(_ device: InsteonAddress, network: DeviceNetwork, asking: Bool) async throws -> DeviceDescription? {

    if let known = await network.registry.device(device) {

      return known.deviceDescription

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

    return await network.registry.device(device)?.deviceDescription

  }

}

/// Works with file paths as strings.
enum Paths {

  /// The directory a path is in, such as `/home/example/.cache/insteon` for
  /// `/home/example/.cache/insteon/identities.json`.
  static func directory(of path: String) -> String {

    guard let slash = path.lastIndex(of: "/") else {

      return "."

    }

    return slash == path.startIndex ? "/" : String(path[..<slash])

  }

}
