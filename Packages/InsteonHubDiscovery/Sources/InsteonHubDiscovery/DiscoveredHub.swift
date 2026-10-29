import InsteonHubClient
import InsteonProtocol

/// An Insteon Hub that ``HubDiscovery`` found on the local network, or that
/// ``InsteonConnectLookup`` found listed for it.
///
/// The same Hub found both ways compares unequal when only one knows its Insteon ID or
/// identity, so merge results by ``DiscoveredHub/endpoint``.
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
  public init(
    endpoint: HubEndpoint,
    insteonID: InsteonAddress? = nil,
    category: DeviceCategory? = nil,
    subcategory: DeviceSubcategory? = nil,
    modemFirmwareVersion: FirmwareVersion? = nil,
    unitType: String? = nil
  ) {

    self.endpoint = endpoint
    self.insteonID = insteonID
    self.category = category
    self.subcategory = subcategory
    self.modemFirmwareVersion = modemFirmwareVersion
    self.unitType = unitType

  }

}
