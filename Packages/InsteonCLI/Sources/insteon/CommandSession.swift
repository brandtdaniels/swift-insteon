import Foundation
import InsteonCLISupport
import InsteonCore

/// Opens the modem a command line names, through InsteonCore's `ModemSession`, and runs a
/// command with it.
enum CommandSession {

  /// The process's environment, with the variables of the environment file merged in, as
  /// `HubFiles.load(explicitPath:hubName:warn:)` reads them; its warnings go to standard error.
  ///
  /// - Parameters:
  ///   - explicitPath: The path given with `--env-file`, if any.
  ///   - hubName: The Hub file's name given with `--hub`, if any.
  /// - Throws: `EnvironmentFileError` if the file can't or mustn't be read, `DotEnvError`
  ///   if it has a malformed line, or `ConfigurationError` if a Hub's file doesn't exist.
  static func loadEnvironment(explicitPath: String?, hubName: String? = nil) throws -> [String: String] {

    try HubFiles(store: LocalHubFiles(), environment: ProcessInfo.processInfo.environment)
      .load(explicitPath: explicitPath, hubName: hubName, warn: Output.note)

  }

  /// The Hub file's name `--hub` gave, unless `--env-file` names the file to read, which wins.
  static func hubName(of invocation: Invocation) -> String? {

    guard let name = invocation.hubName else {

      return nil

    }

    guard invocation.envFilePath == nil else {

      Output.note("Ignoring --hub \(name): --env-file names the file to read.")

      return nil

    }

    return name

  }

  /// Opens the modem, runs `body` with it in a task that Control-C cancels, and closes the
  /// modem.
  ///
  /// `body` runs in a task of its own so that Control-C cancels only it, and the modem keeps
  /// running while the command cleans up, such as by taking the modem out of linking mode.
  ///
  /// - Parameters:
  ///   - invocation: The command line, which names the modem with `--hub` or `--serial`.
  ///   - catalog: The catalog the session describes the modem's serial commands with.
  ///   - body: The work to do with the modem. The session's `hub` is the Hub's host and port,
  ///     or `nil` for a serial modem; the Hub's credentials aren't part of it.
  static func run(_ invocation: Invocation, catalog: ProductCatalog? = nil, _ body: @escaping @Sendable (ModemSession) async throws -> Void) async throws {

    let hubName = hubName(of: invocation)
    let environment = try loadEnvironment(explicitPath: invocation.envFilePath, hubName: hubName)
    let target = try ModemTarget.resolve(hub: invocation.hub, hubName: hubName, serialPath: invocation.serialPath, environment: environment)

    switch target {
    case let .hub(host, port):
      // Refused before connecting, so the note below never names a host the password doesn't
      // reach, and before the credentials are read, so a host that's a Hub Pro is explained
      // rather than asked for a password.
      let hubPort: Int = try ModemTarget.hubLocation(host: host, port: port).port
      let credentials: HubCredentials

      do {

        credentials = try HubCredentials(environment: environment)

      } catch ConfigurationError.missingCredentials {

        if let refusal = try await hubProRefusal(host: host, catalog: catalog) {

          throw refusal

        }

        throw ConfigurationError.missingCredentials

      }

      // The address can come from the environment file, so say where the password is going.
      Output.note("Connecting to the Hub at \(host):\(hubPort)")

      let answered = HubAnswers()

      do {

        try await ModemSession.withHub(
          host: host,
          port: hubPort,
          user: credentials.user,
          password: credentials.password,
          catalog: catalog,
          onPollSucceeded: { await answered.record() }
        ) { (session: ModemSession) async throws -> Void in

          try await Interrupt.cancellingOnInterrupt {

            try await body(session)

          }

        }

      } catch {

        let hubHasAnswered = await answered.hasAnswered

        if let failure = HubText.failure(error, host: host, port: hubPort, device: invocation.device, hubHasAnswered: hubHasAnswered) {

          // A Hub Pro doesn't listen on the Hub's port, so it reads as a Hub that didn't answer.
          if HubFailure(error, hubHasAnswered: hubHasAnswered) == .unanswered, let refusal = try await hubProRefusal(host: host, catalog: catalog) {

            throw refusal

          }

          throw CommandFailure(description: failure)

        }

        throw error

      }
    case let .serial(path):
      #if os(macOS) || os(Linux)
      try await ModemSession.withSerialPort(path: path, catalog: catalog) { (session: ModemSession) async throws -> Void in

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

  /// The failure that explains a host that answers like a Hub Pro, or `nil` for any other host.
  ///
  /// The ports and models that identify a Hub Pro come from the catalog the session was given,
  /// or the bundled one, so a catalog that names none recognizes none.
  private static func hubProRefusal(host: String, catalog: ProductCatalog?) async throws -> CommandFailure? {

    let names = ProductNames()
    let source: ProductCatalog? = catalog ?? names.catalog
    let search = HubSearch(hubProPorts: source?.hubProPorts ?? [], hubProModels: source?.hubProModels ?? [])

    return try await HubText.hubProRefusal(host: host) { () async throws -> RecognizedHubPro? in

      try await search.recognizeHubPro(at: host).map { RecognizedHubPro(settings: $0.hubProSettings) }

    }

  }

}

/// Whether the Hub answered any poll of its buffer in a session.
private actor HubAnswers {

  private(set) var hasAnswered = false

  func record() {

    hasAnswered = true

  }

}
