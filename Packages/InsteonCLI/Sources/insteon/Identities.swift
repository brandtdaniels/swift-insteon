import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import InsteonCLICore
import InsteonDeviceCatalog
import InsteonLinking
import InsteonModem
import InsteonProtocol

/// Reads and writes the per-user cache of the identities devices reported, described by
/// `IdentityCache`.
///
/// The cache holds only Insteon addresses and identities. It's written readable only by the
/// current user, in a directory only they can open when the command creates it, and a cache
/// that can't be read or written only means devices go unnamed.
enum IdentityStore {

  /// The cache, or an empty one if there's none or it can't be read.
  static func load() -> IdentityCache {

    guard let path = path(), let data = PrivateFiles.read(path) else {

      return IdentityCache()

    }

    return (try? IdentityCache(json: data)) ?? IdentityCache()

  }

  /// Remembers the identity a device reported, if it isn't already remembered.
  static func remember(_ identity: ReportedIdentity, for device: InsteonAddress) {

    var cache = load()

    guard cache[device] != identity else {

      return

    }

    cache[device] = identity
    save(cache)

  }

  private static func path() -> String? {

    IdentityCache.path(environment: ProcessInfo.processInfo.environment)

  }

  /// Writes the cache readable only by the current user, replacing the file whole, as
  /// `PrivateFiles.replace(_:with:)` does.
  ///
  /// Two commands that save at the same time each write the cache as they read it, so the
  /// entry one of them added can be lost. The device's identity is then learned again the next
  /// time it's asked.
  private static func save(_ cache: IdentityCache) {

    guard let path = path(), let data = try? cache.json() else {

      return

    }

    guard PrivateFiles.replace(path, with: data) else {

      Output.note("insteon: warning: the identity cache \(path) couldn't be written, so this device's identity won't be remembered.")

      return

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

    if let identity = IdentityStore.load()[device] {

      return names.device(identity)

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

    let identity = ReportedIdentity(pressed)

    IdentityStore.remember(identity, for: device)

    return names.device(identity)

  }

  /// The identity a link reported, or else, for a new link, the one the device reports to an
  /// ID Request. Either is remembered.
  ///
  /// - Throws: `CancellationError` if the task was canceled while asking.
  static func learn(from link: AllLinkingCompleted, modem: Modem, names: ProductNames) async throws -> DeviceDescription? {

    if let identity = ReportedIdentity(link) {

      IdentityStore.remember(identity, for: link.address)

      return names.device(identity)

    }

    guard link.mode != .delete else {

      return IdentityStore.load()[link.address].map(names.device)

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
