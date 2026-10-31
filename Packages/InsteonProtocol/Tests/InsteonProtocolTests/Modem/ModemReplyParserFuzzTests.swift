import Testing
import InsteonProtocol

/// Feeds ``ModemReplyParser`` seeded random streams, so every run sees the same bytes.
struct ModemReplyParserFuzzTests {

  /// What a composed stream is built from.
  enum Unit {

    /// A whole frame and the reply it carries.
    case frame([UInt8], ModemReply)

    /// `02 <number> 15`: a NAK to a command whose reply carries data.
    case shortNegativeAcknowledgment(SerialCommandNumber)

    /// A lone NAK byte where a frame would start.
    case negativeAcknowledgment

    /// Bytes that start no frame and hold no NAK.
    case garbage([UInt8])

  }

  /// Frames from the parser's tests, and messages from a device and to a modem whose
  /// addresses start with an ACK byte.
  static let frames: [([UInt8], ModemReply)] = ModemReplyParserTests.replies.map { (fixture: (String, ModemReply)) -> ([UInt8], ModemReply) in (bytes(fixture.0), fixture.1) } + [
    (
      bytes("0250" + "06BBCC" + "112233" + "2B" + "11FF"),
      .messageReceived(ReceivedMessage(
        sender: InsteonAddress(0x06, 0xBB, 0xCC),
        destination: InsteonAddress(0x11, 0x22, 0x33),
        flags: MessageFlags(rawValue: 0x2B),
        command: Command(command1: 0x11, command2: 0xFF)
      ))
    ),
    (
      bytes("0250" + "AABBCC" + "060606" + "2B" + "1106"),
      .messageReceived(ReceivedMessage(
        sender: InsteonAddress(0xAA, 0xBB, 0xCC),
        destination: InsteonAddress(0x06, 0x06, 0x06),
        flags: MessageFlags(rawValue: 0x2B),
        command: Command(command1: 0x11, command2: 0x06)
      ))
    )
  ]

  static let numbersWithData: [SerialCommandNumber] = [.getModemInfo, .getModemConfiguration, .readRadioStatus]

  static let likelyBytes: [UInt8] = [0x02, 0x06, 0x15, 0x50, 0x51, 0x60, 0x62, 0x73, 0x7E]

  static let seeds: [UInt64] = [1, 2, 3, 0x1A2B3C, 0xC0FFEE]

  // Valid frames with NAKs and garbage between them: the parser reports exactly what each
  // unit stands for, so a NAK is never read as an accepted reply, however the bytes are split.
  @Test(arguments: seeds)
  func reportsEachUnitOfAComposedStream(seed: UInt64) {

    var random = SplitMix64(seed: seed)

    for _ in 0..<400 {

      let units: [Unit] = Self.composedStream(using: &random)
      var bytes: [UInt8] = []
      var expected: [ModemReply] = []

      for unit in units {

        switch unit {
        case let .frame(frame, reply):
          bytes += frame
          expected.append(reply)
        case let .shortNegativeAcknowledgment(number):
          bytes += [0x02, number.rawValue, 0x15]
          expected.append(.echo(CommandEcho(number: number, parameters: [], isAccepted: false)))
        case .negativeAcknowledgment:
          bytes.append(0x15)
          expected.append(.negativeAcknowledgment)
        case let .garbage(garbage):
          bytes += garbage
        }

      }

      let replies: [ModemReply] = Self.parse(bytes, chunkedUsing: &random)

      #expect(replies == expected, "bytes: \(Self.hex(bytes))")

    }

  }

