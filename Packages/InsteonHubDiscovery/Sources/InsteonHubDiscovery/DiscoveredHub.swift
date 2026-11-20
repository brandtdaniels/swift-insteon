import InsteonHubClient
import InsteonHubPro
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

  /// The Hub's own firmware, as the Get Info page prints it, such as `1019` for a Hub 2245 or
  /// `s:1.0.2|c:5.0.1` for a Hub Pro, when the way it was found reports one.
  /// ``InsteonConnectLookup`` reports it; ``HubDiscovery`` doesn't.
  public var firmware: String?

  /// Which of Insteon's two local interfaces the Hub answers on. ``HubDiscovery`` reads it from
  /// the way the address answered; ``InsteonConnectLookup`` reads it from the unit type.
  public var kind: HubKind

  /// The settings a Hub Pro reported when ``HubDiscovery`` or ``HubProProbe`` confirmed it, or
  /// `nil` for a Hub, or for a Hub Pro found another way.
  public var hubProSettings: HubProSettings?

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
  ///   - firmware: The Hub's own firmware as the Get Info page prints it, if known. Defaults to
  ///     `nil`.
  ///   - kind: Which local interface the Hub answers on. Defaults to ``HubKind/hub``.
  ///   - hubProSettings: The settings a Hub Pro reported, if known. Defaults to `nil`.
  ///   - foundBy: The ways this Hub was found. Defaults to none.
  public init(
    endpoint: HubEndpoint,
    insteonID: InsteonAddress? = nil,
    category: DeviceCategory? = nil,
    subcategory: DeviceSubcategory? = nil,
    modemFirmwareVersion: FirmwareVersion? = nil,
    unitType: String? = nil,
    firmware: String? = nil,
    kind: HubKind = .hub,
    hubProSettings: HubProSettings? = nil,
    foundBy: Set<DiscoverySource> = []
  ) {

    self.endpoint = endpoint
    self.insteonID = insteonID
    self.category = category
    self.subcategory = subcategory
    self.modemFirmwareVersion = modemFirmwareVersion
    self.unitType = unitType
    self.firmware = firmware
    self.kind = kind
    self.hubProSettings = hubProSettings
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
    firmware = firmware ?? other.firmware

    hubProSettings = hubProSettings ?? other.hubProSettings

    if other.kind == .hubPro {

      kind = .hubPro

    }

    foundBy.formUnion(other.foundBy)

  }

}

/// Which local interface a ``DiscoveredHub`` answers on.
public enum HubKind: String, Hashable, Sendable, CaseIterable {

  /// The Hub interface: a buffer page that needs the user name and password printed on the
  /// Hub, and through which the Hub's modem is driven.
  case hub

  /// The Hub Pro's own HTTP interface, which answers a settings request without credentials and
  /// doesn't drive a modem the way ``HubKind/hub`` does.
  case hubPro

}
