/// How to install a product, link it, wake it, reset it and take it out of service, for an app
/// that guides people through it or does the steps itself.
///
/// Each part is a ``DeviceLifecycle/Procedure``: steps in order, with other ways to do the
/// same thing as alternatives. Links are made between a controller and a responder; the device
/// that goes into linking mode first is the controller.
///
/// ```swift
/// guard let linking = profile.lifecycle?.linking else {
///   return
/// }
///
/// for step in linking.steps {
///   print(step.text, step.expectation ?? "")
/// }
///
/// // Another way, such as from software instead of with the SET button.
/// if let fromHub = linking.alternatives.first(where: { $0.steps.contains { $0.action == .send } }) {
///   print(fromHub.summary ?? "")
/// }
/// ```
public struct DeviceLifecycle: Hashable, Sendable {

  /// What a factory reset erases.
  public enum Erasure: String, Hashable, Sendable {

    /// The device's ALL-Link database.
    case links

    /// The device's settings, such as its on-level and ramp rate.
    case settings

  }

  /// Steps in order, other ways to do the same thing, and how sure the catalog is of them.
  public struct Procedure: Hashable, Sendable {

    /// What this way of doing it is, for an alternative, such as `"From a Hub"`. The
    /// catalog's JSON calls it `description`.
    public var summary: String?

    /// The steps, in order.
    public var steps: [Step]

    /// What's worth knowing that no step says, such as what the procedure needs.
    public var notes: [String]

    /// How sure the catalog is of the procedure.
    public var verification: Verification

    /// Other ways to do the same thing, such as from software instead of with the SET
    /// button. Each is a whole procedure; an app follows one.
    public var alternatives: [Procedure]

    /// Creates a procedure.
    ///
    /// - Parameters:
    ///   - summary: What this way of doing it is.
    ///   - steps: The steps, in order.
    ///   - notes: What's worth knowing that no step says.
    ///   - verification: How sure the catalog is of the procedure. Defaults to ``Verification/documented``.
    ///   - alternatives: Other ways to do the same thing.
    public init(summary: String? = nil, steps: [Step], notes: [String] = [], verification: Verification = .documented, alternatives: [Procedure] = []) {

      self.summary = summary
      self.steps = steps
      self.notes = notes
      self.verification = verification
      self.alternatives = alternatives

    }

  }

  /// One step a person or an app takes: what to do, to which control, for how long or how many
  /// times, and what the device does in answer.
  public struct Step: Hashable, Sendable {

    /// What a step does, for an app that guides it or does it itself.
    public struct Action: RawRepresentable, Hashable, Sendable, CustomStringConvertible {

      /// The action as the catalog writes it, such as `"hold"`.
      public let rawValue: String

      /// Creates an action from the catalog's name for it.
      ///
      /// - Parameter rawValue: The action as the catalog writes it.
      public init(rawValue: String) {

        self.rawValue = rawValue

      }

      /// Hold a control down, for ``DeviceLifecycle/Step/duration`` if the step gives one.
      public static let hold = Action(rawValue: "hold")

      /// Tap a control, ``DeviceLifecycle/Step/count`` times if the step gives a count.
      public static let tap = Action(rawValue: "tap")

      /// Press a control.
      public static let press = Action(rawValue: "press")

      /// Let go of a control.
      public static let release = Action(rawValue: "release")

      /// Turn a control, such as a dial.
      public static let turn = Action(rawValue: "turn")

      /// Plug the device in.
      public static let plugIn = Action(rawValue: "plugIn")

      /// Unplug the device.
      public static let unplug = Action(rawValue: "unplug")

      /// Turn off the device's power, such as at the circuit breaker.
      public static let powerOff = Action(rawValue: "powerOff")

      /// Turn the device's power back on.
      public static let powerOn = Action(rawValue: "powerOn")

      /// Connect the device's wires.
      public static let wire = Action(rawValue: "wire")

      /// Mount the device, or put its cover back.
      public static let mount = Action(rawValue: "mount")

      /// Put the batteries in.
      public static let insertBatteries = Action(rawValue: "insertBatteries")

      /// Take the batteries out.
      public static let removeBatteries = Action(rawValue: "removeBatteries")

      /// Pull a tab or control out, such as an air gap or a battery tab.
      public static let pullTab = Action(rawValue: "pullTab")

      /// Wait, for ``DeviceLifecycle/Step/duration`` if the step gives one.
      public static let wait = Action(rawValue: "wait")

      /// Send the Insteon command ``DeviceLifecycle/Step/command`` names, which an app can do
      /// itself.
      public static let send = Action(rawValue: "send")

      /// Something else, which ``DeviceLifecycle/Step/text`` describes.
      public static let other = Action(rawValue: "other")

