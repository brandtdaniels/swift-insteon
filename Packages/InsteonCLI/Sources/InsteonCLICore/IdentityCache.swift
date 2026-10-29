import Foundation
import InsteonProtocol

/// What a device said it is: the category, subcategory and firmware version of its SET Button
/// Pressed broadcast, or of the ALL-Linking Completed report when the modem became its
/// controller.
///
/// The `insteon` command names a device only from an identity like this, never from the data
/// bytes of the modem's ALL-Link records, which don't reliably hold it.
public struct KnownIdentity: Hashable, Sendable {

  /// The device's category.
  public var category: DeviceCategory

  /// The device's subcategory.
  public var subcategory: DeviceSubcategory

  /// The device's firmware version, or `nil` if it didn't report one.
  public var firmwareVersion: FirmwareVersion?

  /// Creates an identity.
  ///
  /// - Parameters:
  ///   - category: The device's category.
  ///   - subcategory: The device's subcategory.
  ///   - firmwareVersion: The device's firmware version, if it reported one.
  public init(category: DeviceCategory, subcategory: DeviceSubcategory, firmwareVersion: FirmwareVersion?) {

    self.category = category
    self.subcategory = subcategory
    self.firmwareVersion = firmwareVersion

  }

  /// The identity in a SET Button Pressed broadcast, such as a device's answer to ID Request.
  ///
  /// - Parameter pressed: The broadcast.
  public init(_ pressed: SetButtonPressed) {

    self.init(category: pressed.category, subcategory: pressed.subcategory, firmwareVersion: pressed.firmwareVersion)

  }

  /// The identity the modem reported for a new link, which it does only when it became the
  /// controller.
  ///
  /// - Parameter link: The modem's report.
  /// - Returns: `nil` if the report has no category or subcategory.
  public init?(_ link: AllLinkingCompleted) {

    guard let category = link.category, let subcategory = link.subcategory else {

      return nil

    }

    self.init(category: category, subcategory: subcategory, firmwareVersion: link.firmwareVersion)

  }

}

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
  public var identities: [InsteonAddress: KnownIdentity]

  /// Creates a cache.
  ///
  /// - Parameter identities: The identities, by device. Defaults to none.
  public init(identities: [InsteonAddress: KnownIdentity] = [:]) {

    self.identities = identities

  }

  /// The identity learned for a device, if any.
  ///
  /// - Parameter device: The device's address.
  public subscript(device: InsteonAddress) -> KnownIdentity? {

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

    if let cacheHome = environment["XDG_CACHE_HOME"], cacheHome.hasPrefix("/") {

      return joined(cacheHome, relativePath)

    }

    guard let home = environment["HOME"], home.hasPrefix("/") else {

      return nil

    }

    return joined(joined(home, ".cache"), relativePath)

  }

  /// Reads a cache from its file's JSON. An entry that doesn't read as an address and an
  /// identity is left out.
  ///
  /// - Parameter json: The file's contents.
  /// - Throws: `DecodingError` if the contents aren't a cache file at all.
  public init(json: Data) throws {

    let file = try JSONDecoder().decode(File.self, from: json)
    var identities: [InsteonAddress: KnownIdentity] = [:]

    for (text, entry) in file.devices {

      guard
        let address = InsteonAddress(text),
        let category = Self.byte(entry.category),
        let subcategory = Self.byte(entry.subcategory)
      else {

        continue

      }

      identities[address] = KnownIdentity(
        category: DeviceCategory(rawValue: category),
        subcategory: DeviceSubcategory(rawValue: subcategory),
        firmwareVersion: entry.firmwareVersion.flatMap(Self.byte).map(FirmwareVersion.init(rawValue:))
      )

    }

    self.init(identities: identities)

  }

  /// The cache as its file's JSON, with the devices in address order.
  ///
  /// - Returns: The JSON.
  /// - Throws: `EncodingError` if the cache can't be encoded.
  public func json() throws -> Data {

    var devices: [String: File.Entry] = [:]

    for (address, identity) in identities {

      devices["\(address)"] = File.Entry(
        category: Hex.byte(identity.category.rawValue),
        subcategory: Hex.byte(identity.subcategory.rawValue),
        firmwareVersion: identity.firmwareVersion.map { Hex.byte($0.rawValue) }
      )

    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    return try encoder.encode(File(devices: devices))

  }

  /// The file's format.
  private struct File: Codable {

    struct Entry: Codable {

      var category: String

      var subcategory: String

      var firmwareVersion: String?

    }

    var devices: [String: Entry]

  }

  /// A byte written as `0x` and two hexadecimal digits.
  private static func byte(_ text: String) -> UInt8? {

    guard text.count == 4, text.hasPrefix("0x"), text.dropFirst(2).allSatisfy(\.isHexDigit) else {

      return nil

    }

    return UInt8(text.dropFirst(2), radix: 16)

  }

  private static func joined(_ directory: String, _ name: String) -> String {

    directory.hasSuffix("/") ? directory + name : directory + "/" + name

  }

}
