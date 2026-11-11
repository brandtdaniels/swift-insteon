/// What a message does to its addressee, the device or modem it's sent to, as the catalog marks
/// a flag command, standard command, extended command or keep-awake message given as bytes.
///
/// An app decides from it whether a message needs a person's consent. An effect from a later
/// version of the catalog keeps its name and ranks as ``destructive``:
///
/// ```swift
/// if let command = commands.standardCommand(named: "readStatus"), command.effect?.strictness == .readOnly {
///   print(command.name, "changes nothing on the device")
/// }
/// ```
public struct CommandEffect: RawRepresentable, Hashable, Sendable, CustomStringConvertible {

  /// How strict an effect is: what consent it needs, from none to the most.
  public enum Strictness: Int, Comparable, Sendable {

    /// The message changes nothing the addressee keeps or does: ``CommandEffect/readOnly``.
    case readOnly

    /// The message changes a setting, a link or what the addressee does:
    /// ``CommandEffect/configuration``, ``CommandEffect/link`` or ``CommandEffect/actuation``.
    /// None of the three stands for another.
    case change

    /// The message can remove or overwrite what the addressee keeps, or leave it unable to
    /// communicate: ``CommandEffect/destructive``, or an effect this package doesn't know.
    case destructive

    /// Whether a strictness needs less consent than another.
    public static func < (left: Strictness, right: Strictness) -> Bool {

      left.rawValue < right.rawValue

    }

  }

  /// The effect as the catalog writes it, such as `"readOnly"`.
  public let rawValue: String

  /// Creates an effect from the catalog's name for it.
  ///
  /// - Parameter rawValue: The effect as the catalog writes it.
  public init(rawValue: String) {

    self.rawValue = rawValue

  }

  /// Asks for state and changes nothing the addressee keeps or does, apart from state that
  /// matters only to the request.
  public static let readOnly = CommandEffect(rawValue: "readOnly")

  /// Changes a setting the addressee keeps and acts on later, and nothing it does at once.
  public static let configuration = CommandEffect(rawValue: "configuration")

  /// Puts the addressee in or out of ALL-Linking mode, or adds an ALL-Link record.
  public static let link = CommandEffect(rawValue: "link")

  /// Changes what the addressee does at once, such as its load or a group broadcast.
  public static let actuation = CommandEffect(rawValue: "actuation")

  /// Removes or overwrites ALL-Link records, memory or counters, restores factory settings, or
  /// leaves the addressee unable to communicate with the modem until a person acts.
  public static let destructive = CommandEffect(rawValue: "destructive")

  /// How strict the effect is, with an effect this package doesn't know ranked
  /// ``Strictness/destructive``.
  public var strictness: Strictness {

    switch self {
    case .readOnly:
      .readOnly
    case .configuration, .link, .actuation:
      .change
    default:
      .destructive
    }

  }

  /// The effect as the catalog writes it.
  public var description: String { rawValue }

}
