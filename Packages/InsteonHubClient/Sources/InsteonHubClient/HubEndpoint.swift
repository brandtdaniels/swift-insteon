/// Where an INSTEON Hub can be reached on the local network.
public struct HubEndpoint: Hashable, Sendable {

  /// The port of the local HTTP interface on the Hub 2 (model 2245) and Hub 1 (model 2242):
  /// `25105`.
  public static let defaultPort = 25105

  /// The Hub's host name or IP address.
  public var host: String

  /// The port of the Hub's HTTP interface.
  public var port: Int

  /// Creates an endpoint.
  ///
  /// - Parameters:
  ///   - host: The Hub's host name or IP address.
  ///   - port: The port of the Hub's HTTP interface. Defaults to ``HubEndpoint/defaultPort``.
  public init(host: String, port: Int = HubEndpoint.defaultPort) {

    self.host = host
    self.port = port

  }

}
