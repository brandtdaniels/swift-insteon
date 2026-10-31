import Foundation
import InsteonCLISupport
import InsteonCore

/// Opens the modem a command line names, through InsteonCore's `ModemSession`, and runs a
/// command with it.
enum CommandSession {

  /// The process's environment, with the variables of the environment file merged in, as
  /// `EnvironmentFile.load(explicitPath:environment:warn:)` reads them; its warnings go to
  /// standard error.
  ///
  /// - Parameter explicitPath: The path given with `--env-file`, if any.
  /// - Throws: `EnvironmentFileError` if the file can't or mustn't be read, or `DotEnvError`
  ///   if it has a malformed line.
  static func loadEnvironment(explicitPath: String?) throws -> [String: String] {

    try EnvironmentFile.load(explicitPath: explicitPath, environment: ProcessInfo.processInfo.environment, warn: Output.note)

  }

  /// Opens the modem, runs `body` with it in a task that Control-C cancels, and closes the
  /// modem.
  ///
  /// `body` runs in a task of its own so that Control-C cancels only it, and the modem keeps
  /// running while the command cleans up, such as by taking the modem out of linking mode.
  ///
  /// - Parameters:
  ///   - invocation: The command line, which names the modem with `--hub` or `--serial`.
  ///   - body: The work to do with the modem. The session's `hub` is the Hub's host and port,
  ///     or `nil` for a serial modem; the Hub's credentials aren't part of it.
  static func run(_ invocation: Invocation, _ body: @escaping @Sendable (ModemSession) async throws -> Void) async throws {

    let environment = try loadEnvironment(explicitPath: invocation.envFilePath)
    let target = try ModemTarget.resolve(hub: invocation.hub, serialPath: invocation.serialPath, environment: environment)

    switch target {
    case let .hub(host, port):
      let credentials = try HubCredentials(environment: environment)
      let hubPort: Int = port ?? HubLocation.defaultPort

      // The password goes only to a private IPv4 address; ModemSession.withHub refuses any
      // other, and saying so here keeps the note below from naming a host it never reaches.
      guard HubLocation(host: host, port: hubPort).acceptsCredentials else {

        throw HubAddressRefused(host: host)

      }

      // The address can come from the environment file, so say where the password is going.
      Output.note("Connecting to the Hub at \(host):\(hubPort)")

      do {

        try await ModemSession.withHub(host: host, port: hubPort, user: credentials.user, password: credentials.password) { (session: ModemSession) async throws -> Void in

          try await Interrupt.cancellingOnInterrupt {

            try await body(session)

          }

        }

      } catch {

        switch HubFailure(error) {
        case .stoppedAnswering?:
          // The Hub answered earlier in the run, so it's busy rather than gone, most likely
          // with a device that doesn't answer; 'insteon discover' wouldn't help.
          throw CommandFailure(description: HubText.stoppedAnswering(host: host, port: hubPort, device: device(of: invocation)))
        case .unanswered?:
          // URLSession's own message, such as "The request timed out.", doesn't say it was the
          // Hub.
          throw CommandFailure(description: HubText.unanswered(host: host, port: hubPort))
        case nil:
          throw error
        }

      }
    case let .serial(path):
      #if os(macOS) || os(Linux)
      try await ModemSession.withSerialPort(path: path) { (session: ModemSession) async throws -> Void in

        try await Interrupt.cancellingOnInterrupt {

          try await body(session)

        }

      }
      #else
      _ = path

      throw ConfigurationError.serialUnavailable
      #endif
    }

  }

  /// The device a command line's command is for, if it's for one.
  private static func device(of invocation: Invocation) -> InsteonAddress? {

    switch invocation.subcommand {
    case let .device(address, _):
      return address
    case let .link(options):
      return options.device
    case let .unlink(options):
      return options.device
    case let .remove(options):
      return options.device
    default:
      return nil
    }

  }

}
