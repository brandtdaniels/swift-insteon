/// A command line the `insteon` command can't run, with a message that says why.
public enum ArgumentError: Error, Hashable, Sendable {

  /// The subcommand isn't one the command has.
  case unknownCommand(String)

  /// The option isn't one the subcommand, named second, takes, or one of the command's own.
  case unknownOption(String, subcommand: String?)

  /// The option needs a value after it.
  case missingValue(option: String)

  /// The option's value isn't one it takes; the last value says what it takes.
  case invalidValue(option: String, value: String, expected: String)

  /// The option doesn't take a value, but was given one with `=`.
  case unexpectedValue(option: String)

  /// An argument the subcommand, named second, doesn't take.
  case unexpectedArgument(String, subcommand: String)

  /// Two options that can't be used together.
  case conflictingOptions(String, String)

  /// `insteon device` needs a device's address.
  case missingAddress

  /// The text isn't an Insteon address, such as `1A.2B.3C`.
  case invalidAddress(String)

  /// `insteon device ADDRESS` needs an action, such as `on`.
  case missingDeviceAction

  /// The action isn't one `insteon device ADDRESS` has.
  case unknownDeviceAction(String)

  /// `help` was asked about something that isn't a subcommand.
  case unknownHelpTopic(String)

  /// `--hub` was given a user name or password, as in `user:password@host`.
  case credentialsInHub

  /// An option that takes a Hub's address, named here, was given a user name or password.
  case credentialsInOption(String)

  /// The subcommand, named second, needs an argument, named first, such as `VALUE`.
  case missingArgument(String, subcommand: String)

  /// `insteon modem send` refuses a serial command without `--force`; the value says why.
  case refusedSerialCommand(String)

}

extension ArgumentError: CustomStringConvertible {

  /// The error as a one-line message for the person who typed the command.
  public var description: String {

    switch self {
    case let .unknownCommand(name):
      "Unknown command '\(name)'. Run 'insteon --help' for the list of commands."
    case let .unknownOption(option, subcommand?):
      "Unknown option '\(option)' for 'insteon \(subcommand)'. Run 'insteon \(subcommand) --help' for its options."
    case let .unknownOption(option, nil):
      "Unknown option '\(option)'. Run 'insteon --help' for the options."
    case let .missingValue(option):
      "The option '\(option)' needs a value."
    case let .invalidValue(option, value, expected):
      "'\(value)' isn't a valid value for '\(option)': expected \(expected)."
    case let .unexpectedValue(option):
      "The option '\(option)' doesn't take a value."
    case let .unexpectedArgument(argument, subcommand):
      "Unexpected argument '\(argument)' for 'insteon \(subcommand)'. Run 'insteon \(subcommand) --help' for its usage."
    case let .conflictingOptions(first, second):
      "The options '\(first)' and '\(second)' can't be used together."
    case .missingAddress:
      "'insteon device' needs a device's address, such as 1A.2B.3C."
    case let .invalidAddress(text):
      "'\(text)' isn't an Insteon address: expected six hexadecimal digits, such as 1A.2B.3C."
    case .missingDeviceAction:
      "'insteon device ADDRESS' needs an action: \(Self.deviceActions)."
    case let .unknownDeviceAction(action):
      "Unknown device action '\(action)': expected \(Self.deviceActions)."
    case let .unknownHelpTopic(topic):
      "There's no help for '\(topic)'. Run 'insteon --help' for the list of commands."
    case .credentialsInHub:
      "The option '--hub' takes only HOST[:PORT]. Set the Hub's user name and password in the environment or the environment file instead."
    case let .credentialsInOption(option):
      "The option '\(option)' takes only HOST[:PORT]. Set the Hub's user name and password in the environment or the environment file instead."
    case let .missingArgument(argument, subcommand):
      "'insteon \(subcommand)' needs \(argument). Run 'insteon \(subcommand) --help' for its usage."
    case let .refusedSerialCommand(reason):
      "\(reason) Pass --force to send it anyway."
    }

  }

  /// The actions of `insteon device ADDRESS`, as the errors list them.
  private static let deviceActions = "id, ping, on, off, instant, status, beep, links, settings, set or send"

}
