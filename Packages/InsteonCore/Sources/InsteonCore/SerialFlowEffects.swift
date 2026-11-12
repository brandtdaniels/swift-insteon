import InsteonDeviceCatalog
import InsteonProtocol

/// What the serial commands InsteonCore's own flows build do to the modem, declared where the
/// flows build them, so a modem whose command set doesn't describe them, or that has none, is
/// sent them.
///
/// A declaration is read with the modem's command set, and the stricter of the two decides, so
/// it never weakens the catalog. Each frame is declared by its number and, where one number does
/// several things, by the control byte that tells them apart:
///
/// | Frame | Flow | Effect |
/// | --- | --- | --- |
/// | Get IM Info | every flow that identifies the modem | read only |
/// | Start ALL-Linking, link code `0x00`, `0x01` or `0x03` | `link` | link |
/// | Start ALL-Linking, link code `0xFF` | `unlink` | destructive |
/// | Cancel ALL-Linking | `link`, `unlink` | link |
/// | Get First and Get Next ALL-Link Record | every flow that reads the modem's database | read only |
/// | Manage ALL-Link Record, find codes `0x00` and `0x01` | every flow that reads a device's records | read only |
/// | Manage ALL-Link Record, codes `0x40` and `0x41` | `link --database` | destructive |
/// | Manage ALL-Link Record, code `0x80` | `remove --force-modem-side`, `unlink --database` | destructive |
/// | Send ALL-Link Command | `scene` | actuation |
/// | Send Insteon Standard or Extended Message | every message to a device | actuation |
/// | Beep | `beep` | actuation |
///
/// A message to a device is judged by the device's command set when a ``Device`` sends it, so a
/// frame that carries one declares only that it acts on the network.
enum SerialFlowEffects {

  /// What the flows declare a serial command does, or `nil` if no flow builds it.
  ///
  /// - Parameter bytes: The command's bytes, starting with `0x02`.
  /// - Returns: The declared effect.
  static func declaredEffect(of bytes: [UInt8]) -> CommandEffect? {

    guard bytes.count >= 2, bytes[0] == SerialCommand.startOfText, let number = SerialCommandNumber(rawValue: bytes[1]) else {

      return nil

    }

    let control: UInt8? = bytes.count > 2 ? bytes[2] : nil

    switch number {
    case .getModemInfo, .getFirstAllLinkRecord, .getNextAllLinkRecord:
      return .readOnly
    case .startAllLinking:
      switch control {
      case AllLinkMode.responder.rawValue?, AllLinkMode.controller.rawValue?, AllLinkMode.controllerOrResponder.rawValue?:
        return .link
      case AllLinkMode.delete.rawValue?:
        return .destructive
      default:
        return nil
      }
    case .cancelAllLinking:
      return .link
    case .manageAllLinkRecord:
      switch control {
      case AllLinkRecordAction.findFirst.rawValue?, AllLinkRecordAction.findNext.rawValue?:
        return .readOnly
      case AllLinkRecordAction.modifyFirstControllerOrAdd.rawValue?, AllLinkRecordAction.modifyFirstResponderOrAdd.rawValue?, AllLinkRecordAction.deleteFirst.rawValue?:
        return .destructive
      default:
        return nil
      }
    case .sendAllLinkCommand, .sendMessage, .beep:
      return .actuation
    default:
      return nil
    }

  }

}
