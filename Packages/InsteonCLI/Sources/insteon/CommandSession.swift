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
      // Refused before connecting, so the note below never names a host the password doesn't
      // reach.
      let hubPort: Int = try ModemTarget.hubLocation(host: host, port: port).port

      // The address can come from the environment file, so say where the password is going.
      Output.note("Connecting to the Hub at \(host):\(hubPort)")

      do {

        try await ModemSession.withHub(host: host, port: hubPort, user: credentials.user, password: credentials.password) { (session: ModemSession) async throws -> Void in

          try await Interrupt.cancellingOnInterrupt {

            try await body(session)

          }

        }

      } catch {

        if let failure = HubText.failure(error, host: host, port: hubPort, device: invocation.device) {

          throw CommandFailure(description: failure)

        }

        throw error

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

}
