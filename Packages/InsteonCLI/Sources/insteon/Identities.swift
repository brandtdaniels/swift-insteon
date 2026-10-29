import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import InsteonCLICore
import InsteonLinking
import InsteonModem
import InsteonProtocol

/// Reads and writes the per-user cache of the identities devices reported, described by
/// `IdentityCache`.
///
/// The cache holds only Insteon addresses and identities. It's written readable only by the
/// current user, in a directory only they can open, and a cache that can't be read or written
/// only means devices go unnamed.
enum IdentityStore {

  /// The cache, or an empty one if there's none or it can't be read.
  static func load() -> IdentityCache {

    guard
      let path = path(),
      let type = try? FileManager.default.attributesOfItem(atPath: path)[.type] as? FileAttributeType,
      // Only a regular file is read, so a named pipe can't block the command.
      type == .typeRegular,
      let data = FileManager.default.contents(atPath: path)
    else {

      return IdentityCache()

    }

    return (try? IdentityCache(json: data)) ?? IdentityCache()

  }

  /// Remembers the identity a device reported, if it isn't already remembered.
  static func remember(_ identity: KnownIdentity, for device: InsteonAddress) {

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

  /// Writes the cache to a file of its own, readable only by the current user, then moves it
  /// into place, so a reader never sees half a file.
  private static func save(_ cache: IdentityCache) {

    guard let path = path(), let data = try? cache.json() else {

      return

    }

    let directory = Paths.directory(of: path)
    let temporary = "\(path).\(getpid()).tmp"

    do {

      try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

      guard FileManager.default.createFile(atPath: temporary, contents: data, attributes: [.posixPermissions: 0o600]) else {

        throw CocoaError(.fileWriteUnknown)

      }

      guard rename(temporary, path) == 0 else {

        throw CocoaError(.fileWriteUnknown)

      }

    } catch {

      try? FileManager.default.removeItem(atPath: temporary)
      Output.note("insteon: warning: the identity cache \(path) couldn't be written, so this device's identity won't be remembered.")

    }

  }

}

/// Finds out what devices are, from the identity cache or by asking them.
enum Identities {

  /// A device's identity from the cache, or else, when `asking`, from an ID Request, which is
  /// then remembered.
  ///
  /// - Returns: The device and what the catalog says about it, or `nil` if its identity isn't
  ///   known and it didn't report one.
  static func known(_ device: InsteonAddress, modem: Modem, names: ProductNames, asking: Bool) async -> KnownDevice? {

    if let identity = IdentityStore.load()[device] {

      return names.device(identity)

    }

    guard asking else {

      return nil

    }

    Output.note("Asking \(device) for its identity with ID Request...")

    guard let pressed = try? await DeviceIdentifier(modem: modem).identify(device).identity else {

      return nil

    }

    let identity = KnownIdentity(pressed)

    IdentityStore.remember(identity, for: device)

    return names.device(identity)

  }

  /// The identity a link reported, or else, for a new link, the one the device reports to an
  /// ID Request. Either is remembered.
  static func learn(from link: AllLinkingCompleted, modem: Modem, names: ProductNames) async -> KnownDevice? {

    if let identity = KnownIdentity(link) {

      IdentityStore.remember(identity, for: link.address)

      return names.device(identity)

    }

    guard link.mode != .delete else {

      return IdentityStore.load()[link.address].map(names.device)

    }

    return await known(link.address, modem: modem, names: names, asking: true)

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

  /// The path with every symbolic link in it resolved, or `nil` if it can't be.
  static func resolved(_ path: String) -> String? {

    guard let resolved = realpath(path, nil) else {

      return nil

    }

    defer { free(resolved) }

    return String(cString: resolved)

  }

}
