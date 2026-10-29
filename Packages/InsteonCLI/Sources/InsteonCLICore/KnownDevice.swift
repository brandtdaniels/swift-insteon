import InsteonDeviceCatalog
import InsteonProtocol

/// A device whose identity is known, with what the Insteon device catalog says about it.
///
/// ```swift
/// let plug = KnownDevice(identity: KnownIdentity(category: 0x02, subcategory: 0x2A, firmwareVersion: 0x41), catalog: catalog)
/// plug.productName              // the catalog's name and model, if it has the identity
/// plug.mainGroupType?.kind      // GroupType.Kind.relay for a device switched on and off
/// ```
public struct KnownDevice: Hashable, Sendable {

  /// What the device said it is.
  public var identity: KnownIdentity

  /// The catalog's profile for the identity, or `nil` if the catalog doesn't have it or wasn't
  /// loaded.
  public var profile: DeviceProfile?

  /// The command set the profile names for the identity, if any.
  public var commandSet: CommandSet?

  /// Looks an identity up in a catalog.
  ///
  /// - Parameters:
  ///   - identity: What the device said it is.
  ///   - catalog: The catalog, or `nil` if it couldn't be loaded.
  public init(identity: KnownIdentity, catalog: DeviceCatalog?) {

    self.identity = identity
    profile = catalog?.profile(category: identity.category, subcategory: identity.subcategory, firmwareVersion: identity.firmwareVersion)
    commandSet = catalog?.commandSet(category: identity.category, subcategory: identity.subcategory, firmwareVersion: identity.firmwareVersion)

  }

  /// The product's name, model and first alias, as ``ProductName/of(_:)`` writes them, or
  /// `nil` without a profile.
  public var productName: String? {

    profile.map(ProductName.of)

  }

  /// The type of one of the device's groups, or `nil` if the catalog doesn't say.
  ///
  /// - Parameter number: The device's group number, such as 1 for its load.
  public func groupType(forGroup number: AllLinkGroupNumber) -> GroupType? {

    guard
      let commandSet,
      let name = profile?.groups.first(where: { $0.number == number })?.type
    else {

      return nil

    }

    return commandSet.groupType(named: name)

  }

  /// The type of the device's main group: group 1's, or else that of the first group that has
  /// one. A relay's kind is `GroupType.Kind.relay`, which turns only on and off.
  public var mainGroupType: GroupType? {

    if let type = groupType(forGroup: 1) {

      return type

    }

    guard let profile, let commandSet else {

      return nil

    }

    return profile.groups.lazy.compactMap { $0.type.flatMap(commandSet.groupType(named:)) }.first

  }

  /// The group type that explains a responder record in the device's own ALL-Link database.
  ///
  /// A device with several groups keeps its own group in one of the data bytes, which the
  /// main group's type marks with `LinkDataByte.isPerGroup`; otherwise the main group's type
  /// explains the record.
  ///
  /// - Parameter data: The record's Data 1 through Data 3.
  public func responderGroupType(forRecordData data: [UInt8]) -> GroupType? {

    guard let main = mainGroupType else {

      return nil

    }

    guard
      let perGroup = main.linkData.responder.first(where: \.isPerGroup),
      perGroup.position <= data.count,
      let type = groupType(forGroup: AllLinkGroupNumber(rawValue: data[perGroup.position - 1]))
    else {

      return main

    }

    return type

  }

  /// Whether the catalog says the device can be a controller, so the modem can respond to it.
  /// `false` when there's no profile.
  public var canControl: Bool {

    guard let profile else {

      return false

    }

    let controls: (DeviceProfile.LinkRole?) -> Bool = { $0 == .controller || $0 == .both }

    return controls(profile.role) || profile.groups.contains { controls($0.role) }

  }

}

/// Names products as the docs do.
public enum ProductName {

  /// A profile's name and model, then its first alias in parentheses, such as
  /// "Dimmer Switch 2477D (SwitchLinc Dimmer)".
  ///
  /// - Parameter profile: The profile.
  /// - Returns: The name.
  public static func of(_ profile: DeviceProfile) -> String {

    let name = "\(profile.name) \(profile.model)"

    guard let alias = profile.aliases.first else {

      return name

    }

    return "\(name) (\(alias))"

  }

}
