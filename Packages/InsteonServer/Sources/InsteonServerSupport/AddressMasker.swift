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
    // ALL-Linking completed, ALL-Link record response.
    0x53: [4], 0x57: [4],
    // ALL-Link cleanup failure report: group, then address. The offset is from a Hub 2's bench trace,
    // where the frame is six bytes, `02 56 05 C1 C2 C3`.
    0x56: [3],
    // A Hub 2 sends `02 5C` in the layout of a standard message received: from, to, flags, cmd1,
    // cmd2. The layout is inferred from one bench trace, not from a document.
    0x5C: [2, 5],
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

    var tokens: [Token] = []

    for byte in bytes {

      guard let offset = reader.offset else {

        if byte == 0x02 { reader.offset = 1 }
        tokens.append(.byte(byte))
        continue

      }

      if offset == 1 {

        reader.number = byte
        reader.offset = Self.addressOffsets[byte] == nil ? nil : 2
        tokens.append(.byte(byte))
        continue

      }

      let starts = Self.addressOffsets[reader.number] ?? []
      let inside = starts.contains { $0 <= offset && offset < $0 + 3 }

      if inside {

        reader.pending.append(byte)
        reader.offset = offset + 1

        if reader.pending.count == 3 {

          tokens.append(.tag(tag(for: reader.pending)))
          reader.pending = []

        }

        if offset + 1 >= (starts.max() ?? 0) + 3 { reader.offset = nil }
        continue

      }

      tokens.append(.byte(byte))
      reader.offset = offset + 1
      if offset + 1 >= (starts.max() ?? 0) + 3 { reader.offset = nil }

    }

    if stream == .outbound { outbound = reader } else { inbound = reader }

    return maskingSeenAddresses(in: tokens).joined(separator: " ")

  }

  /// A byte shown as it is, or an address's tag.
  private enum Token {
    case byte(UInt8)
    case tag(String)
  }

  /// The tokens as text, with any three bytes in a row that are an address seen earlier in the run
  /// shown as its tag too, so a frame of a number the masker doesn't know can't show an address
  /// that an earlier frame did. It reads the bytes of one read, so an address split across two
  /// reads inside such a frame isn't caught.
  private func maskingSeenAddresses(in tokens: [Token]) -> [String] {

    var shown: [String] = []
    var index = 0

    while index < tokens.count {

      switch tokens[index] {
      case let .tag(text):
        shown.append(text)
      case let .byte(first):
        if index + 2 < tokens.count, case let .byte(second) = tokens[index + 1], case let .byte(third) = tokens[index + 2], let known = tags[Self.key([first, second, third])] {
          shown.append("@" + Self.hex(known))
          index += 2
        } else {
          shown.append(Self.hex(first))
        }
      }

      index += 1

    }

    return shown

  }

  /// Forgets a half-read frame, as after the Hub cleared its buffer.
  mutating func resetInbound() {

    inbound = Reader()

  }

  private mutating func tag(for address: [UInt8]) -> String {

    let key = Self.key(address)

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

  private static func key(_ address: [UInt8]) -> UInt32 {

    UInt32(address[0]) << 16 | UInt32(address[1]) << 8 | UInt32(address[2])

  }

  private static func hex(_ byte: UInt8) -> String {

    WireTraceLogger.hex(byte)

  }

}
