import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import InsteonCLICore
import InsteonCore
import InsteonModem

/// The `insteon` command: drives an Insteon Hub or modem, and its devices, from the terminal.
///
/// The command line is read by `Invocation.parse(_:)` in InsteonCLICore, so this target only
/// runs what it asks for.
@main
struct InsteonCommand {

  static func main() async {

    let status = await run(Array(ProcessInfo.processInfo.arguments.dropFirst()))

    exit(status)

  }

  /// Runs a command line and returns the command's exit status.
  static func run(_ arguments: [String]) async -> Int32 {

    do {

      let invocation = try Invocation.parse(arguments)

      try await run(invocation)

      return ExitStatus.success

    } catch {

      Output.note("insteon: \(Names.message(for: error))")

      switch error {
      case is ArgumentError, is ConfigurationError, is DotEnvError, is EnvironmentFileError:
        return ExitStatus.usage
      case is CancellationError:
        return ExitStatus.interrupted
      default:
        return ExitStatus.failure
      }

    }

  }

  private static func run(_ invocation: Invocation) async throws {

    let printsJSON = invocation.printsJSON

    switch invocation.subcommand {
    case let .help(topic):
      Output.line(HelpText.text(for: topic) ?? HelpText.overview)
    case let .discover(options):
      try await DiscoverCommand.run(options, envFilePath: invocation.envFilePath, printsJSON: printsJSON)
    case .info:
      try await withModem(invocation) { modem, names in

        try await ModemCommands.info(modem, names: names, printsJSON: printsJSON)

      }
    case let .links(options):
      try await withModemAndHub(invocation) { modem, names, hub in

        try await ModemCommands.links(modem, hub: hub, options: options, names: names, printsJSON: printsJSON)

      }
    case let .link(options):
      try await withModem(invocation) { modem, names in

        try await ModemCommands.link(modem, options: options, names: names, printsJSON: printsJSON)

      }
    case .cancelLinking:
      try await withModem(invocation) { modem, _ in

        try await ModemCommands.cancelLinking(modem)

      }
    case let .unlink(options):
      try await withModem(invocation) { modem, names in

        try await ModemCommands.unlink(modem, options: options, names: names, printsJSON: printsJSON)

      }
    case let .remove(options):
      // Asked before the modem is opened, so a command that can't ask fails at once.
      let asks: Bool = try options.asksForConfirmation(readsFromTerminal: Terminal.readsFromTerminal)

      try await withModem(invocation) { modem, names in

        try await ModemCommands.remove(modem, options: options, asks: asks, names: names, printsJSON: printsJSON)

      }
    case let .device(device, action):
      try await withModemAndHub(invocation) { modem, names, hub in

        try await DeviceCommands.run(action, device: device, modem: modem, hub: hub, names: names, printsJSON: printsJSON)

      }
    case let .scene(group, isOn):
      try await withModem(invocation) { modem, _ in

        try await SceneCommands.scene(group, isOn: isOn, modem: modem)

      }
    case let .beep(isDouble):
      try await withModem(invocation) { modem, _ in

        try await SceneCommands.beep(isDouble: isDouble, modem: modem)

      }
    case let .modemSend(request):
      try await withModem(invocation) { modem, _ in

        try await ExploreCommands.send(request, modem: modem)

      }
    case let .watch(options):
      try await withModem(invocation) { modem, names in

        await WatchCommand.run(options, modem: modem, names: names)

      }
    case .catalog:
      // Needs no modem, and reads neither the environment file nor the Hub's settings.
      CatalogCommand.status()
    case .catalogUpdate:
      try await CatalogCommand.update()
    }

  }

  /// Opens the modem the command line names and runs `body` with it and the catalog's
  /// product names.
  private static func withModem(
    _ invocation: Invocation,
    _ body: @escaping @Sendable (Modem, ProductNames) async throws -> Void
  ) async throws {

    let names = ProductNames()

    try await ModemSession.run(invocation) { modem in

      try await body(modem, names)

    }

  }

  /// Opens the modem the command line names and runs `body` with it, the catalog's product
  /// names, and the Hub's host and port, or `nil` for a serial modem.
  private static func withModemAndHub(
    _ invocation: Invocation,
    _ body: @escaping @Sendable (Modem, ProductNames, HubLocation?) async throws -> Void
  ) async throws {

    let names = ProductNames()

    try await ModemSession.run(invocation, reachingHub: { (modem: Modem, hub: HubLocation?) async throws -> Void in

      try await body(modem, names, hub)

    })

  }

}
