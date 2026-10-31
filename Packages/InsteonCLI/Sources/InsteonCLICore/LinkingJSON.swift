import InsteonCore
import InsteonDeviceCatalog
import InsteonLinking
import InsteonProtocol

/// What `insteon link` and `insteon unlink` print with `--json`, built from what a
/// `DeviceLinkingCoordinator` returns.
///
/// The category, subcategory, firmware version and product come from the device's identity
/// when it's known, and are left out otherwise.
public enum LinkingJSON {

  /// A link the modem reported, with the device's identity when it's known.
  public struct Link: Encodable, Hashable, Sendable {

    /// The device's address, such as `"1A.2B.3C"`.
    public let address: String

    /// The modem's group.
    public let group: Int

    /// The modem's role, as `AllLinkMode`'s `name` gives it, such as `"controller"`.
    public let modemRole: String

    /// The device's category, such as `"0x01"`.
    public let category: String?

    /// The device's subcategory, such as `"0x20"`.
    public let subcategory: String?

    /// The device's firmware version, such as `"0x41"`.
    public let firmwareVersion: String?

    /// The product's name and model, from the Insteon device catalog.
    public let product: String?

  }

  /// What `insteon link --json` prints: the link alone, or every link when the device was
  /// linked back.
  public enum LinkReport: Encodable, Hashable, Sendable {

    /// The one link made.
    case link(Link)

    /// The link asked for, then the link back.
    case links([Link])

    /// Encodes the link as an object, or the links as an array.
    ///
    /// - Parameter encoder: The encoder.
    /// - Throws: The encoder's errors.
    public func encode(to encoder: any Encoder) throws {

      var container: any SingleValueEncodingContainer = encoder.singleValueContainer()

      switch self {
      case let .link(link):
        try container.encode(link)
      case let .links(links):
        try container.encode(links)
      }

    }

  }

  /// A link `insteon unlink` removed with the device's SET button.
  public struct Unlink: Encodable, Hashable, Sendable {

    /// The device's address.
    public let address: String

    /// The modem's group.
    public let group: Int

    /// The product's name and model, when the device was known.
    public let product: String?

  }

  /// A link `insteon unlink ADDRESS --all` removed.
  public struct RemovedLink: Encodable, Hashable, Sendable {

    /// The device's address.
    public let address: String

    /// The modem's group.
    public let group: Int

    /// The modem's role in the link, `"controller"` or `"responder"`.
    public let modemRole: String

    /// The product's name and model, when the device was known.
    public let product: String?

  }

  /// A link the modem reported.
  ///
  /// - Parameters:
  ///   - link: The link.
  ///   - known: What the catalog says about the device, or `nil` if its identity isn't known.
  /// - Returns: The link as JSON prints it.
  public static func link(_ link: AllLinkingCompleted, known: DeviceDescription?) -> Link {

    Link(
      address: "\(link.address)",
      group: Int(link.group.rawValue),
      modemRole: link.mode?.name ?? "unknown",
      category: known.map { (description: DeviceDescription) -> String in "\(description.category)" },
      subcategory: known.map { (description: DeviceDescription) -> String in "\(description.subcategory)" },
      firmwareVersion: known?.firmwareVersion.map { (version: FirmwareVersion) -> String in "\(version)" },
      product: known?.displayName
    )

  }

  /// What `insteon link --json` prints for a link: an object for one link, or an array when
  /// the device was linked back.
  ///
  /// - Parameter result: What the coordinator linked.
  /// - Returns: The report.
  public static func report(_ result: DeviceLinkingResult) -> LinkReport {

    let known: DeviceDescription? = result.device?.deviceDescription
    let links: [Link] = result.links.map { (made: AllLinkingCompleted) -> Link in link(made, known: known) }

    if links.count == 1 {

      return .link(links[0])

    }

    return .links(links)

  }

  /// A link removed with the device's SET button.
  ///
  /// - Parameter unlinked: The removed link.
  /// - Returns: The link as JSON prints it.
  public static func unlink(_ unlinked: UnlinkedLink) -> Unlink {

    Unlink(
      address: "\(unlinked.link.address)",
      group: Int(unlinked.link.group.rawValue),
      product: unlinked.device?.deviceDescription.displayName
    )

  }

  /// The links removed without the device's SET button, in order.
  ///
  /// - Parameter removed: The links removed.
  /// - Returns: The links as JSON prints them, empty if the modem had none with the device.
  public static func removedLinks(_ removed: RemovedLinks) -> [RemovedLink] {

    let product: String? = removed.device?.deviceDescription.displayName

    return removed.links.map { (link: ModemLink) -> RemovedLink in

      RemovedLink(
        address: "\(removed.address)",
        group: Int(link.group.rawValue),
        modemRole: link.modemRole == .controller ? "controller" : "responder",
        product: product
      )

    }

  }

}
