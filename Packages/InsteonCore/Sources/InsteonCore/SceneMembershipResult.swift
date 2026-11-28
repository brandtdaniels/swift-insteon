import Foundation
import InsteonLinking
import InsteonProtocol

/// Why applying a ``SceneMembershipPlan`` wrote nothing. Each is thrown before any record is
/// written.
public enum SceneMembershipRefusal: Error, Hashable, Sendable {

  /// The plan has a refusal or no steps, so there is nothing it may write.
  case notApplicable

  /// The consent doesn't agree to the writes.
  case consentRequired

  /// The consent agrees to the writes and names another plan than the one given.
  case consentMismatch

  /// A database changed since the plan was made: a device's, or the modem's for `nil`.
  case planStale(InsteonAddress?)

  /// A step would write a record into a slot of the device's database that holds a record in use, or clear a
  /// slot that holds none. A plan from ``SceneMembershipPlanner`` never does, so the plan was changed after
  /// it was made.
  case wouldOverwriteRecord(InsteonAddress)

  /// A device didn't answer the read of the first step's slot, so nothing was written. A device that stops
  /// answering after a step was written is the cause inside ``SceneMembershipInterrupted`` instead.
  case deviceNotAnswering(InsteonAddress)

}

extension SceneMembershipRefusal: CustomStringConvertible, LocalizedError {

  /// A one-line explanation of the refusal.
  public var description: String {

    switch self {
    case .notApplicable:
      "The plan has a refusal or no steps, so it can't be applied. Nothing was written."
    case .consentRequired:
      "Writing ALL-Link records needs consent that agrees to the writes. Nothing was written."
    case .consentMismatch:
      "The consent names another plan than the one that was shown. Nothing was written."
    case let .deviceNotAnswering(device):
      "\(device) didn't answer the read of the slot the first step writes. Nothing was written; try again."
    case let .wouldOverwriteRecord(device):
      "A step of the plan would write over a record in use in \(device)'s ALL-Link database. Nothing was written."
    case let .planStale(device):
      "\(device.map { "\($0)'s ALL-Link database" } ?? "The modem's ALL-Link database") changed since the plan was made. Nothing was written; plan again."
    }

  }

  /// The same text as the refusal's `description`, for `localizedDescription`.
  public var errorDescription: String? {

    description

  }

}

/// What ``DeviceLinkingCoordinator/apply(_:consent:)->SceneMembershipResult`` did for a ``SceneMembershipPlan``: each step's
/// outcome, and what reading the modem's database and each device's again found.
public struct SceneMembershipResult: Hashable, Sendable {

  /// One step and its outcome.
  public struct StepResult: Hashable, Sendable {

    /// The step.
    public var step: SceneMembershipStep

    /// What became of it.
    public var outcome: DatabaseLinkStepOutcome

    /// Creates a step's result.
    public init(step: SceneMembershipStep, outcome: DatabaseLinkStepOutcome) {

      self.step = step
      self.outcome = outcome

    }

  }

  /// A record that isn't as expected after the steps that were made.
  public struct Mismatch: Hashable, Sendable {

    /// The device whose database holds the record, or `nil` for the modem's.
    public var device: InsteonAddress?

    /// The record expected and the one found.
    public var mismatch: DatabaseMismatch

    /// Creates a mismatch.
    public init(device: InsteonAddress?, mismatch: DatabaseMismatch) {

      self.device = device
      self.mismatch = mismatch

    }

  }

  /// The plan carried out.
  public var plan: SceneMembershipPlan

  /// Each step, in order, with its outcome.
  public var steps: [StepResult]

  /// The records not as expected after the steps that were made.
  public var mismatches: [Mismatch]

  /// What reading each device's database again found, for each device the plan wrote to.
  public var deviceChecks: [InsteonAddress: DatabaseLinkResult.DeviceCheck]

  /// Whether the modem's database was read again and compared.
  public var isModemChecked: Bool

  /// What reading the databases the steps changed into the network's copies found, or `nil` when no step was tried and
  /// so nothing was forgotten.
  public var cacheReload: SceneMembershipCacheReload?

  /// The steps made: those whose record read back as written, or that can't be read back only
  /// because they removed a device's last record of the modem.
  public var madeSteps: [SceneMembershipStep] {

    steps.filter(\.outcome.isDone).map(\.step)

  }

  /// The steps that weren't made, in order, whether they failed or weren't reached.
  public var unmadeSteps: [SceneMembershipStep] {

    steps.filter { (result: StepResult) -> Bool in !result.outcome.isDone }.map(\.step)

  }

  /// Whether every step was made and every database read back as expected.
  public var isComplete: Bool {

    steps.allSatisfy(\.outcome.isDone) && mismatches.isEmpty && isModemChecked && !deviceChecks.values.contains(.unanswered)

  }

