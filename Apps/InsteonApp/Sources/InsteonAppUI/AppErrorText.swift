import InsteonCore
import InsteonService

/// What a screen says about an error from the network, in words for a person.
enum AppErrorText {

  /// The words for an error that a network call can throw.
  static func message(for error: any Error) -> String {
    if let message = InsteonErrorDescription.message(for: error) { return message }
    switch error as? ServiceControlError {
    case .busy?: return "The service is busy with another request. Try again."
    case .modemUnavailable?: return "The service can't reach its modem right now."
    case .notLinked?: return "That device isn't linked to the modem."
    case .notIdentified?: return "That device hasn't said what it is yet."
    case .unsupportedControl?: return "That device has no on and off control."
    case .invalidLevel?: return "That level isn't one the device can take."
    case .unknownDevice?: return "The service doesn't know that device."
    case .databasesUnavailable?: return "This network doesn't give out its ALL-Link databases."
    case .unknownScene?: return "The service holds no such scene."
    case .sceneEmpty?: return "That scene has no members."
    case .unknownPlan?, .planExpired?: return "That plan is gone. Plan again."
    case .planAlreadyApplied?: return "That plan was used. Plan again."
    case .deviceNotAnswering?: return "A device didn't answer, and nothing was written. Try again."
    case .planNotApplicable?: return "That plan can't be applied."
    case .planStale?: return "A database differs from what the plan was made from. Refresh the scenes and plan again."
    case .consentRequired?, .consentMismatch?: return "Writing records needs consent that names the plan."
    case nil: return "The service couldn't be reached."
    }
  }
}
