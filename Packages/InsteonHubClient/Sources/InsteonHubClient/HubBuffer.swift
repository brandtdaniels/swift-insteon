import Foundation

/// The Hub's buffer of bytes received from its modem, as read with ``Hub/readBuffer()``.
///
/// The Hub keeps the modem's replies in a ring buffer: new bytes overwrite the oldest once
/// it fills, and ``HubBuffer/endIndex`` marks where the Hub writes the next byte. Use a
/// ``HubBufferCursor`` to pick out the bytes that are new since the last read.
public struct HubBuffer: Hashable, Sendable {

  /// The buffer's contents.
  public let bytes: [UInt8]

  /// The index in ``HubBuffer/bytes`` where the Hub writes the next byte.
  public let endIndex: Int

  /// Creates a buffer.
  ///
  /// - Parameters:
  ///   - bytes: The buffer's contents.
  ///   - endIndex: The index where the Hub writes the next byte.
  public init(bytes: [UInt8], endIndex: Int) {

    self.bytes = bytes
    self.endIndex = endIndex

  }

  /// Parses the Hub's `buffstatus.xml` response.
  ///
  /// The response is `<response><BS>…</BS></response>`, where the hex digits are the buffer
  /// followed by two more giving the end position in hex digits.
  ///
  /// - Parameter response: The response body as text.
  /// - Throws: ``HubError/malformedBuffer`` if the response isn't in that form.
  public init(response: String) throws(HubError) {

    guard
      let start = response.range(of: "<BS>")?.upperBound,
      let end = response.range(of: "</BS>", range: start..<response.endIndex)?.lowerBound
    else {

      throw .malformedBuffer

    }

    let hex = Array(response[start..<end].filter { !$0.isWhitespace })

    // ASCII only: `isHexDigit` also accepts full-width digits, which don't parse.
    guard hex.count >= 2, hex.count.isMultiple(of: 2), hex.allSatisfy({ $0.isASCII && $0.isHexDigit }) else {

      throw .malformedBuffer

    }

    let contents = hex.dropLast(2)
    let bytes = stride(from: contents.startIndex, to: contents.endIndex, by: 2).compactMap {
      UInt8(String(contents[$0..<$0 + 2]), radix: 16)
    }

    // The end position counts hex digits, so it's always even and within the buffer.
    guard
      bytes.count * 2 == contents.count,
      let endDigit = Int(String(hex.suffix(2)), radix: 16),
      endDigit.isMultiple(of: 2),
      endDigit / 2 <= bytes.count
    else {

      throw .malformedBuffer

    }

    self.init(bytes: bytes, endIndex: endDigit / 2)

  }

}
