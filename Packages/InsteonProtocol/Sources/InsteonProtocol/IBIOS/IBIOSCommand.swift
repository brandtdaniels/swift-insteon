/// A serial command a host sends to a device running IBIOS, the Insteon BIOS, such as a
/// PowerLinc Controller (2414U, 2414S).
///
/// IBIOS gives the host direct access to the device's memory: a host sends an Insteon message,
/// for example, by writing it into memory with ``IBIOSCommand/download(address:data:)`` and
/// setting a flag with ``IBIOSCommand/mask(address:or:and:)``. Every command starts with
/// ``SerialCommand/startOfText`` (`0x02`) and its number, and IBIOS echoes it with an ACK
/// (`0x06`) or NAK (`0x15`).
///
/// ```swift
/// IBIOSCommand.getVersion.bytes   // [0x02, 0x48]
/// ```
public enum IBIOSCommand: Hashable, Sendable {

  /// Writes bytes into memory (`0x40`), protected by a checksum.
  ///
  /// An ACK means IBIOS received the bytes, not that it wrote them correctly, so confirm a
  /// download with ``IBIOSCommand/getChecksum(address:length:)``.
  ///
  /// - Parameters:
  ///   - address: The address of the first byte to write.
  ///   - data: The bytes to write: at most 65,535, since the length is sent in two bytes.
  case download(address: UInt16, data: [UInt8])

  /// Reads bytes from memory (`0x42`).
  ///
  /// - Parameters:
  ///   - address: The address of the first byte to read.
  ///   - length: How many bytes to read.
  case upload(address: UInt16, length: UInt16)

  /// Asks for the checksum of a region of memory (`0x44`), for example to confirm a download.
  ///
  /// The checksum covers only the region's bytes, so a correct download of `data` reads back
  /// as `IBIOSCommand.checksum(of: data)`.
  ///
  /// - Parameters:
  ///   - address: The address of the region's first byte.
  ///   - length: The region's length.
  case getChecksum(address: UInt16, length: UInt16)

  /// Sets and clears bits in a register without touching the others (`0x46`).
  ///
  /// The register becomes `(register | or) & and`: bits set in `or` are set, and bits clear in
  /// `and` are cleared.
  ///
  /// - Parameters:
  ///   - address: The register's address.
  ///   - or: The bits to set.
  ///   - and: The bits to keep; the others are cleared.
  case mask(address: UInt16, or: UInt8, and: UInt8)

  /// Fires an event as if it had happened (`0x47`).
  ///
  /// - Parameters:
  ///   - event: The event to fire.
  ///   - timer: `0` to fire the event at once, or a delay: 1 to 127 seconds, or 1 to 127
  ///     minutes with bit 7 set.
  case simulateEvent(IBIOSEvent, timer: UInt8)

  /// Asks for the device's address, device category, subcategory and firmware version
  /// (`0x48`).
  case getVersion

  /// The command's number.
  public var number: IBIOSCommandNumber {

    switch self {
    case .download: .download
    case .upload: .upload
    case .getChecksum: .getChecksum
    case .mask: .mask
    case .simulateEvent: .simulateEvent
    case .getVersion: .getVersion
    }

  }

  /// The bytes that follow the command number.
  public var parameters: [UInt8] {

    switch self {
    case let .download(address, data):
      precondition(data.count <= Int(UInt16.max), "An IBIOS download carries at most 65,535 bytes.")

      let header = address.bigEndianBytes + UInt16(data.count).bigEndianBytes
      return header + Self.checksum(of: header + data).bigEndianBytes + data
    case let .upload(address, length), let .getChecksum(address, length):
      return address.bigEndianBytes + length.bigEndianBytes
    case let .mask(address, or, and):
      return address.bigEndianBytes + [or, and]
    case let .simulateEvent(event, timer):
      return [event.rawValue, timer]
    case .getVersion:
      return []
    }

  }

  /// The checksum IBIOS uses for downloads, uploads and ``IBIOSCommand/getChecksum(address:length:)``:
  /// the two's complement of the 16-bit sum of the bytes.
  ///
  /// - Parameter bytes: The bytes to sum.
  /// - Returns: The checksum.
  public static func checksum(of bytes: some Sequence<UInt8>) -> UInt16 {

    0 &- bytes.reduce(UInt16(0)) { $0 &+ UInt16($1) }

  }

}

// MARK: - ByteEncodable

extension IBIOSCommand: ByteEncodable {

  /// The command's bytes: ``SerialCommand/startOfText``, the number and the parameters.
  public var bytes: [UInt8] {

    [SerialCommand.startOfText, number.rawValue] + parameters

  }

}
