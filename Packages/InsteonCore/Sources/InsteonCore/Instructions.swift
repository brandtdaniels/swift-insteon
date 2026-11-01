import InsteonDeviceCatalog

/// Steps for a person to follow on a device, such as to link it or restore its factory
/// settings, as the Insteon device catalog gives them.
public struct Instructions: Hashable, Sendable {

  /// The steps, in order.
  public var steps: [InstructionStep]

  /// Notes on the steps, such as what to do when a step doesn't work.
  public var notes: [String]

  /// Creates instructions.
  ///
  /// - Parameters:
  ///   - steps: The steps, in order.
  ///   - notes: Notes on the steps. Defaults to none.
  public init(steps: [InstructionStep], notes: [String] = []) {

    self.steps = steps
    self.notes = notes

  }

  /// The instructions a catalog procedure gives.
  init(_ procedure: DeviceLifecycle.Procedure) {

    self.init(steps: procedure.steps.map { (step: DeviceLifecycle.Step) -> InstructionStep in InstructionStep(step) }, notes: procedure.notes)

  }

}

/// A step for a person to do, with what the device does in answer.
public struct InstructionStep: Hashable, Sendable {

  /// What to do, such as `"Press and hold the SET button."`.
  public var text: String

  /// What the device does in answer, such as `"LED blinks green"`, or `nil` if the catalog
  /// doesn't say.
  public var expectation: String?

  /// Whether the step is done on another device, such as the Hub or a controller, rather than
  /// on the device itself.
  public var isOnOtherDevice: Bool

  /// Creates a step.
  ///
  /// - Parameters:
  ///   - text: What to do.
  ///   - expectation: What the device does in answer. Defaults to `nil`.
  ///   - isOnOtherDevice: Whether the step is done on another device. Defaults to `false`.
  public init(text: String, expectation: String? = nil, isOnOtherDevice: Bool = false) {

    self.text = text
    self.expectation = expectation
    self.isOnOtherDevice = isOnOtherDevice

  }

  /// The step a catalog procedure gives.
  init(_ step: DeviceLifecycle.Step) {

    self.init(text: step.text, expectation: step.expectation, isOnOtherDevice: step.isOnOtherDevice)

  }

}

/// Something a device's factory reset erases, as the Insteon device catalog gives it.
public enum ResetErasure: String, Hashable, Sendable, CaseIterable {

  /// The device's ALL-Link database.
  case links

  /// The device's settings.
  case settings

  /// What the catalog's erasure names.
  init(_ erasure: DeviceLifecycle.Erasure) {

    switch erasure {
    case .links:
      self = .links
    case .settings:
      self = .settings
    }

  }

}
