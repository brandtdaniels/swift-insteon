import Foundation
import InsteonCore

/// A command that couldn't do what was asked, with a message that says why and what to do.
public struct CommandFailure: Error, CustomStringConvertible, Hashable, Sendable {

  /// The message for the person who typed the command.
  public let description: String

  /// Creates a failure with its message.
  ///
  /// - Parameter description: The message for the person who typed the command.
  public init(description: String) {

    self.description = description

  }

}

/// Names for the values the `insteon` command prints.
public enum Names {

  /// A category with its name, such as "0x01 (Example Lighting Control)".
  ///
  /// - Parameter category: The category.
  /// - Returns: The category, with its name when it has one.
  public static func category(_ category: DeviceCategory) -> String {

    category.name.map { "\(category) (\($0))" } ?? "\(category)"

  }

  /// An engine as Insteon's documents name it, or "unknown".
  ///
  /// - Parameter engine: The engine, or `nil` if it isn't known.
  /// - Returns: The engine's name.
  public static func engine(_ engine: InsteonEngine?) -> String {

    engine?.name ?? "unknown"

  }

  /// The modem's role in a link it reported, or "unknown".
  ///
  /// - Parameter mode: The role, or `nil` if it isn't known.
  /// - Returns: The role's name.
  public static func mode(_ mode: AllLinkMode?) -> String {

    mode?.name ?? "unknown"

  }

  /// An error as a one-line message, without credentials: the command's own errors, and the
  /// libraries' as InsteonCore describes them, with where to set the Hub's user name and
  /// password when the Hub rejects them.
  ///
  /// - Parameter error: The error.
  /// - Returns: The message.
  public static func message(for error: any Error) -> String {

    switch error {
    case let error as ArgumentError:
      return error.description
    case let error as ConfigurationError:
      return error.description
    case let error as DotEnvError:
      return error.description
    case let error as EnvironmentFileError:
      return error.description
    case is CancellationError:
      return "Interrupted."
    case let error as CommandFailure:
      return error.description
    case let error as RelayStateLinkingError:
      return LinkingEventText.relayStateMessage(error)
    default:
      break
    }

    if InsteonErrorDescription.isRejectedHubCredentials(error), let message = InsteonErrorDescription.message(for: error) {

      return message + " Check INSTEON_HUB_USERNAME and INSTEON_HUB_PASSWORD."

    }

    return InsteonErrorDescription.message(for: error) ?? error.localizedDescription

  }

}
