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

  /// Writes the cache to a new file of its own, readable only by the current user, then moves
  /// it into place, so a reader never sees half a file.
  ///
  /// The new file has a name no other process can guess, and is created only if nothing,
  /// such as a symbolic link, is already there. The cache's directory is created readable only
  /// by the current user, but a directory that's already there is left as it is.
  ///
  /// Two commands that save at the same time each write the cache as they read it, so the
  /// entry one of them added can be lost. The device's identity is then learned again the next
  /// time it's asked.
  private static func save(_ cache: IdentityCache) {

    guard let path = path(), let data = try? cache.json() else {

      return

    }

    let suffix = String(UInt64.random(in: UInt64.min...UInt64.max), radix: 16)
    let temporary = "\(path).\(suffix).tmp"

    guard makeDirectory(Paths.directory(of: path)), createFile(temporary, containing: data) else {

      Output.note("insteon: warning: the identity cache \(path) couldn't be written, so this device's identity won't be remembered.")

      return

    }

    guard rename(temporary, path) == 0 else {

      _ = unlink(temporary)
      Output.note("insteon: warning: the identity cache \(path) couldn't be written, so this device's identity won't be remembered.")

      return

    }

  }

  /// Makes the cache's directory, readable only by the current user, if it isn't there.
  ///
  /// - Returns: Whether the directory is there.
  private static func makeDirectory(_ directory: String) -> Bool {

    let parent = Paths.directory(of: directory)

    if !FileManager.default.fileExists(atPath: parent) {

      guard (try? FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)) != nil else {

        return false

      }

    }

    // A directory that's already there keeps its permissions.
    if mkdir(directory, 0o700) == 0 {

      return true

    }

    return errno == EEXIST

  }

  /// Writes data to a file that doesn't exist yet, readable only by the current user, and
  /// flushes it to storage. A file that can't be written in full is removed.
  ///
  /// - Returns: Whether the file was written.
  private static func createFile(_ path: String, containing data: Data) -> Bool {

    let flags: Int32 = O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW
    let descriptor: Int32 = open(path, flags, 0o600)

    guard descriptor >= 0 else {

      return false

    }

    let written: Bool = data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Bool in

      writeAll(buffer, to: descriptor)

    }

    let synced: Bool = written && fsync(descriptor) == 0
    let closed: Bool = close(descriptor) == 0

    guard synced, closed else {

      _ = unlink(path)

      return false

    }

    return true

  }

  /// Writes every byte of a buffer to a file descriptor, trying again after an interruption.
  private static func writeAll(_ buffer: UnsafeRawBufferPointer, to descriptor: Int32) -> Bool {

    guard let base = buffer.baseAddress else {

      return true

    }

    var offset = 0

    while offset < buffer.count {

      let count: Int = write(descriptor, base + offset, buffer.count - offset)

      if count < 0 {

        guard errno == EINTR else {

          return false

        }

        continue

      }

      offset += count

    }

    return true

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

    let identity = KnownIdentity(pressed)

    IdentityStore.remember(identity, for: device)

    return names.device(identity)

  }

  /// The identity a link reported, or else, for a new link, the one the device reports to an
  /// ID Request. Either is remembered.
  ///
  /// - Throws: `CancellationError` if the task was canceled while asking.
  static func learn(from link: AllLinkingCompleted, modem: Modem, names: ProductNames) async throws -> DeviceDescription? {

    if let identity = KnownIdentity(link) {

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
