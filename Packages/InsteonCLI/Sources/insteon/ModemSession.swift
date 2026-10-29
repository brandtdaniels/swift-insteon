import Foundation
import InsteonCLICore
import InsteonHubClient
import InsteonModem

/// Opens the modem a command line names, and runs a command with it.
enum ModemSession {

  /// The process's environment, with the variables of a `.env` file in the current directory
  /// merged in. A variable set in the environment wins over the file.
  ///
  /// - Throws: `DotEnvError` if the file has a malformed line, or the error reading it.
  static func loadEnvironment() throws -> [String: String] {

    let environment = ProcessInfo.processInfo.environment
    let path = FileManager.default.currentDirectoryPath + "/" + DotEnv.fileName

    guard FileManager.default.fileExists(atPath: path) else {

      return environment

    }

    let contents = try String(contentsOfFile: path, encoding: .utf8)

    return try DotEnv.merging(DotEnv.parse(contents), into: environment)

  }

  /// Opens the modem, runs `body` with it in a task that Control-C cancels, and closes the
  /// modem.
  ///
  /// `body` runs in a task of its own so that Control-C cancels only it, and the modem keeps
  /// running while the command cleans up, such as by taking the modem out of linking mode.
  ///
  /// - Parameters:
  ///   - invocation: The command line, which names the modem with `--hub` or `--serial`.
  ///   - body: The work to do with the modem.
  static func run(_ invocation: Invocation, _ body: @escaping @Sendable (Modem) async throws -> Void) async throws {

    let environment = try loadEnvironment()
    let target = try ModemTarget.resolve(hub: invocation.hub, serialPath: invocation.serialPath, environment: environment)

    switch target {
    case let .hub(host, port):
      let credentials = try HubCredentials(environment: environment)
      let hub = Hub(
        endpoint: HubEndpoint(host: host, port: port ?? HubEndpoint.defaultPort),
        user: credentials.user,
        password: credentials.password
      )

      try await withModem(HubConnection(hub: hub), body)
    case let .serial(path):
      #if os(macOS) || os(Linux)
      let port = try SerialPort(path: path)
      defer { port.close() }

      try await withModem(port, body)
      #else
      _ = path

      throw ConfigurationError.serialUnavailable
      #endif
    }

  }

  private static func withModem(_ connection: any ModemConnection, _ body: @escaping @Sendable (Modem) async throws -> Void) async throws {

    try await Modem.withConnection(connection) { modem in

      try await Interrupt.cancellingOnInterrupt {

        try await body(modem)

      }

    }

  }

}
