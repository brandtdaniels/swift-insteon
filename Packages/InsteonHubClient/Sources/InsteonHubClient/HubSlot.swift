import InsteonProtocol

/// One of the 256 slots in which a Hub 2242 keeps a scene or device it runs timers for.
///
/// The Hub arranges its slots as 16 pages of 16, and numbers them from 1: slot `n` is index
/// `(n - 1) % 16 + 1` on page `(n - 1) / 16 + 1`. Each page is one of the Hub's rooms. Timers go
/// in slots 1 through 239, the ones Insteon's Hub app used: slot 240 holds the Hub's unlock code,
/// and the last page is the thermostat room, which the app kept disabled.
public struct HubSlot: RawRepresentable, Hashable, Sendable, Comparable {

  /// The slot that holds the Hub's unlock code.
  public static let unlockCode = HubSlot(rawValue: 240)!

  /// The slots that hold timers: 1 through 239.
  public static let timerSlots = 1...239

  /// Whether the slot can hold a timer.
  public var holdsTimers: Bool { Self.timerSlots.contains(rawValue) }

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

/// What a Hub 2242 reports about a slot's state.
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

/// A slot's device and group, and its state, as a Hub 2242 reports them.
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
  /// The page lists `S` elements whose `D` attributes are either a slot's device and group,
  /// such as `1A.DC.49.01`, or a slot's flags in hex. As Insteon's Hub app reads the page, the
  /// first device and group goes with the first flags, and so on, in slot order.
  ///
  /// - Parameters:
  ///   - response: The response body as text.
  ///   - page: The page that was read, from 1 through 16.
  /// - Returns: The page's slots, in order.
  /// - Throws: ``HubError/malformedSlotPage`` if the response isn't in that form.
  static func page(_ response: String, page: Int) throws(HubError) -> [HubSlotStatus] {

    let values = attributeValues(in: response)
    let targets = values.filter { $0.count > 2 }
    let flags = values.filter { $0.count <= 2 }

    guard targets.count == flags.count, targets.count <= 16 else {

      throw .malformedSlotPage

    }

    var statuses: [HubSlotStatus] = []

    for (offset, (target, flag)) in zip(targets, flags).enumerated() {

      let bytes = target.split(separator: ".", omittingEmptySubsequences: false).compactMap { UInt8($0, radix: 16) }

      guard
        bytes.count == 4,
        target.count == 11,
        let flags = UInt8(flag, radix: 16),
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

  /// The `D` attribute of each `S` element, in order, in either kind of quotes.
  private static func attributeValues(in response: String) -> [String] {

    var values: [String] = []
    var rest = response[...]

    while let element = rest.range(of: "<S ") {

      rest = rest[element.upperBound...]

      guard let name = rest.range(of: "D="), let quote = rest[name.upperBound...].first, quote == "\"" || quote == "'" else {

        break

      }

      let start = rest.index(after: name.upperBound)

      guard let end = rest[start...].firstIndex(of: quote) else {

        break

      }

      values.append(String(rest[start..<end]))
      rest = rest[rest.index(after: end)...]

    }

    return values

  }

}
