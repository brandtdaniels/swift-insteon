import InsteonProtocol

/// The modem's role in a link it makes with a device.
public enum ModemRole: Hashable, Sendable {

  /// The modem controls the device: the device joins one of the modem's ALL-Link groups.
  case controller

  /// The modem responds to the device: the modem joins one of the device's ALL-Link groups.
  case responder

  /// The modem's linking mode for the role.
  var linkingMode: AllLinkMode {

    switch self {
    case .controller: .controller
    case .responder: .responder
    }

  }

}
