import Foundation

/// The values that tune how the service waits and retries, written once and passed down.
///
/// ``standard`` holds the defaults. The server reads a person's own values from its options and
/// environment, checks them with ``validated()`` and gives the service the result, so nothing
/// below the service learns about options. The libraries keep their own parameters with their own
/// defaults, and tests pass their own values and clocks.
///
/// A value an Insteon document fixes stays a `static let` beside its citation, and a tuning field
/// may only lengthen it: ``validated()`` refuses a shorter one.
///
/// Fields are grouped by who uses them, so another group is added beside ``scenes`` without
/// changing it.
public struct ServiceTuning: Sendable, Codable, Equatable {

  /// How long a scene run waits.
  public struct Scenes: Sendable, Codable, Equatable {

    /// How long to wait for the modem to accept a scene's group command, by echoing it. A Hub
    /// brings the echo over polling, so it can come later than a serial modem's. Unverified.
    public var echoWait: Duration

    /// How long to wait for more cleanup traffic before giving up on the modem's cleanup status
    /// report. A member that doesn't answer makes the modem retry its cleanup before it reports,
    /// which the Insteon Developer's Guide doesn't time, so this is unverified: it is chosen from
    /// bench runs on a Hub 2. It can't be shorter than ``ServiceTuning/minimumCleanupQuietPeriod``.
    public var cleanupQuietPeriod: Duration

    /// The longest to wait for the status report after the modem accepted the command, however
    /// much traffic keeps coming, so a run holds the admission gate for a bounded time. Unverified.
    public var cleanupCap: Duration

    /// Creates the scene values.
    public init(echoWait: Duration, cleanupQuietPeriod: Duration, cleanupCap: Duration) {

      self.echoWait = echoWait
      self.cleanupQuietPeriod = cleanupQuietPeriod
      self.cleanupCap = cleanupCap

    }

    /// 5 seconds, 15 seconds and 60 seconds.
    public static let standard = Scenes(echoWait: .seconds(5), cleanupQuietPeriod: .seconds(15), cleanupCap: .seconds(60))

  }

  /// How long a scene run waits.
  public var scenes: Scenes

  /// The first cleanup comes up to 2.150 seconds after the broadcast, the Insteon Developer's
  /// Guide says, for a member that answers. A quiet period shorter than that could give up before
  /// the first cleanup.
  public static let minimumCleanupQuietPeriod: Duration = .milliseconds(2_150)

  /// The longest a wait may be set to: 5 minutes.
  public static let longestWait: Duration = .seconds(300)

  /// The longest the echo wait may be set to: 1 minute.
  public static let longestEchoWait: Duration = .seconds(60)

  /// The standard tuning.
  public static let standard = ServiceTuning(scenes: .standard)

  /// Creates a tuning.
  public init(scenes: Scenes = .standard) {

    self.scenes = scenes

  }

  /// This tuning, if every value is in range.
  ///
  /// - Throws: ``ServiceTuningError/invalid(field:)`` for the first value that is not positive,
  ///   is shorter than a document's figure, or is longer than its limit. A quiet period longer
  ///   than the cap is refused as the quiet period.
  public func validated() throws -> ServiceTuning {

    guard scenes.echoWait > .zero, scenes.echoWait <= Self.longestEchoWait else { throw ServiceTuningError.invalid(field: .scenesEchoWait) }
    guard scenes.cleanupCap > .zero, scenes.cleanupCap <= Self.longestWait else { throw ServiceTuningError.invalid(field: .scenesCleanupCap) }
    guard scenes.cleanupQuietPeriod >= Self.minimumCleanupQuietPeriod, scenes.cleanupQuietPeriod <= scenes.cleanupCap else { throw ServiceTuningError.invalid(field: .scenesCleanupQuiet) }

    return self

  }

  /// Every value with its name, in milliseconds, and where it came from.
  ///
  /// - Parameter sources: The source of each value by name, such as `scenes.echoWaitMs`. A value
  ///   with no entry is a default.
  public func entries(sources: [String: TuningSource]) -> [TuningEntry] {

    [
      TuningEntry(name: ServiceTuningError.Field.scenesEchoWait.name, milliseconds: Self.milliseconds(scenes.echoWait), source: sources[ServiceTuningError.Field.scenesEchoWait.name] ?? .default),
      TuningEntry(name: ServiceTuningError.Field.scenesCleanupQuiet.name, milliseconds: Self.milliseconds(scenes.cleanupQuietPeriod), source: sources[ServiceTuningError.Field.scenesCleanupQuiet.name] ?? .default),
      TuningEntry(name: ServiceTuningError.Field.scenesCleanupCap.name, milliseconds: Self.milliseconds(scenes.cleanupCap), source: sources[ServiceTuningError.Field.scenesCleanupCap.name] ?? .default)
    ]

  }

  private static func milliseconds(_ duration: Duration) -> Int {

    Int(duration.components.seconds) * 1_000 + Int(duration.components.attoseconds / 1_000_000_000_000_000)

  }

}

/// Where a tuning value came from.
public enum TuningSource: String, Sendable, Codable, Equatable {

  /// The standard value.
  case `default`

  /// A command-line option.
  case flag

  /// An environment variable.
  case environment

}

/// One tuning value as health reports it.
public struct TuningEntry: Sendable, Codable, Equatable {

  /// The value's name, such as `scenes.echoWaitMs`.
  public let name: String

  /// The value, in milliseconds.
  public let milliseconds: Int

  /// Where the value came from.
  public let source: TuningSource

  /// Creates an entry.
  public init(name: String, milliseconds: Int, source: TuningSource) {

    self.name = name
    self.milliseconds = milliseconds
    self.source = source

  }

}

/// A tuning value the service refuses.
public enum ServiceTuningError: Error, Equatable {

  /// A tuning value, named as health and the server's options name it.
  public enum Field: String, Sendable, Equatable, CaseIterable {

    /// ``ServiceTuning/Scenes/echoWait``.
    case scenesEchoWait = "scenes.echoWaitMs"

    /// ``ServiceTuning/Scenes/cleanupQuietPeriod``.
    case scenesCleanupQuiet = "scenes.cleanupQuietMs"

    /// ``ServiceTuning/Scenes/cleanupCap``.
    case scenesCleanupCap = "scenes.cleanupCapMs"

    /// The name health lists the value under.
    public var name: String { rawValue }

  }

  /// The value is out of range.
  case invalid(field: Field)

}
