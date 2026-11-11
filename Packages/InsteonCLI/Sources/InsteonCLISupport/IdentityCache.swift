import Foundation
import InsteonCore

/// Where the `insteon` command keeps the identities devices reported, so later commands can
/// name devices and use what the catalog says about them.
///
/// The file is `$XDG_CACHE_HOME/insteon/identities.json`, or `~/.cache/insteon/identities.json`
/// when `XDG_CACHE_HOME` isn't set. InsteonCore's `JSONFileDeviceRegistryStore` reads and
/// writes it. It holds Insteon addresses and identities, and copies of the modem's and devices'
/// ALL-Link databases, each device's engine, last level and last-seen time, and the Hub's host,
/// port and Insteon ID, never credentials.
public enum IdentityCache {

  /// The file's path inside the cache directory: `insteon/identities.json`.
  public static let relativePath = "insteon/identities.json"

  /// The cache file: `$XDG_CACHE_HOME/insteon/identities.json`, or
  /// `$HOME/.cache/insteon/identities.json`.
  ///
  /// `XDG_CACHE_HOME` is used only when it's an absolute path, as the XDG Base Directory
  /// Specification asks.
  ///
  /// - Parameter environment: The process's environment.
  /// - Returns: The path, or `nil` if neither `XDG_CACHE_HOME` nor `HOME` is set.
  public static func path(environment: [String: String]) -> String? {

    CachePaths.path(relativePath, environment: environment)

  }

}

/// The identity cache's file, as InsteonCore's `JSONFileDeviceRegistryStore` reads and
/// writes it.
public protocol IdentityCacheFile {

  /// Reads everything the file holds.
  ///
  /// - Returns: The snapshot, or an empty one if there's no file yet.
  /// - Throws: `DeviceRegistryStoreError` if the file can't be read.
  func loadNetwork() throws -> NetworkSnapshot

  /// Replaces what the file holds.
  ///
  /// - Parameter snapshot: The snapshot to keep.
  /// - Throws: `DeviceRegistryStoreError` if the file can't be written.
  func saveNetwork(_ snapshot: NetworkSnapshot) throws

}

/// InsteonCore's file store is the identity cache's file.
extension JSONFileDeviceRegistryStore: IdentityCacheFile {}

/// What came of saving to the identity cache.
public enum IdentityCacheSave: Hashable, Sendable {

  /// Nothing needed writing: nothing was learned, or the cache already holds it.
  case unchanged

  /// The changes were written.
  case saved

  /// The changes couldn't be written, so they're still to be saved, with the warning to print,
  /// or `nil` when nothing a person would miss, such as an identity, was lost.
  case notSaved(warning: String?)

}

extension IdentityCache {

  /// Writes to the cache only what changed from `start` to `learned`, such as what a network
  /// learned since it started or since it last saved.
  ///
  /// The cache is read again first, and the changes are merged into it with
  /// `NetworkSnapshot.merging(changesFrom:to:)`: each identity, each field of each device's
  /// state, the modem's ALL-Link database and the Hub are written only when they changed, so
  /// what another command saved in the meantime is kept unless this one changed the same
  /// value. A cache that can't be read isn't replaced, so it isn't lost, and it's warned about
  /// only when a device reported an identity that would have been remembered.
  ///
  /// - Parameters:
  ///   - learned: What the network knows.
  ///   - start: What it knew when it started or last saved.
  ///   - file: The cache's file.
  ///   - path: The file's path, for a warning.
  /// - Returns: What came of it.
  public static func save(_ learned: NetworkSnapshot, since start: NetworkSnapshot, to file: some IdentityCacheFile, path: String) -> IdentityCacheSave {

    guard learned != start else {

      return .unchanged

    }

    let current: NetworkSnapshot

    do {

      current = try file.loadNetwork()

    } catch {

      return .notSaved(warning: learned.registry != start.registry ? warning(for: error, path: path) : nil)

    }

    let merged: NetworkSnapshot = current.merging(changesFrom: start, to: learned)

    guard merged != current else {

      return .unchanged

    }

    do {

      try file.saveNetwork(merged)

      return .saved

    } catch {

      return .notSaved(warning: warning(for: error, path: path))

    }

  }

  /// The warning that the identities devices report won't be remembered, for why the cache
  /// couldn't be read or written.
  ///
  /// - Parameters:
  ///   - error: The error reading or writing the cache.
  ///   - path: The cache's file.
  /// - Returns: The warning.
  public static func warning(for error: any Error, path: String) -> String {

    switch error as? DeviceRegistryStoreError {
    case .malformedContents?, .unsupportedVersion(_)?:
      "insteon: warning: the identity cache \(path) isn't in a format this command reads, so it's left as it is and the identities devices report won't be remembered. Delete it to start a new one."
    case .unreadableFile?:
      "insteon: warning: the identity cache \(path) couldn't be read, so it's left as it is and the identities devices report won't be remembered."
    default:
      "insteon: warning: the identity cache \(path) couldn't be written, so the identities devices report won't be remembered."
    }

  }

}

/// Paths in the per-user cache directory, where the `insteon` command keeps the identity cache
/// and its copy of the Insteon device catalog.
public enum CachePaths {

  /// A file in the cache directory: `$XDG_CACHE_HOME/RELATIVE_PATH`, or
  /// `$HOME/.cache/RELATIVE_PATH`.
  ///
  /// `XDG_CACHE_HOME` is used only when it's an absolute path, as the XDG Base Directory
  /// Specification asks.
  ///
  /// ```swift
  /// CachePaths.path("insteon/catalog.json", environment: ["HOME": "/home/example"])
  /// // "/home/example/.cache/insteon/catalog.json"
  /// ```
  ///
  /// - Parameters:
  ///   - relativePath: The file's path inside the cache directory, such as
  ///     `insteon/identities.json`.
  ///   - environment: The process's environment.
  /// - Returns: The path, or `nil` if neither `XDG_CACHE_HOME` nor `HOME` is set.
  public static func path(_ relativePath: String, environment: [String: String]) -> String? {

    if let cacheHome = environment["XDG_CACHE_HOME"], cacheHome.hasPrefix("/") {

      return joined(cacheHome, relativePath)

    }

    guard let home = environment["HOME"], home.hasPrefix("/") else {

      return nil

    }

    return joined(joined(home, ".cache"), relativePath)

  }

  private static func joined(_ directory: String, _ name: String) -> String {

    directory.hasSuffix("/") ? directory + name : directory + "/" + name

  }

}
