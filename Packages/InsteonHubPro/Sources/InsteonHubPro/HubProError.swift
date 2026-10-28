/// Errors reported by ``HubProClient``.
public enum HubProError: Error, Hashable, Sendable {

  /// The Hub Pro answered with a status other than `200 OK`.
  case unexpectedStatus(Int)

  /// The device to add or remove didn't answer the Hub Pro, which reports it as a missing
  /// `FromAddress` or `Device.InsteonEngineVersion`.
  case deviceNotResponding

  /// The Hub Pro reported an error, with its message.
  case rejected(String)

  /// The answer wasn't the JSON the Hub Pro sends.
  case malformedResponse

  /// The host is empty or isn't a host name or IP address, or the port isn't from 0 to 65535.
  case invalidEndpoint

}