  // Any bytes at all: the parser never traps, reports the same replies however the bytes are
  // split, and always gets past what came before, so replies that follow are reported.
  @Test(arguments: seeds)
  func recoversFromRandomBytes(seed: UInt64) {

    var random = SplitMix64(seed: seed)
    let userResets: [UInt8] = Array(repeating: [UInt8]([0x02, 0x55]), count: 20).flatMap { $0 }

    for _ in 0..<400 {

      let count: Int = Int.random(in: 0...120, using: &random)
      // Start bytes, answers and frame numbers come up more often than they would at random.
      var bytes: [UInt8] = []

      for _ in 0..<count {

        if Bool.random(using: &random) {

          bytes.append(Self.likelyBytes.randomElement(using: &random)!)

        } else {

          bytes.append(UInt8.random(in: 0...255, using: &random))

        }

      }

      var whole = ModemReplyParser()
      let all: [ModemReply] = whole.parse(bytes)

      var chunked = ModemReplyParser()
      var index = 0
      var pieces: [ModemReply] = []

      while index < bytes.count {

        let end: Int = min(index + Int.random(in: 1...8, using: &random), bytes.count)
        pieces += chunked.parse(bytes[index..<end])
        index = end

      }

      #expect(pieces == all, "bytes: \(Self.hex(bytes))")

      // A frame is at most 25 bytes, so whatever is pending ends within the user resets and
      // the rest of them are reported.
      let after: [ModemReply] = whole.parse(userResets)
      let trailing: Int = after.reversed().prefix { $0 == .userReset }.count

      #expect(trailing >= 5, "bytes: \(Self.hex(bytes))")

    }

  }

  /// Units in an order the parser can read without guessing: a short NAK is followed by a
  /// frame or ends the stream, and garbage isn't followed by a lone NAK, which would be
  /// skipped with it.
  static func composedStream(using random: inout SplitMix64) -> [Unit] {

    var units: [Unit] = []

    for _ in 0..<Int.random(in: 1...12, using: &random) {

      let previous: Unit? = units.last
      var choices: [Int] = [0, 1, 2, 3]

      switch previous {
      case .shortNegativeAcknowledgment?:
        choices = [0]
      case .garbage?:
        choices = [0, 1]
      default:
        break
      }

      switch choices.randomElement(using: &random)! {
      case 0:
        let (frame, reply) = frames.randomElement(using: &random)!
        units.append(.frame(frame, reply))
      case 1:
        units.append(.shortNegativeAcknowledgment(numbersWithData.randomElement(using: &random)!))
      case 2:
        units.append(.negativeAcknowledgment)
      default:
        let garbage: [UInt8] = (0..<Int.random(in: 1...6, using: &random)).map { (_: Int) -> UInt8 in

          var byte: UInt8 = UInt8.random(in: 0...255, using: &random)

          while byte == 0x02 || byte == 0x15 {

            byte = UInt8.random(in: 0...255, using: &random)

          }

          return byte

        }

        units.append(.garbage(garbage))
      }

    }

    return units

  }

  /// The replies to bytes fed in random chunks, then whatever a NAK held back at the end
  /// stands for.
  static func parse(_ bytes: [UInt8], chunkedUsing random: inout SplitMix64) -> [ModemReply] {

    var parser = ModemReplyParser()
    var replies: [ModemReply] = []
    var index = 0

    while index < bytes.count {

      let end: Int = min(index + Int.random(in: 1...8, using: &random), bytes.count)
      replies += parser.parse(bytes[index..<end])
      index = end

    }

    return replies + parser.finishPendingReply()

  }

  static func bytes(_ hex: String) -> [UInt8] {

    let digits = Array(hex)

    return stride(from: 0, to: digits.count, by: 2).map { UInt8(String(digits[$0..<$0 + 2]), radix: 16)! }

  }

  static func hex(_ bytes: [UInt8]) -> String {

    bytes.map { (byte: UInt8) -> String in

      let digits = String(byte, radix: 16, uppercase: true)

      return digits.count == 1 ? "0" + digits : digits

    }.joined(separator: " ")

  }

}

/// A small, fast generator whose numbers depend only on its seed.
struct SplitMix64: RandomNumberGenerator {

  private var state: UInt64

  init(seed: UInt64) {

    state = seed

  }

  mutating func next() -> UInt64 {

    state &+= 0x9E37_79B9_7F4A_7C15

    var z: UInt64 = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB

    return z ^ (z >> 31)

  }

}
