import Foundation

/// Where the `insteon` command keeps the identities devices reported, so later commands can
/// name devices and use what the catalog says about them.
///
/// The file is `$XDG_CACHE_HOME/insteon/identities.json`, or `~/.cache/insteon/identities.json`
/// when `XDG_CACHE_HOME` isn't set. InsteonCore's `JSONFileDeviceRegistryStore` reads and
/// writes it. It holds only Insteon addresses and identities, never credentials.
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