      /// The action as the catalog writes it.
      public var description: String { rawValue }

    }

    /// The step as a person reads it, in the owner's manual's words where it has them.
    public var text: String

    /// Whether the step is done on the other device being linked or unlinked, such as a Hub,
    /// rather than on this one.
    public var isOnOtherDevice: Bool

    /// What the step does, or `nil` if the catalog doesn't say. An action from a later version
    /// of the catalog keeps its name.
    public var action: Action?

    /// The button or part the step uses, as the device labels it, such as `"SET button"`.
    public var control: String?

    /// How long to hold, wait or keep going.
    public var duration: Duration?

    /// How many times to tap or press.
    public var count: Int?

    /// What the device does when the step works, such as a beep or its LED blinking. The
    /// catalog's JSON calls it `expect`.
    public var expectation: String?

    /// For a step an app sends, the Insteon command by the name the Insteon Developer's Guide
    /// gives it, such as `"Enter Linking Mode"`.
    public var command: String?

    /// Creates a step.
    ///
    /// - Parameters:
    ///   - text: The step as a person reads it.
    ///   - isOnOtherDevice: Whether the step is done on the other device. Defaults to `false`.
    ///   - action: What the step does.
    ///   - control: The button or part the step uses.
    ///   - duration: How long to hold, wait or keep going.
    ///   - count: How many times to tap or press.
    ///   - expectation: What the device does when the step works.
    ///   - command: The Insteon command an app sends.
    public init(
      text: String,
      isOnOtherDevice: Bool = false,
      action: Action? = nil,
      control: String? = nil,
      duration: Duration? = nil,
      count: Int? = nil,
      expectation: String? = nil,
      command: String? = nil
    ) {

      self.text = text
      self.isOnOtherDevice = isOnOtherDevice
      self.action = action
      self.control = control
      self.duration = duration
      self.count = count
      self.expectation = expectation
      self.command = command

    }

  }

  /// Installing the product, such as wiring a switch or plugging in a module.
  public var installation: Procedure?

  /// Putting the device in linking mode, as a controller or a responder.
  public var linking: Procedure?

  /// How long the device stays in linking mode if nothing links.
  public var linkingTimeout: Duration?

  /// Linking the product to a Hub or modem, as data an app can follow on its own, or `nil` if
  /// the catalog doesn't give it.
  public var fromHub: HubLinking?

  /// Linking several devices in one session.
  public var multiLinking: Procedure?

  /// Putting the device in unlinking mode.
  public var unlinking: Procedure?

  /// Waking a battery-powered device so it can be programmed.
  public var waking: Procedure?

  /// How long a woken device stays awake.
  public var awakeDuration: Duration?

  /// Restoring the factory settings.
  public var reset: Procedure?

  /// What a factory reset erases, if the catalog says.
  public var resetErases: Set<Erasure>

  /// Taking the product out of service, such as unlinking it everywhere and uninstalling it.
  public var removal: Procedure?

  /// Creates a lifecycle.
  ///
  /// - Parameters:
  ///   - installation: Installing the product.
  ///   - linking: Putting the device in linking mode.
  ///   - linkingTimeout: How long the device stays in linking mode.
  ///   - multiLinking: Linking several devices in one session.
  ///   - unlinking: Putting the device in unlinking mode.
  ///   - waking: Waking a battery-powered device.
  ///   - awakeDuration: How long a woken device stays awake.
  ///   - reset: Restoring the factory settings.
  ///   - resetErases: What a factory reset erases.
  ///   - removal: Taking the product out of service.
  ///   - fromHub: Linking the product to a Hub, as data. Defaults to `nil`.
  public init(
    installation: Procedure? = nil,
    linking: Procedure? = nil,
    linkingTimeout: Duration? = nil,
    multiLinking: Procedure? = nil,
    unlinking: Procedure? = nil,
    waking: Procedure? = nil,
    awakeDuration: Duration? = nil,
    reset: Procedure? = nil,
    resetErases: Set<Erasure> = [],
    removal: Procedure? = nil,
    fromHub: HubLinking? = nil
  ) {

    self.installation = installation
    self.linking = linking
    self.linkingTimeout = linkingTimeout
    self.multiLinking = multiLinking
    self.unlinking = unlinking
    self.waking = waking
    self.awakeDuration = awakeDuration
    self.reset = reset
    self.resetErases = resetErases
    self.removal = removal
    self.fromHub = fromHub

  }

}

// MARK: - Decodable

extension DeviceLifecycle: Decodable {

  private enum CodingKeys: String, CodingKey {

    case installation
    case linking
    case linkingTimeoutSeconds
    case multiLinking
    case unlinking
    case waking
    case awakeSeconds
    case reset
    case resetErases
    case removal
    case fromHub

  }

