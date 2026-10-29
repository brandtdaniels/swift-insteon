/// The number that identifies a command sent from a host to an Insteon modem.
///
/// Every serial command starts with ``SerialCommand/startOfText`` (`0x02`) followed by its
/// number.
public enum SerialCommandNumber: UInt8, CaseIterable, Hashable, Sendable {

  /// Get IM Info (`0x60`).
  case getModemInfo = 0x60

  /// Send ALL-Link Command (`0x61`).
  case sendAllLinkCommand = 0x61

  /// Send Insteon Standard or Extended Message (`0x62`).
  case sendMessage = 0x62

  /// Send X10 (`0x63`).
  case sendX10 = 0x63

  /// Start ALL-Linking (`0x64`).
  case startAllLinking = 0x64

  /// Cancel ALL-Linking (`0x65`).
  case cancelAllLinking = 0x65

  /// Set Host Device Category (`0x66`).
  case setHostDeviceCategory = 0x66

  /// Reset the IM (`0x67`).
  case resetModem = 0x67

  /// Set Insteon ACK Message Byte (`0x68`).
  case setAcknowledgmentByte = 0x68

  /// Get First ALL-Link Record (`0x69`).
  case getFirstAllLinkRecord = 0x69

  /// Get Next ALL-Link Record (`0x6A`).
  case getNextAllLinkRecord = 0x6A

  /// Set IM Configuration (`0x6B`).
  case setModemConfiguration = 0x6B

  /// Get ALL-Link Record for Sender (`0x6C`).
  case getAllLinkRecordForSender = 0x6C

  /// LED On (`0x6D`).
  case ledOn = 0x6D

  /// LED Off (`0x6E`).
  case ledOff = 0x6E

  /// Manage ALL-Link Record (`0x6F`).
  case manageAllLinkRecord = 0x6F

  /// Set Insteon NAK Message Byte (`0x70`).
  case setNegativeAcknowledgmentByte = 0x70

  /// Set Insteon ACK Message Two Bytes (`0x71`).
  case setAcknowledgmentBytes = 0x71

  /// RF Sleep (`0x72`).
  case rfSleep = 0x72

  /// Get IM Configuration (`0x73`).
  case getModemConfiguration = 0x73

  /// Cancel Cleanup (`0x74`).
  case cancelCleanup = 0x74

  /// Read 8 Bytes from Database (`0x75`).
  case readDatabase = 0x75

  /// Write 8 Bytes to Database (`0x76`).
  case writeDatabase = 0x76

  /// Beep (`0x77`).
  case beep = 0x77

  /// Set Responder Link Data (`0x79`).
  case setResponderLinkData = 0x79

  /// Set Application Retries (`0x7A`).
  case setApplicationRetries = 0x7A

  /// Set RF Disable Flag (`0x7D`).
  case setRadio = 0x7D

  /// Read RF Frequency (`0x7E`), from later modem firmware.
  case readRadioStatus = 0x7E

  /// Diagnostics (`0x81`), from later modem firmware.
  case readDiagnostics = 0x81

  /// Database Commands (`0x82`), from later modem firmware.
  case manageDeviceRecord = 0x82

}

extension SerialCommandNumber {

  /// The command's name, as the Insteon Modem Developer's Guide gives it, such as
  /// `"Get IM Info"` or `"Start ALL-Linking"`.
  public var name: String {

    switch self {
    case .getModemInfo: "Get IM Info"
    case .sendAllLinkCommand: "Send ALL-Link Command"
    case .sendMessage: "Send Insteon Standard or Extended Message"
    case .sendX10: "Send X10"
    case .startAllLinking: "Start ALL-Linking"
    case .cancelAllLinking: "Cancel ALL-Linking"
    case .setHostDeviceCategory: "Set Host Device Category"
    case .resetModem: "Reset the IM"
    case .setAcknowledgmentByte: "Set Insteon ACK Message Byte"
    case .getFirstAllLinkRecord: "Get First ALL-Link Record"
    case .getNextAllLinkRecord: "Get Next ALL-Link Record"
    case .setModemConfiguration: "Set IM Configuration"
    case .getAllLinkRecordForSender: "Get ALL-Link Record for Sender"
    case .ledOn: "LED On"
    case .ledOff: "LED Off"
    case .manageAllLinkRecord: "Manage ALL-Link Record"
    case .setNegativeAcknowledgmentByte: "Set Insteon NAK Message Byte"
    case .setAcknowledgmentBytes: "Set Insteon ACK Message Two Bytes"
    case .rfSleep: "RF Sleep"
    case .getModemConfiguration: "Get IM Configuration"
    case .cancelCleanup: "Cancel Cleanup"
    case .readDatabase: "Read 8 Bytes from Database"
    case .writeDatabase: "Write 8 Bytes to Database"
    case .beep: "Beep"
    case .setResponderLinkData: "Set Responder Link Data"
    case .setApplicationRetries: "Set Application Retries"
    case .setRadio: "Set RF Disable Flag"
    case .readRadioStatus: "Read RF Frequency"
    case .readDiagnostics: "Diagnostics"
    case .manageDeviceRecord: "Database Commands"
    }

  }

}
