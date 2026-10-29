/// The role a modem takes when ALL-Linking with another device.
public enum AllLinkMode: UInt8, CaseIterable, Hashable, Sendable {

  /// The modem responds to the other device (`0x00`).
  case responder = 0x00

  /// The modem controls the other device (`0x01`).
  case controller = 0x01

  /// The modem controls the other device if it starts linking, and responds otherwise (`0x03`).
  case controllerOrResponder = 0x03

  /// Deletes the link instead of creating one (`0xFF`).
  case delete = 0xFF

}

extension AllLinkMode {

  /// The modem's role by name, as a report of a link gives it: `"responder"`,
  /// `"controller"`, `"controller or responder"`, or `"deleted"` for a link that was deleted.
  public var name: String {

    switch self {
    case .responder: "responder"
    case .controller: "controller"
    case .controllerOrResponder: "controller or responder"
    case .delete: "deleted"
    }

  }

}
