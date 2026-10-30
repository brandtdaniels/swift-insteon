import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import InsteonCLICore
import InsteonCore
import InsteonDeviceCatalog
import InsteonLinking
import InsteonModem
import InsteonProtocol

/// Reads and writes the per-user cache of the identities devices reported, at the path
/// `IdentityCache` gives, through InsteonCore's `DeviceRegistry` and
/// `JSONFileDeviceRegistryStore`.
///
/// The cache holds only Insteon addresses and identities. It's written readable only by the
/// current user, in a directory only they can open when the command creates it, and a cache
/// that can't be read or written only means devices go unnamed.
enum IdentityStore {

  /// The devices in the cache, described with the catalog, or none if there's no cache or it
  /// can't be read.
  static func registry(names: ProductNames) -> DeviceRegistry {

    DeviceRegistry(catalog: names.catalog, snapshot: load())

  }

  /// What the catalog says about a device whose identity is in the cache.
  ///
  /// - Returns: The description, or `nil` if the device's identity isn't in the cache.
  static func known(_ device: InsteonAddress, names: ProductNames) async -> DeviceDescription? {

    await registry(names: names).device(device)?.deviceDescription

  }

  /// Remembers the identity a device reported, if it isn't already remembered.
  ///
  /// The cache is read again first, so an identity another command remembered in the meantime
  /// is kept.
  ///
  /// - Returns: What the catalog says about the device.
  @discardableResult
  static func remember(_ identity: ReportedIdentity, for device: InsteonAddress, names: ProductNames? = nil) async -> DeviceDescription {

    let registry = DeviceRegistry(catalog: names?.catalog, snapshot: load())
    let isRemembered: Bool = await registry.device(device)?.identity == identity
    let registered: RegisteredDevice = await registry.record(identity, for: device)

    if !isRemembered {

      await save(registry)

    }

    return registered.deviceDescription

  }

  private static func path() -> String? {

    IdentityCache.path(environment: ProcessInfo.processInfo.environment)

  }

  /// The identities in the cache, or none if there's no cache or it can't be read.
  private static func load() -> DeviceRegistrySnapshot {

    guard let path = path(), let snapshot = try? JSONFileDeviceRegistryStore(fileURL: URL(fileURLWithPath: path)).load() else {

      return DeviceRegistrySnapshot()

    }

    return snapshot

  }

  /// Writes the cache readable only by the current user, replacing the file whole.
  ///
  /// Two commands that save at the same time each write the cache as they read it, so the
  /// entry one of them added can be lost. The device's identity is then learned again the next
  /// time it's asked. A cache that can't be read isn't replaced, so it isn't lost.
  private static func save(_ registry: DeviceRegistry) async {

    guard let path = path() else {

      return

    }

    let snapshot: DeviceRegistrySnapshot = await registry.snapshot

    do {

      try JSONFileDeviceRegistryStore(fileURL: URL(fileURLWithPath: path)).save(snapshot)

    } catch DeviceRegistryStoreError.malformedContents, DeviceRegistryStoreError.unsupportedVersion(_) {

      Output.note("insteon: warning: the identity cache \(path) isn't in a format this command reads, so it's left as it is and this device's identity won't be remembered. Delete it to start a new one.")

    } catch {

      Output.note("insteon: warning: the identity cache \(path) couldn't be written, so this device's identity won't be remembered.")

    }

  }

}

/// Finds out what devices are, from the identity cache or by asking them.
enum Identities {

  /// A device's identity from the cache, or else, when `asking`, from an ID Request, which is
  /// then remembered.
  ///
  /// A device that doesn't answer is only left unnamed, but cancellation, such as by
  /// Control-C, stops the command.
  ///
  /// - Returns: The device and what the catalog says about it, or `nil` if its identity isn't
  ///   known and it didn't report one.
  /// - Throws: `CancellationError` if the task was canceled.
  static func known(_ device: InsteonAddress, modem: Modem, names: ProductNames, asking: Bool) async throws -> DeviceDescription? {

    if let known = await IdentityStore.known(device, names: names) {

      return known

    }

    guard asking else {

      return nil

    }

    Output.note("Asking \(device) for its identity with ID Request...")

    let reported: SetButtonPressed?

    do {

      reported = try await DeviceIdentifier(modem: modem).identify(device).identity

    } catch let error as CancellationError {

      throw error

    } catch {

      return nil

    }

    guard let pressed = reported else {

      return nil

    }

    return await IdentityStore.remember(ReportedIdentity(pressed), for: device, names: names)

  }

  /// The identity a link reported, or else, for a new link, the one the device reports to an
  /// ID Request. Either is remembered.
  ///
  /// - Throws: `CancellationError` if the task was canceled while asking.
  static func learn(from link: AllLinkingCompleted, modem: Modem, names: ProductNames) async throws -> DeviceDescription? {

    if let identity = ReportedIdentity(link) {

      return await IdentityStore.remember(identity, for: link.address, names: names)

    }

    guard link.mode != .delete else {

      return await IdentityStore.known(link.address, names: names)

    }

    return try await known(link.address, modem: modem, names: names, asking: true)

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
