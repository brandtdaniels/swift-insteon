import InsteonProtocol

/// One end of an ALL-Link: the modem, or a device the modem can reach.
public enum LinkEndpoint: Hashable, Sendable {

  /// The modem the links are made through.
  case modem

  /// A device, by its address.
  case device(InsteonAddress)

}
