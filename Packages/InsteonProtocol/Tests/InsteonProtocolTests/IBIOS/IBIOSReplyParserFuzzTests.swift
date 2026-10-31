import Testing
import InsteonProtocol

/// Feeds ``IBIOSReplyParser`` seeded random streams, so every run sees the same bytes.
struct IBIOSReplyParserFuzzTests {

  /// Start bytes, answers, End of Text and frame numbers, which come up more often than they
  /// would at random.
  static let likelyBytes: [UInt8] = [0x02, 0x03, 0x06, 0x15, 0x40, 0x41, 0x42, 0x43, 0x45, 0x48, 0x4F]

  static let seeds: [UInt64] = [1, 2, 3, 0x1A2B3C, 0xC0FFEE]

  // Any bytes at all: the parser never traps, reports the same replies however the bytes are
  // split, and once a stalled frame is discarded reads the next reply.
  @Test(arguments: seeds)
  func recoversFromRandomBytes(seed: UInt64) {

    var random = SplitMix64(seed: seed)

    for _ in 0..<400 {

      var bytes: [UInt8] = []

      for _ in 0..<Int.random(in: 0...120, using: &random) {

        if Bool.random(using: &random) {

          bytes.append(Self.likelyBytes.randomElement(using: &random)!)

        } else {

          bytes.append(UInt8.random(in: 0...255, using: &random))

        }

      }

      var whole = IBIOSReplyParser()
      let all: [IBIOSReply] = whole.parse(bytes)

      var chunked = IBIOSReplyParser()
      var index = 0
      var pieces: [IBIOSReply] = []

      while index < bytes.count {

        let end: Int = min(index + Int.random(in: 1...8, using: &random), bytes.count)
        pieces += chunked.parse(bytes[index..<end])
        index = end

      }

      #expect(pieces == all, "bytes: \(ModemReplyParserFuzzTests.hex(bytes))")

      // Once nothing more arrives, whatever was pending is discarded.
      _ = whole.finishPendingReply()
      whole.discardStalledFrame()

      #expect(whole.parse([0x02, 0x45, 0x0A]) == [.eventReport(.buttonTapped)], "bytes: \(ModemReplyParserFuzzTests.hex(bytes))")

    }

  }

}
