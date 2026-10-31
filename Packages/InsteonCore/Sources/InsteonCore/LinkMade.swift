import InsteonProtocol

/// A link the modem reported making or removing, with the identity the device sent with it.
///
/// ```swift
/// for link in result.links {
///   print(link.address, link.group, link.mode?.name ?? "unknown")
/// }
/// ```
public struct LinkMade: Hashable, Sendable {

  /// The device the link is with.
  public var address: InsteonAddress

  /// The modem's group in the link.
  public var group: AllLinkGroupNumber

  /// The modem's role in the link, or `delete` for a link removed, or `nil` for
  /// a role the modem reported that isn't one of these.
  public var mode: AllLinkMode?

  /// The category the device sent with the link, or `nil` for a removed link, which carries
  /// none.
  public var category: DeviceCategory?

  /// The subcategory the device sent with the link, or `nil` for a removed link.
  public var subcategory: DeviceSubcategory?

  /// The firmware version the device sent with the link, or `nil` for a removed link.
  public var firmwareVersion: FirmwareVersion?

  /// Creates a link.
  ///
  /// - Parameters:
  ///   - address: The device the link is with.
  ///   - group: The modem's group in the link.
  ///   - mode: The modem's role in the link, or `delete` for a link removed.
  ///   - category: The category the device sent. Defaults to `nil`.
  ///   - subcategory: The subcategory the device sent. Defaults to `nil`.
  ///   - firmwareVersion: The firmware version the device sent. Defaults to `nil`.
  public init(
    address: InsteonAddress,
    group: AllLinkGroupNumber,
    mode: AllLinkMode?,
    category: DeviceCategory? = nil,
    subcategory: DeviceSubcategory? = nil,
    firmwareVersion: FirmwareVersion? = nil
  ) {

    self.address = address
    self.group = group
    self.mode = mode
    self.category = category
    self.subcategory = subcategory
    self.firmwareVersion = firmwareVersion

  }

  /// The link the modem's ALL-Linking Completed reply reports.
  init(_ completed: AllLinkingCompleted) {

    self.init(
      address: completed.address,
      group: completed.group,
      mode: completed.mode,
      category: completed.category,
      subcategory: completed.subcategory,
      firmwareVersion: completed.firmwareVersion
    )

  }

  /// The modem's reply that reports the link. A role that isn't one of the modem's known link
  /// codes is given a code that isn't either.
  var allLinkingCompleted: AllLinkingCompleted {

    AllLinkingCompleted(
      linkCode: mode?.rawValue ?? 0x02,
      group: group,
      address: address,
      category: category,
      subcategory: subcategory,
      firmwareVersion: firmwareVersion
    )

  }

}
