/// What ``Device/selfTest(_:)`` does beyond reading.
public struct SelfTestOptions: Hashable, Sendable {

  /// Whether to send the device a harmless command it acknowledges, Beep, when its Insteon
  /// device catalog entry lists a Beep that's sent. Nothing else is sent that changes the
  /// device's state.
  public var actuates: Bool

  /// Creates options.
  ///
  /// - Parameter actuates: Whether to send Beep when the catalog lists it. Defaults to `false`,
  ///   so the test only reads.
  public init(actuates: Bool = false) {

    self.actuates = actuates

  }

}

/// How one check of a ``SelfTestReport`` came out.
public enum SelfTestOutcome: String, Hashable, Sendable, CaseIterable {

  /// The device is as it should be.
  case passed

  /// Something is worth a look, but the device works.
  case warning

  /// Something is wrong.
  case failed

  /// The check wasn't run, such as when the device didn't answer or the catalog doesn't
  /// describe it.
  case skipped

}

/// One of the checks ``Device/selfTest(_:)`` runs, in the order it runs them.
public enum SelfTestCheckKind: String, Hashable, Sendable, CaseIterable {

  /// The device answers Get Insteon Engine Version and accepts the modem.
  case answers

  /// The Insteon device catalog describes the identity the device reports to ID Request.
  case catalog

  /// The device reports its state.
  case status

  /// The device's ALL-Link database reads, with every record's checksum intact and the
  /// record that marks its end.
  case linkDatabase

  /// The device and the modem hold both records of each link between them: each link the
  /// catalog gives the device to a Hub, or, without those, a link with the modem as
  /// controller.
  case modemLinks

  /// Every record of the device names the modem or a device the modem is linked to.
  case leftoverRecords

  /// None of the device's operating flags is set that locks its programming or cuts it off
  /// from the modem.
  case operatingFlags

  /// The device acknowledges Beep. Run only when ``SelfTestOptions/actuates`` is `true`.
  case beep

  /// What the check is, in a few words.
  public var title: String {

    switch self {
    case .answers:
      "Answers the modem"
    case .catalog:
      "Insteon device catalog"
    case .status:
      "Reports its state"
    case .linkDatabase:
      "ALL-Link database"
    case .modemLinks:
      "Links with the modem"
    case .leftoverRecords:
      "Leftover records"
    case .operatingFlags:
      "Operating flags"
    case .beep:
      "Beep"
    }

  }

}

/// What may put right a check that didn't pass, from Insteon's troubleshooting steps, most
/// likely first. A front end says how to carry each out.
public enum SelfTestFix: Hashable, Sendable {

  /// Improve the signal between the modem and the device: try another outlet, one on the same
  /// circuit as the modem, or nearer to it; keep the modem and the device off power strips and
  /// filtered outlets; and check that the home's two power phases are bridged, by a dual-band
  /// device on each or a phase coupler.
  case checkSignal

  /// Link the device to the modem again.
  case link

  /// Read the device again, as a record or an answer may have been lost on the way.
  case readAgain

  /// Look over the device's records naming these devices, which the modem isn't linked to,
  /// and remove those that are unwanted.
  case reviewRecords([InsteonAddress])

  /// Turn the device's programming lock off.
  case turnOffProgrammingLock

  /// Get the latest Insteon device catalog, which may describe the device.
  case updateCatalog

  /// As a last resort, reset the device to its factory settings, then link it again.
  case factoryReset

}

/// One check of a ``SelfTestReport``.
public struct SelfTestCheck: Hashable, Sendable {

  /// Which check it is.
  public var kind: SelfTestCheckKind

  /// How it came out.
  public var outcome: SelfTestOutcome

  /// What the check found, as a sentence.
  public var detail: String

  /// What may put it right, most likely first, or none when it passed.
  public var fixes: [SelfTestFix]

  /// Creates a check.
  ///
  /// - Parameters:
  ///   - kind: Which check it is.
  ///   - outcome: How it came out.
  ///   - detail: What the check found.
  ///   - fixes: What may put it right. Defaults to none.
  public init(kind: SelfTestCheckKind, outcome: SelfTestOutcome, detail: String, fixes: [SelfTestFix] = []) {

    self.kind = kind
    self.outcome = outcome
    self.detail = detail
    self.fixes = fixes

  }

  /// The check's title, from its kind.
  public var title: String {

    kind.title

  }

}

/// Something only a person can do to check a device further, which a front end lists once,
/// after the checks, for whoever wants to.
public enum SelfTestChecklistItem: Hashable, Sendable {

  /// Press the device's button for a group it controls the modem with, and see that the
  /// modem hears it.
  case pressButton(group: Int)

  /// Cut the device's power for about ten seconds, by unplugging it or pulling its air gap,
  /// restore it, and see that it answers again and keeps its links and settings.
  case powerCycle

}

/// What ``Device/selfTest(_:)`` found.
public struct SelfTestReport: Hashable, Sendable {

  /// The device.
  public var device: InsteonAddress

  /// The engine the device reported, or `nil` if it didn't answer or reported one this
  /// package doesn't know.
  public var engine: InsteonEngine?

  /// The identity the device reported to ID Request, or `nil` if it reported none.
  public var identity: ReportedIdentity?

  /// The product the Insteon device catalog has for the device, or `nil` if it has none.
  public var productName: String?

  /// The state the device reported, or `nil` if it wasn't read.
  public var status: DeviceStatus?

  /// The checks, in the order they ran.
  public var checks: [SelfTestCheck]

  /// What only a person can do to check the device further.
  public var checklist: [SelfTestChecklistItem]

  /// Creates a report.
  ///
  /// - Parameters:
  ///   - device: The device.
  ///   - engine: The engine the device reported. Defaults to `nil`.
  ///   - identity: The identity the device reported. Defaults to `nil`.
  ///   - productName: The product the catalog has for the device. Defaults to `nil`.
  ///   - status: The state the device reported. Defaults to `nil`.
  ///   - checks: The checks, in order.
  ///   - checklist: What only a person can do. Defaults to none.
  public init(
    device: InsteonAddress,
    engine: InsteonEngine? = nil,
    identity: ReportedIdentity? = nil,
    productName: String? = nil,
    status: DeviceStatus? = nil,
    checks: [SelfTestCheck],
    checklist: [SelfTestChecklistItem] = []
  ) {

    self.device = device
    self.engine = engine
    self.identity = identity
    self.productName = productName
    self.status = status
    self.checks = checks
    self.checklist = checklist

  }

  /// How the test came out as a whole: failed if any check failed, else warning if any gave
  /// a warning, else passed. Skipped checks don't count.
  public var outcome: SelfTestOutcome {

    let outcomes: [SelfTestOutcome] = checks.map(\.outcome)

    if outcomes.contains(.failed) {

      return .failed

    }

    if outcomes.contains(.warning) {

      return .warning

    }

    return .passed

  }

  /// The check of a kind, or `nil` if the test didn't include it.
  ///
  /// - Parameter kind: The check's kind.
  /// - Returns: The check.
  public func check(_ kind: SelfTestCheckKind) -> SelfTestCheck? {

    checks.first { (check: SelfTestCheck) -> Bool in check.kind == kind }

  }

}
