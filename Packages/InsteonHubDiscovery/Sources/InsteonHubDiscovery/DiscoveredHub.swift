import InsteonHubClient
import InsteonProtocol

/// An Insteon Hub that ``HubDiscovery`` found on the local network, or that
/// ``InsteonConnectLookup`` found listed for it.
///
/// The same Hub found both ways compares unequal when only one knows its Insteon ID or
/// identity, so merge results by ``DiscoveredHub/endpoint``.
///
/// The synthesized equality includes ``DiscoveredHub/foundBy``, so the same Hub found by
/// different sources compares unequal even when every other field matches; combine such records
/// with ``DiscoveredHub/merge(with:)``.
///
/// Connect to it with the user name and password printed on the Hub:
///
/// ```swift
/// let connection = HubConnection(hub: Hub(endpoint: hub.endpoint, user: username, password: password))
/// ```
public struct DiscoveredHub: Hashable, Sendable {

  /// Where the Hub answers on the local network.
  public var endpoint: HubEndpoint

  /// The Hub's Insteon ID, printed on its label, when the way it was found reports one, so a
  /// user with several Hubs can tell them apart. ``HubDiscovery`` doesn't;
  /// ``InsteonConnectLookup`` does.
  public var insteonID: InsteonAddress?

  /// The category of the Hub's modem, when the way it was found reports one: always
  /// `DeviceCategory.networkBridges` for a Hub. ``InsteonConnectLookup`` reports it;
  /// ``HubDiscovery`` doesn't.
  public var category: DeviceCategory?

  /// The subcategory of the Hub's modem, which names the Hub's model, such as `0x33` for a
  /// Hub 2245, when the way it was found reports one. ``InsteonConnectLookup`` reports it;
  /// ``HubDiscovery`` doesn't.
  public var subcategory: DeviceSubcategory?

  /// The firmware version of the Hub's modem, when the way it was found reports one.
  /// ``InsteonConnectLookup`` reports it, from the Get Info page's PLM Firmware; ``HubDiscovery``
  /// doesn't.
  public var modemFirmwareVersion: FirmwareVersion?

  /// The kind of Hub as Insteon's servers name it, such as `"HUB2"` for a Hub 2245 or `"HUB1"`
  /// for a Hub 2242, when the way it was found reports one. ``InsteonConnectLookup`` reports
  /// it; ``HubDiscovery`` doesn't.
  public var unitType: String?

  /// The ways this Hub was found, such as both the local network and Insteon Connect when both
  /// report it.
  ///
  /// ``HubDiscovery`` and ``InsteonConnectLookup`` leave this empty; ``HubFinder`` fills it as
  /// it runs each way and unions the sources when it merges the same Hub found both ways.
  public var foundBy: Set<DiscoverySource>

  /// Creates a discovered Hub.
  ///
  /// - Parameters:
  ///   - endpoint: Where the Hub answers.
  ///   - insteonID: The Hub's Insteon ID, if known. Defaults to `nil`.
  ///   - category: The category of the Hub's modem, if known. Defaults to `nil`.
  ///   - subcategory: The subcategory of the Hub's modem, if known. Defaults to `nil`.
  ///   - modemFirmwareVersion: The firmware version of the Hub's modem, if known. Defaults to
  ///     `nil`.
  ///   - unitType: The kind of Hub as Insteon's servers name it, if known. Defaults to `nil`.
  ///   - foundBy: The ways this Hub was found. Defaults to none.
  public init(
    endpoint: HubEndpoint,
    insteonID: InsteonAddress? = nil,
    category: DeviceCategory? = nil,
    subcategory: DeviceSubcategory? = nil,
    modemFirmwareVersion: FirmwareVersion? = nil,
    unitType: String? = nil,
    foundBy: Set<DiscoverySource> = []
  ) {

    self.endpoint = endpoint
    self.insteonID = insteonID
    self.category = category
    self.subcategory = subcategory
    self.modemFirmwareVersion = modemFirmwareVersion
    self.unitType = unitType
    self.foundBy = foundBy

  }

  /// Merges another record of the same Hub into this one, keeping what either way knows.
  ///
  /// Each field this record doesn't know is taken from `other`, and the two records'
  /// ``DiscoveredHub/foundBy`` sets are combined. This record's known fields are kept, so merge
  /// the later way's record into the earlier one to prefer the earlier way's values.
  ///
  /// - Parameter other: Another record of the same Hub, usually found a different way.
  public mutating func merge(with other: DiscoveredHub) {

    insteonID = insteonID ?? other.insteonID
    category = category ?? other.category
    subcategory = subcategory ?? other.subcategory
    modemFirmwareVersion = modemFirmwareVersion ?? other.modemFirmwareVersion
    unitType = unitType ?? other.unitType
    foundBy.formUnion(other.foundBy)

  }

}
