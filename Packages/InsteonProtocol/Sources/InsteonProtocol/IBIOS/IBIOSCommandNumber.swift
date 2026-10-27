/// The number that identifies a command a host sends to a device running IBIOS.
///
/// Every IBIOS command starts with ``SerialCommand/startOfText`` (`0x02`) followed by its
/// number, and the device's echo repeats it.
public enum IBIOSCommandNumber: UInt8, CaseIterable, Hashable, Sendable {

  /// Download (`0x40`).
  case download = 0x40

  /// Upload (`0x42`).
  case upload = 0x42

  /// Get Checksum (`0x44`).
  case getChecksum = 0x44

  /// Mask (`0x46`).
  case mask = 0x46

  /// Simulated Event (`0x47`).
  case simulateEvent = 0x47

  /// Get Version (`0x48`).
  case getVersion = 0x48

}