  /// Decodes a lifecycle from a profile's `lifecycle`.
  ///
  /// What a reset erases from a later version of the catalog is passed over.
  ///
  /// - Parameter decoder: The decoder to read from.
  /// - Throws: `DecodingError` if the JSON isn't a lifecycle, or a number of seconds is
  ///   negative or longer than a year.
  public init(from decoder: any Decoder) throws {

    let container = try decoder.container(keyedBy: CodingKeys.self)

    self.init(
      installation: try container.decodeIfPresent(Procedure.self, forKey: .installation),
      linking: try container.decodeIfPresent(Procedure.self, forKey: .linking),
      linkingTimeout: try container.decodeSecondsIfPresent(forKey: .linkingTimeoutSeconds),
      multiLinking: try container.decodeIfPresent(Procedure.self, forKey: .multiLinking),
      unlinking: try container.decodeIfPresent(Procedure.self, forKey: .unlinking),
      waking: try container.decodeIfPresent(Procedure.self, forKey: .waking),
      awakeDuration: try container.decodeSecondsIfPresent(forKey: .awakeSeconds),
      reset: try container.decodeIfPresent(Procedure.self, forKey: .reset),
      resetErases: Set((try container.decodeIfPresent([String].self, forKey: .resetErases) ?? []).compactMap(Erasure.init(rawValue:))),
      removal: try container.decodeIfPresent(Procedure.self, forKey: .removal),
      fromHub: try container.decodeIfPresent(HubLinking.self, forKey: .fromHub)
    )

  }

}

extension DeviceLifecycle.Procedure: Decodable {

  private enum CodingKeys: String, CodingKey {

    case summary = "description"
    case steps
    case notes
    case verification
    case alternatives

  }

  /// Decodes a procedure from a profile's `lifecycle`.
  ///
  /// - Parameter decoder: The decoder to read from.
  /// - Throws: `DecodingError` if the JSON isn't a procedure.
  public init(from decoder: any Decoder) throws {

    let container = try decoder.container(keyedBy: CodingKeys.self)

    self.init(
      summary: try container.decodeIfPresent(String.self, forKey: .summary),
      steps: try container.decode([DeviceLifecycle.Step].self, forKey: .steps),
      notes: try container.decodeIfPresent([String].self, forKey: .notes) ?? [],
      verification: try container.decodeIfPresent(Verification.self, forKey: .verification) ?? .documented,
      alternatives: try container.decodeIfPresent([DeviceLifecycle.Procedure].self, forKey: .alternatives) ?? []
    )

  }

}

extension DeviceLifecycle.Step: Decodable {

  private enum CodingKeys: String, CodingKey {

    case text
    case device
    case action
    case control
    case seconds
    case count
    case expect
    case command

  }

  /// Decodes a step from a profile's `lifecycle`.
  ///
  /// A step is on the other device only when its `device` is `"other"`; any other value,
  /// including one from a later version of the catalog, reads as this device.
  ///
  /// - Parameter decoder: The decoder to read from.
  /// - Throws: `DecodingError` if the JSON isn't a step, or its seconds are negative or longer
  ///   than a year.
  public init(from decoder: any Decoder) throws {

    let container = try decoder.container(keyedBy: CodingKeys.self)

    self.init(
      text: try container.decode(String.self, forKey: .text),
      isOnOtherDevice: try container.decodeIfPresent(String.self, forKey: .device) == "other",
      action: try container.decodeIfPresent(String.self, forKey: .action).map(Action.init(rawValue:)),
      control: try container.decodeIfPresent(String.self, forKey: .control),
      duration: try container.decodeSecondsIfPresent(forKey: .seconds),
      count: try container.decodeIfPresent(Int.self, forKey: .count),
      expectation: try container.decodeIfPresent(String.self, forKey: .expect),
      command: try container.decodeIfPresent(String.self, forKey: .command)
    )

  }

}

extension KeyedDecodingContainer {

  /// The longest duration the catalog gives in seconds: a year.
  private static var longestSeconds: Double { 366 * 24 * 60 * 60 }

  /// Decodes a number of seconds as a duration, refusing one too long for a `Duration` to
  /// hold safely.
  ///
  /// - Parameter key: The key the seconds are under.
  /// - Returns: The duration, or `nil` if there's no value for the key.
  /// - Throws: `DecodingError` if the value isn't a number from 0 through a year.
  func decodeSecondsIfPresent(forKey key: Key) throws -> Duration? {

    guard let seconds = try decodeIfPresent(Double.self, forKey: key) else {

      return nil

    }

    guard seconds >= 0, seconds <= Self.longestSeconds else {

      throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "\(seconds) seconds isn't from 0 through a year.")

    }

    return .seconds(seconds)

  }

}
