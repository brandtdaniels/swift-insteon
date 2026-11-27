/// Replaces the Insteon addresses in the frames of a wire trace with short tags, such as `@A1`.
///
/// It reads the frames it knows by their command number and masks the three-byte address fields
/// at the offsets the Insteon Modem Developer's Guide gives them, so a trace can be pasted
/// without naming a device. The same address has the same tag for as long as the masker lives,
/// and a different address a different one, up to 256 addresses. The tag follows from a salted
/// hash, and the salt is random for each run, so a tag says nothing outside its own trace.
///
/// It is best effort: bytes outside a recognized frame, such as noise on a serial line, pass as
/// they are, and an address that a stray byte leaves out of step may be shown.
struct AddressMasker {

  /// The two directions a stream of bytes can go, each read as its own sequence of frames.
  enum Stream { case outbound, inbound }

  /// Seeds the tags.
  let salt: UInt64

  private var tags: [UInt32: UInt8] = [:]

  private var taken: Set<UInt8> = []

  private var outbound = Reader()

  private var inbound = Reader()

  init(salt: UInt64 = .random(in: .min ... .max)) {

    self.salt = salt

  }

  /// Where an address starts, by frame number: the offsets from the frame's `0x02`.
  private static let addressOffsets: [UInt8: [Int]] = [
    // Standard and extended messages received: from, then to.
    0x50: [2, 5], 0x51: [2, 5],
    // ALL-Linking completed, ALL-Link record response, ALL-Link cleanup failure report.
    0x53: [4], 0x57: [4], 0x56: [4],
    // Get IM Info's reply, send standard or extended message, manage ALL-Link record.
    0x60: [2], 0x62: [2], 0x6F: [5],
  ]

  private struct Reader {
    /// The frame being read: its offset of the next byte, and its number.
    var offset: Int?
    var number: UInt8 = 0
    var pending: [UInt8] = []
  }

  /// The bytes as hex, with each recognized address replaced by its tag. An address cut short by
  /// the end of the bytes is held and shown, as a tag, with the bytes that finish it.
  mutating func mask(_ bytes: [UInt8], in stream: Stream) -> String {

    var reader = stream == .outbound ? outbound : inbound
    // Each write is a frame of its own, so one that stops short doesn't carry over.
    if stream == .outbound { reader = Reader() }

    var tokens: [String] = []

    for byte in bytes {

      guard let offset = reader.offset else {

        if byte == 0x02 { reader.offset = 1 }
        tokens.append(Self.hex(byte))
        continue

      }

      if offset == 1 {

        reader.number = byte
        reader.offset = Self.addressOffsets[byte] == nil ? nil : 2
        tokens.append(Self.hex(byte))
        continue

      }

      let starts = Self.addressOffsets[reader.number] ?? []
      let inside = starts.contains { $0 <= offset && offset < $0 + 3 }

      if inside {

        reader.pending.append(byte)
        reader.offset = offset + 1

        if reader.pending.count == 3 {

          tokens.append(tag(for: reader.pending))
          reader.pending = []

        }

        if offset + 1 >= (starts.max() ?? 0) + 3 { reader.offset = nil }
        continue

      }

      tokens.append(Self.hex(byte))
      reader.offset = offset + 1
      if offset + 1 >= (starts.max() ?? 0) + 3 { reader.offset = nil }

    }

    if stream == .outbound { outbound = reader } else { inbound = reader }

    return tokens.joined(separator: " ")

  }

  /// Forgets a half-read frame, as after the Hub cleared its buffer.
  mutating func resetInbound() {

    inbound = Reader()

  }

  private mutating func tag(for address: [UInt8]) -> String {

    let key = UInt32(address[0]) << 16 | UInt32(address[1]) << 8 | UInt32(address[2])

    if let known = tags[key] { return "@" + Self.hex(known) }

    // A splitmix64 step over the salted address, whose low byte is the tag. A taken tag moves
    // on to the next, so two addresses of one run never share one.
    var mixed = salt &+ UInt64(key) &* 0x9E37_79B9_7F4A_7C15
    mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
    mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
    var candidate = UInt8(truncatingIfNeeded: mixed ^ (mixed >> 31))
    if taken.count < 256 { while taken.contains(candidate) { candidate &+= 1 } }

    taken.insert(candidate)
    tags[key] = candidate

    return "@" + Self.hex(candidate)

  }

  private static func hex(_ byte: UInt8) -> String {

    WireTraceLogger.hex(byte)

  }

}
