/// A button on a keypad, numbered from 1 as Insteon's command workbooks number them.
///
/// On an 8-button keypad, buttons run two to a row from the top: 1 is the main on button, 2 is
/// beside it, then 3 and 4, 5 and 6, and 7 and 8. A dimmer, switch or outlet has one button,
/// button 1. Insteon's workbooks don't give the 6-button keypad's numbering.
public struct KeypadButton: RawRepresentable, Hashable, Sendable, Comparable {

  /// The main button, and the only one on a dimmer, switch or outlet.
  public static let main = KeypadButton(rawValue: 1)!

  /// The button's number, from 1 to 8.
  public let rawValue: UInt8

  /// Creates a button from its number.
  ///
  /// - Parameter rawValue: The button's number, from 1 to 8.
  /// - Returns: `nil` if the number is outside 1 to 8.
  public init?(rawValue: UInt8) {

    guard (1...8).contains(rawValue) else {

      return nil

    }

    self.rawValue = rawValue

  }

  /// Whether one button comes before another.
  ///
  /// - Parameters:
  ///   - lhs: A button.
  ///   - rhs: Another button.
  /// - Returns: `true` if `lhs` has the lower number.
  public static func < (lhs: KeypadButton, rhs: KeypadButton) -> Bool {

    lhs.rawValue < rhs.rawValue

  }

}

/// A set of keypad buttons, as a bitmask with button 1 in bit 0 and button 8 in bit 7.
///
/// Keypad settings that apply to several buttons, such as which LEDs are lit or which buttons
/// turn others off, use this mask. A status request with variant `0x01` returns the lit LEDs
/// as one in the acknowledgement's cmd2:
///
/// ```swift
/// let ack = try await modem.request(StandardMessage(to: keypad, command: StandardDirectCommand.statusRequest(variant: 0x01)))
/// let lit = KeypadButtonSet(rawValue: ack.command.command2)
/// ```
public struct KeypadButtonSet: OptionSet, Hashable, Sendable {

  /// The mask, with button 1 in bit 0.
  public var rawValue: UInt8

  /// Creates a set from its mask.
  ///
  /// - Parameter rawValue: The mask, with button 1 in bit 0.
  public init(rawValue: UInt8) {

    self.rawValue = rawValue

  }

  /// Creates a set of buttons.
  ///
  /// - Parameter buttons: The buttons.
  public init(_ buttons: some Sequence<KeypadButton>) {

    self.init(rawValue: buttons.reduce(0) { $0 | 1 << ($1.rawValue - 1) })

  }

  /// The buttons in the set, in order.
  public var buttons: [KeypadButton] {

    (1...8).compactMap { number in

      rawValue & 1 << (number - 1) == 0 ? nil : KeypadButton(rawValue: number)

    }

  }

  /// Whether the set includes a button.
  ///
  /// - Parameter button: The button.
  /// - Returns: `true` if the button's bit is set.
  public func contains(_ button: KeypadButton) -> Bool {

    rawValue & 1 << (button.rawValue - 1) != 0

  }

}
