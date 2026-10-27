/// A use of one of the modem's buttons, reported in a ``ModemReply/buttonEvent(_:)`` reply.
///
/// Every modem has a SET button, and some have a second and third button. The event code's
/// high nibble identifies the button and its low nibble the action.
///
/// Holding the SET button for more than three seconds also starts ALL-Linking, unless
/// ``ModemConfiguration/disableAutomaticLinking`` is set.
public struct ModemButtonEvent: RawRepresentable, Hashable, Sendable {

  /// A button on the modem.
  public enum Button: UInt8, CaseIterable, Hashable, Sendable {

    /// The SET button (`0x0_`).
    case set = 0x00

    /// The second button, on modems that have one (`0x1_`).
    case button2 = 0x10

    /// The third button, on modems that have one (`0x2_`).
    case button3 = 0x20

  }

  /// What was done with a button.
  public enum Action: UInt8, CaseIterable, Hashable, Sendable {

    /// The button was tapped (`0x_2`).
    case tapped = 0x02

    /// The button was held for more than three seconds (`0x_3`).
    case held = 0x03

    /// The button was released after being held (`0x_4`).
    case released = 0x04

  }

  /// The event code the modem sent.
  public var rawValue: UInt8

  /// Creates an event from the code the modem sent.
  ///
  /// - Parameter rawValue: The event code.
  public init(rawValue: UInt8) {

    self.rawValue = rawValue

  }

  /// Creates an event for a button and action.
  ///
  /// - Parameters:
  ///   - button: The button used.
  ///   - action: What was done with it.
  public init(button: Button, action: Action) {

    self.rawValue = button.rawValue | action.rawValue

  }

  /// The button used, or `nil` if the code names a button this type doesn't know.
  public var button: Button? {

    Button(rawValue: rawValue & 0xF0)

  }

  /// What was done with the button, or `nil` if the code names an action this type doesn't
  /// know.
  public var action: Action? {

    Action(rawValue: rawValue & 0x0F)

  }

}
