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

  /// The modem's mode for removing a link in the role: unlinking mode as the controller, and
  /// linking mode as the responder, which joins a controller that's in unlinking mode, as with
  /// SET buttons.
  var unlinkingMode: AllLinkMode {

    switch self {
    case .controller: .delete
    case .responder: .responder
    }

  }

}
