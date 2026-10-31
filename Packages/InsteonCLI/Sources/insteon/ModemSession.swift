import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import InsteonCLICore
import InsteonCore
import InsteonHubClient
import InsteonModem
import InsteonProtocol

/// Opens the modem a command line names, and runs a command with it.
enum ModemSession {

  /// The process's environment, with the variables of the environment file merged in: the
  /// file `--env-file` names, or else `$XDG_CONFIG_HOME/insteon/env` or
  /// `~/.config/insteon/env`, if it exists. A variable set in the environment wins over the
  /// file.
  ///
  /// The file is read only if it's a regular file the current user owns and no one else can
  /// write to, and a warning is printed if others can read it. Its contents are never printed.
  ///
  /// - Parameter explicitPath: The path given with `--env-file`, if any.
  /// - Throws: `EnvironmentFileError` if the file can't or mustn't be read, or `DotEnvError`
  ///   if it has a malformed line.
  static func loadEnvironment(explicitPath: String?) throws -> [String: String] {

    let environment = ProcessInfo.processInfo.environment

    guard let path = EnvironmentFile.path(explicit: explicitPath, environment: environment) else {

      return environment

    }

    guard FileManager.default.fileExists(atPath: path) else {

      // The default file is optional; one named on the command line isn't.
      if explicitPath != nil {

        throw EnvironmentFileError.notFound(path: path)

      }

      return environment

    }

    let contents = try readEnvironmentFile(at: path)

    return try DotEnv.merging(DotEnv.parse(contents), into: environment)

  }

  /// Checks the file's type, owner and permissions, opens it, checks them again on the open
  /// file, so it can't be swapped between the check and the read, and reads it as UTF-8.
  ///
  /// The first check keeps the command from opening something that isn't a regular file, such
  /// as a named pipe, which could block.
  private static func readEnvironmentFile(at path: String) throws(EnvironmentFileError) -> String {

    var pathInfo = stat()

    guard stat(path, &pathInfo) == 0 else {

      throw EnvironmentFileError.unreadable(path: path)

    }

    if case let .refuse(refusal) = verdict(of: pathInfo) {

      throw EnvironmentFileError.refused(path: path, refusal)

    }

    guard let handle = FileHandle(forReadingAtPath: path) else {

      throw EnvironmentFileError.unreadable(path: path)

    }

    defer { try? handle.close() }

    var info = stat()

    guard fstat(handle.fileDescriptor, &info) == 0 else {

      throw EnvironmentFileError.unreadable(path: path)

    }

    switch verdict(of: info) {
    case .read:
      break
    case .readWithWarning:
      Output.note("insteon: warning: others can read the environment file \(path). Make it readable only by you: chmod 600 \(path)")
    case let .refuse(refusal):
      throw EnvironmentFileError.refused(path: path, refusal)
    }

    guard
      let data = try? handle.readToEnd() ?? Data(),
      let contents = String(data: data, encoding: .utf8)
    else {

      throw EnvironmentFileError.unreadable(path: path)

    }

    return contents

  }

  /// Whether to read a file, from what `stat` or `fstat` says about it.
  private static func verdict(of info: stat) -> EnvironmentFile.Verdict {

    EnvironmentFile.verdict(mode: Int(info.st_mode), ownerID: Int(info.st_uid), currentUserID: Int(getuid()))

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

    try await run(invocation, reachingHub: { (modem: Modem, _: HubLocation?) async throws -> Void in

      try await body(modem)

    })

  }

  /// Opens the modem, runs `body` with it and the Hub it's reached through, in a task that
  /// Control-C cancels, and closes the modem.
  ///
  /// - Parameters:
  ///   - invocation: The command line, which names the modem with `--hub` or `--serial`.
  ///   - body: The work to do with the modem, given the Hub's host and port, or `nil` for a
  ///     serial modem. The Hub's credentials aren't part of it.
  static func run(_ invocation: Invocation, reachingHub body: @escaping @Sendable (Modem, HubLocation?) async throws -> Void) async throws {

    let environment = try loadEnvironment(explicitPath: invocation.envFilePath)
    let target = try ModemTarget.resolve(hub: invocation.hub, serialPath: invocation.serialPath, environment: environment)

    switch target {
    case let .hub(host, port):
      let credentials = try HubCredentials(environment: environment)
      let endpoint = HubEndpoint(host: host, port: port ?? HubEndpoint.defaultPort)
      let hub = Hub(endpoint: endpoint, user: credentials.user, password: credentials.password)

      // The address can come from the environment file, so say where the password is going.
      Output.note("Connecting to the Hub at \(endpoint.host):\(endpoint.port)")

      do {

        let location = HubLocation(host: endpoint.host, port: endpoint.port)

        try await withModem(HubConnection(hub: hub)) { (modem: Modem) async throws -> Void in

          try await body(modem, location)

        }

      } catch is HubStoppedAnswering {

        // The Hub answered earlier in the run, so it's busy rather than gone, most likely with
        // a device that doesn't answer; 'insteon discover' wouldn't help.
        throw CommandFailure(description: HubText.stoppedAnswering(host: endpoint.host, port: endpoint.port, device: device(of: invocation)))

      } catch {

        // URLSession's own message, such as "The request timed out.", doesn't say it was the Hub.
        if let message = Names.hubUnanswered(error, endpoint: endpoint) {

          throw CommandFailure(description: message)

        }

        throw error

      }
    case let .serial(path):
      #if os(macOS) || os(Linux)
      let port = try SerialPort(path: path)
      defer { port.close() }

      try await withModem(port) { (modem: Modem) async throws -> Void in

        try await body(modem, nil)

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

  private static func withModem(_ connection: any ModemConnection, _ body: @escaping @Sendable (Modem) async throws -> Void) async throws {

    try await Modem.withConnection(connection) { modem in

      try await Interrupt.cancellingOnInterrupt {

        try await body(modem)

      }

    }

  }

}
