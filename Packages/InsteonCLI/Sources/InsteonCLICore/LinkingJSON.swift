import InsteonCore
import InsteonDeviceCatalog
import InsteonLinking
import InsteonProtocol

/// What `insteon link`, `insteon unlink` and `insteon remove` print with `--json`, built from
/// what a `DeviceLinkingCoordinator` returns.
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

    /// Each leg's link of the catalog's linking from a Hub, and what became of each leg.
    case legs(LegsReport)

    /// Encodes the link as an object, the links as an array, or the legs as an object with
    /// `links` and `legs`.
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
      case let .legs(report):
        try container.encode(report)
      }

    }

  }

  /// A leg of the catalog's linking from a Hub, and what became of it.
  public struct Leg: Encodable, Hashable, Sendable {

    /// The modem's role in the leg, `"controller"` or `"responder"`.
    public let modemRole: String

    /// The group Start ALL-Linking named.
    public let modemGroup: Int

    /// The device's group, which Enter Linking Mode named.
    public let deviceGroup: Int

    /// `"linked"`, `"failed"`, or `"notRun"` for a leg after one that failed.
    public let status: String

    /// How the device joined a linked leg: `"enterLinkingMode"`, `"setButton"` or
    /// `"deviceFirst"`.
    public let joinedBy: String?

    /// Why a failed leg didn't link.
    public let error: String?

  }

  /// What `insteon link --json` prints for a device linked by the catalog's legs.
  public struct LegsReport: Encodable, Hashable, Sendable {

    /// Each leg's link, in order.
    public let links: [Link]

    /// Each leg, in the catalog's order.
    public let legs: [Leg]

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

  /// A link between the modem and a device, by the modem's role and group.
  public struct ModemLinkReport: Encodable, Hashable, Sendable {

    /// The modem's group.
    public let group: Int

    /// The modem's role in the link, `"controller"` or `"responder"`.
    public let modemRole: String

  }

  /// A record in a device's ALL-Link database that names a removed device.
  public struct LeftoverRecord: Encodable, Hashable, Sendable {

    /// The record's address in the database, such as `"0x0FF7"`.
    public let recordAddress: String

    /// The record's role, `"controller"` or `"responder"`.
    public let role: String

    /// The record's group.
    public let group: Int

  }

  /// A device whose ALL-Link database names a removed device.
  public struct LeftoverHolder: Encodable, Hashable, Sendable {

    /// The device's address.
    public let address: String

    /// The product's name and model, when the device is known.
    public let product: String?

    /// The records that name the removed device.
    public let records: [LeftoverRecord]

  }

  /// A device whose ALL-Link database couldn't be read.
  public struct UnreadDevice: Encodable, Hashable, Sendable {

    /// The device's address.
    public let address: String

    /// Why the database couldn't be read.
    public let error: String

  }

  /// The catalog's factory reset steps for a removed device.
  public struct FactoryReset: Encodable, Hashable, Sendable {

    /// The steps, each with what the device does in answer, or `nil` when the catalog has
    /// none for the device.
    public let steps: [String]?

    /// The catalog's notes on the reset.
    public let notes: [String]

    /// What a reset erases, as the catalog names it, such as `"links"`.
    public let erases: [String]

  }

  /// What `insteon remove --json` prints.
  public struct Removal: Encodable, Sendable {

    /// The device's address.
    public let address: String

    /// The product's name and model, when the device was known.
    public let product: String?

    /// The links removed through the device.
    public let removedLinks: [ModemLinkReport]

    /// Why the links couldn't be removed through the device, when the modem's records for it
    /// were deleted instead.
    public let remoteUnlinkingFailure: String?

    /// The modem's records for the device deleted directly, with `--force-modem-side`.
    public let deletedModemRecords: [ModemLinkReport]

    /// The links the modem still has with the device, or `nil` if its database couldn't be
    /// read.
    public let remainingLinks: [ModemLinkReport]?

    /// The devices whose databases still name the device, with `--scan`.
    public let leftoverRecords: [LeftoverHolder]?

    /// The devices whose databases couldn't be read, with `--scan`.
    public let unreadDevices: [UnreadDevice]?

    /// Whether the device was removed and forgotten; `false` when it was kept.
    public let forgotten: Bool

    /// Why the device was kept, or `nil` when it was forgotten.
    public let keptBecause: String?

    /// The catalog's factory reset steps, or `nil` when the device was kept.
    public let factoryReset: FactoryReset?

  }

  /// What `insteon remove --json` prints for a removal.
  ///
  /// - Parameters:
  ///   - result: What the coordinator did.
  ///   - message: The sentence that describes an error, ending with a period.
  /// - Returns: The report.
  public static func removal(_ result: DeviceRemovalResult, message: (any Error) -> String) -> Removal {

    let scan: LeftoverRecordScan? = result.leftoverRecords
    var factoryReset: FactoryReset?

    if let reset = result.factoryReset {

      let steps: [String]? = reset.procedure.map { (procedure: DeviceLifecycle.Procedure) -> [String] in

        LinkingInstructions.steps(procedure.steps)

      }

      factoryReset = FactoryReset(steps: steps, notes: reset.procedure?.notes ?? [], erases: reset.erases.map(\.rawValue).sorted())

    }

    var keptBecause: String?

    if let reason = result.keptBecause {

      keptBecause = RemovalText.keptReason(result.address, reason, message: message)

    }

    let deleted: [ModemLinkReport] = result.deletedModemRecords.map { (record: AllLinkRecord) -> ModemLinkReport in

      ModemLinkReport(group: Int(record.group.rawValue), modemRole: RemovalText.role(record))

    }
    let remaining: [ModemLinkReport]? = result.remainingLinks.map { (links: [ModemLink]) -> [ModemLinkReport] in

      links.map(modemLink)

    }
    let holders: [LeftoverHolder]? = scan.map { (found: LeftoverRecordScan) -> [LeftoverHolder] in

      found.holders.map(leftoverHolder)

    }
    var unread: [UnreadDevice]?

    if let scan {

      unread = scan.unread.map { (database: UnreadDatabase) -> UnreadDevice in

        UnreadDevice(address: "\(database.address)", error: message(database.reason))

      }

    }

    var failure: String?

    if let error = result.remoteUnlinkingFailure {

      failure = message(error)

    }

    return Removal(
      address: "\(result.address)",
      product: result.removed.device?.deviceDescription.displayName,
      removedLinks: result.removed.links.map(modemLink),
      remoteUnlinkingFailure: failure,
      deletedModemRecords: deleted,
      remainingLinks: remaining,
      leftoverRecords: holders,
      unreadDevices: unread,
      forgotten: result.forgotten != nil,
      keptBecause: keptBecause,
      factoryReset: factoryReset
    )

  }

  /// A device whose database names a removed device, with those records.
  private static func leftoverHolder(_ holder: LeftoverRecords) -> LeftoverHolder {

    let records: [LeftoverRecord] = holder.records.map { (response: AllLinkRecordResponse) -> LeftoverRecord in

      LeftoverRecord(
        recordAddress: Hex.address(response.address),
        role: RemovalText.role(response.record),
        group: Int(response.record.group.rawValue)
      )

    }

    return LeftoverHolder(address: "\(holder.address)", product: holder.device?.deviceDescription.displayName, records: records)

  }

  /// A link between the modem and a device.
  private static func modemLink(_ link: ModemLink) -> ModemLinkReport {

    ModemLinkReport(group: Int(link.group.rawValue), modemRole: link.modemRole == .controller ? "controller" : "responder")

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
  /// the device was linked back. A device linked by the catalog's legs gets an object with
  /// its links and its legs, whose errors are described as `String(describing:)` gives them;
  /// ``LinkingJSON/report(_:message:)`` words them.
  ///
  /// - Parameter result: What the coordinator linked.
  /// - Returns: The report.
  public static func report(_ result: DeviceLinkingResult) -> LinkReport {

    report(result) { (error: any Error) -> String in String(describing: error) }

  }

  /// What `insteon link --json` prints for a link: an object for one link, an array when the
  /// device was linked back, or, for a device linked by the catalog's legs, an object with its
  /// links and its legs.
  ///
  /// - Parameters:
  ///   - result: What the coordinator linked.
  ///   - message: The sentence that describes an error, ending with a period.
  /// - Returns: The report.
  public static func report(_ result: DeviceLinkingResult, message: (any Error) -> String) -> LinkReport {

    let known: DeviceDescription? = result.device?.deviceDescription
    let links: [Link] = result.links.map { (made: AllLinkingCompleted) -> Link in link(made, known: known) }

    if !result.legs.isEmpty {

      return .legs(LegsReport(links: links, legs: result.legs.map { (outcome: HubLinkingLegOutcome) -> Leg in leg(outcome, message: message) }))

    }

    if links.count == 1 {

      return .link(links[0])

    }

    return .links(links)

  }

  /// A leg and what became of it.
  private static func leg(_ outcome: HubLinkingLegOutcome, message: (any Error) -> String) -> Leg {

    let status: String
    var joinedBy: String?
    var error: String?

    switch outcome.status {
    case let .linked(_, join):
      status = "linked"

      switch join {
      case .enterLinkingMode:
        joinedBy = "enterLinkingMode"
      case .setButton:
        joinedBy = "setButton"
      case .deviceFirst:
        joinedBy = "deviceFirst"
      }
    case let .failed(reason):
      status = "failed"
      error = message(reason)
    case .notRun:
      status = "notRun"
    }

    return Leg(
      modemRole: outcome.leg.modemRole == .controller ? "controller" : "responder",
      modemGroup: Int(outcome.leg.modemGroup.rawValue),
      deviceGroup: Int(outcome.leg.deviceGroup.rawValue),
      status: status,
      joinedBy: joinedBy,
      error: error
    )

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
