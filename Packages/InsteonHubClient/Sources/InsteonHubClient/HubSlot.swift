import InsteonProtocol

/// One of the 256 slots in which a 2242 Hub keeps a scene or device it runs timers for.
///
/// The Hub arranges its slots as 16 pages of 16, and numbers them from 1: slot `n` is index
/// `(n - 1) % 16 + 1` on page `(n - 1) / 16 + 1`. Slot 240 holds the Hub's unlock code rather
/// than a timer.
public struct HubSlot: RawRepresentable, Hashable, Sendable, Comparable {

  /// The slot that holds the Hub's unlock code.
  public static let unlockCode = HubSlot(rawValue: 240)!

  /// The slot number, from 1 through 256.
  public let rawValue: Int

  /// Creates a slot from its number.
  ///
  /// - Parameter rawValue: The slot number.
  /// - Returns: `nil` unless the number is from 1 through 256.
  public init?(rawValue: Int) {

    guard (1...256).contains(rawValue) else {

      return nil

    }

    self.rawValue = rawValue

  }

  /// Creates a slot from its page and its index on the page.
  ///
  /// - Parameters:
  ///   - page: The page, from 1 through 16.
  ///   - index: The index on the page, from 1 through 16.
  /// - Returns: `nil` unless both are from 1 through 16.
  public init?(page: Int, index: Int) {

    guard (1...16).contains(page), (1...16).contains(index) else {

      return nil

    }

    self.init(rawValue: (page - 1) * 16 + index)

  }

  /// The page the slot is on, from 1 through 16.
  public var page: Int { (rawValue - 1) / 16 + 1 }

  /// The slot's index on its page, from 1 through 16.
  public var index: Int { (rawValue - 1) % 16 + 1 }

  /// Orders slots by number.
  public static func < (lhs: HubSlot, rhs: HubSlot) -> Bool {

    lhs.rawValue < rhs.rawValue

  }

}

/// What a 2242 Hub reports about a slot's state.
public struct HubSlotFlags: OptionSet, Hashable, Sendable {

  /// The slot is the active one for its device and group.
  public static let active = HubSlotFlags(rawValue: 0x01)

  /// The slot's device or scene was last turned on.
  public static let on = HubSlotFlags(rawValue: 0x02)

  /// The slot's device or scene was last turned off.
  public static let off = HubSlotFlags(rawValue: 0x04)

  /// The slot is in use.
  public static let used = HubSlotFlags(rawValue: 0x10)

  /// The slot raises an alert.
  public static let alert = HubSlotFlags(rawValue: 0x20)

  /// The flags as the Hub reports them.
  public let rawValue: UInt8

  /// Creates flags from the Hub's byte.
  ///
  /// - Parameter rawValue: The byte.
  public init(rawValue: UInt8) {

    self.rawValue = rawValue

  }

}

/// A slot's device and group, and its state, as a 2242 Hub reports them.
public struct HubSlotStatus: Hashable, Sendable {

  /// The slot.
  public var slot: HubSlot

  /// The device the slot is for, or `00.00.00` if none.
  public var device: InsteonAddress

  /// The group the slot is for.
  public var group: AllLinkGroupNumber

  /// The slot's state.
  public var flags: HubSlotFlags

  /// Creates a slot status.
  ///
  /// - Parameters:
  ///   - slot: The slot.
  ///   - device: The device the slot is for.
  ///   - group: The group the slot is for.
  ///   - flags: The slot's state.
  public init(slot: HubSlot, device: InsteonAddress, group: AllLinkGroupNumber, flags: HubSlotFlags) {

    self.slot = slot
    self.device = device
    self.group = group
    self.flags = flags

  }

  /// Parses one page of slot statuses from the Hub's `b.xml` response.
  ///
  /// The page lists each slot as two `S` elements: one whose `D` attribute is the device and
  /// group, such as `1A.DC.49.01`, then one whose `D` attribute is the flags in hex.
  ///
  /// - Parameters:
  ///   - response: The response body as text.
  ///   - page: The page that was read, from 1 through 16.
  /// - Returns: The page's slots, in order.
  /// - Throws: ``HubError/malformedSlotPage`` if the response isn't in that form.
  static func page(_ response: String, page: Int) throws(HubError) -> [HubSlotStatus] {

    let values = attributeValues(in: response)

    guard values.count.isMultiple(of: 2), values.count <= 32 else {

      throw .malformedSlotPage

    }

    var statuses: [HubSlotStatus] = []

    for (offset, pair) in stride(from: 0, to: values.count, by: 2).map({ (values[$0], values[$0 + 1]) }).enumerated() {

      let bytes = pair.0.split(separator: ".", omittingEmptySubsequences: false).compactMap { UInt8($0, radix: 16) }

      guard
        bytes.count == 4,
        pair.0.count == 11,
        pair.1.count <= 2,
        let flags = UInt8(pair.1, radix: 16),
        let slot = HubSlot(page: page, index: offset + 1)
      else {

        throw .malformedSlotPage

      }

      statuses.append(HubSlotStatus(
        slot: slot,
        device: InsteonAddress(bytes[0], bytes[1], bytes[2]),
        group: AllLinkGroupNumber(rawValue: bytes[3]),
        flags: HubSlotFlags(rawValue: flags)
      ))

    }

    return statuses

  }

  /// The `D` attribute of each `S` element, in order.
  private static func attributeValues(in response: String) -> [String] {

    var values: [String] = []
    var rest = response[...]

    while let element = rest.range(of: "<S ") {

      rest = rest[element.upperBound...]

      guard let start = rest.range(of: "D=\""), let end = rest.range(of: "\"", range: start.upperBound..<rest.endIndex) else {

        break

      }

      values.append(String(rest[start.upperBound..<end.lowerBound]))
      rest = rest[end.upperBound...]

    }

    return values

  }

}
