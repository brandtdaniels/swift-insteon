import Foundation
import InsteonProtocol

/// The identities the `insteon` command has learned, by device, kept in a per-user cache file
/// so later commands can name devices and use what the catalog says about them.
///
/// The file is `$XDG_CACHE_HOME/insteon/identities.json`, or `~/.cache/insteon/identities.json`
/// when `XDG_CACHE_HOME` isn't set. It holds only Insteon addresses and identities, never
/// credentials:
///
/// ```json
/// {
///   "devices" : {
///     "1A.2B.3C" : { "category" : "0x02", "firmwareVersion" : "0x41", "subcategory" : "0x2A" }
///   }
/// }
/// ```
public struct IdentityCache: Hashable, Sendable {

  /// The file's path inside the cache directory: `insteon/identities.json`.
  public static let relativePath = "insteon/identities.json"

  /// The identities, by device.
  public var identities: [InsteonAddress: ReportedIdentity]

  /// Creates a cache.
  ///
  /// - Parameter identities: The identities, by device. Defaults to none.
  public init(identities: [InsteonAddress: ReportedIdentity] = [:]) {

    self.identities = identities

  }

  /// The identity learned for a device, if any.
  ///
  /// - Parameter device: The device's address.
  public subscript(device: InsteonAddress) -> ReportedIdentity? {

    get { identities[device] }
    set { identities[device] = newValue }

  }

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

  /// Reads a cache from its file's JSON. An entry that doesn't read as an address and an
  /// identity is left out.
  ///
  /// - Parameter json: The file's contents.
  /// - Throws: `DecodingError` if the contents aren't a cache file at all.
  public init(json: Data) throws {

    let file = try JSONDecoder().decode(StoredFile.self, from: json)
    var identities: [InsteonAddress: ReportedIdentity] = [:]

    for (text, entry) in file.devices {

      guard let address = InsteonAddress(text), let identity = entry.identity else {

        continue

      }

      identities[address] = identity

    }

    self.init(identities: identities)

  }

  /// The cache as its file's JSON, with the devices in address order.
  ///
  /// - Returns: The JSON.
  /// - Throws: `EncodingError` if the cache can't be encoded.
  public func json() throws -> Data {

    var devices: [String: ReportedIdentity] = [:]

    for (address, identity) in identities {

      devices["\(address)"] = identity

    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    return try encoder.encode(File(devices: devices))

  }

  /// The file's format, as it's written.
  private struct File: Encodable {

    var devices: [String: ReportedIdentity]

  }

  /// The file's format, as it's read: an entry that isn't an identity reads as `nil`.
  private struct StoredFile: Decodable {

    struct Entry: Decodable {

      var identity: ReportedIdentity?

      init(from decoder: any Decoder) throws {

        identity = try? ReportedIdentity(from: decoder)

      }

    }

    var devices: [String: Entry]

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