  /// The devices a step was tried for, each once: the ones whose databases a step wrote to, and the ones a record
  /// of the modem's names. The network forgets its copies of their databases and the modem's, and reads them again.
  public var changedDevices: [InsteonAddress] {

    var devices: [InsteonAddress] = []

    for result in steps where result.outcome != .notReached {

      let address: InsteonAddress

      if case let .device(device) = result.step.endpoint {

        address = device

      } else {

        address = result.step.record.address

      }

      if !devices.contains(address) {

        devices.append(address)

      }

    }

    return devices

  }

  /// Creates a result.
  public init(plan: SceneMembershipPlan, steps: [StepResult], mismatches: [Mismatch], deviceChecks: [InsteonAddress: DatabaseLinkResult.DeviceCheck], isModemChecked: Bool, cacheReload: SceneMembershipCacheReload? = nil) {

    self.cacheReload = cacheReload

    self.plan = plan
    self.steps = steps
    self.mismatches = mismatches
    self.deviceChecks = deviceChecks
    self.isModemChecked = isModemChecked

  }

}

/// Whether the network's copies of the databases a plan changed were read again afterward.
public struct SceneMembershipCacheReload: Hashable, Sendable {

  /// Whether the modem's database was read again.
  public var isModemReloaded: Bool

  /// The devices whose databases couldn't be read again, though they were expected to be readable.
  public var unreadDevices: [InsteonAddress]

  /// The devices that reject the modem once their last record of it is gone, so their databases aren't read again.
  /// Expected after a removal that drops it (``SceneMembershipStep/Risk/rejectsModemOnceUnlinked``).
  public var expectedUnreadable: [InsteonAddress]

  /// Whether every database that can be read was: the modem's and each device's, except the expected ones.
  public var isReloaded: Bool {

    isModemReloaded && unreadDevices.isEmpty

  }

  /// Creates a reload.
  public init(isModemReloaded: Bool, unreadDevices: [InsteonAddress] = [], expectedUnreadable: [InsteonAddress] = []) {

    self.isModemReloaded = isModemReloaded
    self.unreadDevices = unreadDevices
    self.expectedUnreadable = expectedUnreadable

  }

}

/// The steps of a ``SceneMembershipPlan`` stopped after some were made, for something other than a step's own
/// failure: the modem's error, a device that didn't answer the read of the slot of a later step (the device's own
/// timeout or rejection is the cause), a slot that changed (``SceneMembershipSlotChanged``), or `CancellationError`.
///
/// ``result`` says which steps were made, so a front end can say which records were written, and carries what reading
/// the databases again found, which runs even when the request is canceled. A plan stopped before its first step
/// is a ``SceneMembershipRefusal`` instead, or a `CancellationError`.
public struct SceneMembershipInterrupted: Error, Sendable {

  /// Each step's outcome, and what reading the databases again found when they could be read.
  public let result: SceneMembershipResult

  /// What stopped the steps.
  public let cause: any Error

  /// Creates the error.
  public init(result: SceneMembershipResult, cause: any Error) {

    self.result = result
    self.cause = cause

  }

}

extension SceneMembershipInterrupted: CustomStringConvertible, LocalizedError {

  /// A one-line explanation that says what was written.
  public var description: String {

    "Applying the plan stopped after \(result.madeSteps.count) of \(result.steps.count) steps were made: \(InsteonErrorDescription.message(for: cause) ?? "\(cause)")"

  }

  /// The same text as the error's `description`, for `localizedDescription`.
  public var errorDescription: String? {

    description

  }

}

/// A slot of a device's database changed after some steps were written, so the step for it and the steps after it
/// weren't made. Thrown inside ``SceneMembershipInterrupted`` as its cause, since the steps before it stay written.
/// A slot found changed before the first write is ``SceneMembershipRefusal/planStale(_:)`` instead.
public struct SceneMembershipSlotChanged: Error, Hashable, Sendable {

  /// The device whose slot changed.
  public let device: InsteonAddress

  /// How many steps were made before it was found.
  public let made: Int

  /// How many steps the plan has.
  public let total: Int

  /// Creates the error.
  public init(device: InsteonAddress, made: Int, total: Int) {

    self.device = device
    self.made = made
    self.total = total

  }

}

extension SceneMembershipSlotChanged: CustomStringConvertible, LocalizedError {

  /// A one-line explanation that says how many steps were made.
  public var description: String {

    "\(device)'s ALL-Link database changed after \(made) of \(total) steps were made. The step for it and the \(total - made - 1 < 0 ? 0 : total - made - 1) after it were not made, and nothing was undone. Read the databases again and plan again."

  }

  /// The same text as the error's `description`, for `localizedDescription`.
  public var errorDescription: String? {

    description

  }

}
