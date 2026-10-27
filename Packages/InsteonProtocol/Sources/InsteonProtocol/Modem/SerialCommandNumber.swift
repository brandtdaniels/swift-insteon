/// The number that identifies a command sent from a host to an INSTEON modem.
///
/// Every serial command starts with ``SerialCommand/startOfText`` (`0x02`) followed by its
/// number.
public enum SerialCommandNumber: UInt8, CaseIterable, Hashable, Sendable {

  /// Get IM Info (`0x60`).
  case getModemInfo = 0x60

  /// Send ALL-Link Command (`0x61`).
  case sendAllLinkCommand = 0x61

  /// Send INSTEON Standard or Extended Message (`0x62`).
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

  /// Set INSTEON ACK Message Byte (`0x68`).
  case setAcknowledgementByte = 0x68

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

  /// Set INSTEON NAK Message Byte (`0x70`).
  case setNegativeAcknowledgementByte = 0x70

  /// Set INSTEON ACK Message Two Bytes (`0x71`).
  case setAcknowledgementBytes = 0x71

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

}
