import InsteonClient
import InsteonDemo
import InsteonService
import Observation

/// Which network the app runs on.
public enum NetworkChoice: Sendable {
  /// A made-up network that needs no Hub and no pairing.
  case demo
  /// A service reached through a connection.
  case paired(ClientConnection)
}

/// The network a screen calls, whichever the choice was. Both answer through the same service protocols.
public struct AppNetwork: DeviceQuerying, DeviceCommanding, SceneManaging {
  private enum Backing: Sendable {
    case demo(InsteonService)
    case paired(ClientConnection)
  }

  private let backing: Backing

  init(_ choice: NetworkChoice) {
    switch choice {
    case .demo: backing = .demo(DemoNetwork.make())
    case let .paired(connection): backing = .paired(connection)
    }
  }

  public func devices() async throws -> [ServiceDevice] {
    switch backing {
    case let .demo(service): try await service.devices()
    case let .paired(connection): try await connection.devices()
    }
  }

  public func execute(_ command: ServiceCommand) async throws -> CommandReceipt {
    switch backing {
    case let .demo(service): try await service.execute(command)
    case let .paired(connection): try await connection.execute(command)
    }
  }

  public func scenes() async throws -> SceneList {
    switch backing {
    case let .demo(service): try await ServiceScenes(service).scenes()
    case let .paired(connection): try await connection.scenes()
    }
  }

  public func refreshScenes() async throws -> SceneList {
    switch backing {
    case let .demo(service): try await ServiceScenes(service).refreshScenes()
    case let .paired(connection): try await connection.refreshScenes()
    }
  }

  public func runScene(_ number: Int, action: SceneAction, idempotencyKey: String?) async throws -> SceneRunReceipt {
    switch backing {
    case let .demo(service): try await ServiceScenes(service).runScene(number, action: action, idempotencyKey: idempotencyKey)
    case let .paired(connection): try await connection.runScene(number, action: action, idempotencyKey: idempotencyKey)
    }
  }
}

/// The app's choice of network and the screen it gives.
///
/// The launch argument `--demo` chooses the demo network, so the app runs with no Hub. With no
/// choice made, the app asks which network to use.
@MainActor
@Observable
public final class AppModel {
  /// The launch argument that chooses the demo network.
  public static let demoArgument = "--demo"

  /// The devices screen over the chosen network, or `nil` until a choice is made.
  public private(set) var devices: DevicesScreen<AppNetwork>?

  /// The scenes screen over the chosen network, or `nil` until a choice is made.
  public private(set) var scenes: ScenesScreen<AppNetwork>?

  /// A value that differs after each choice, for a view to use as its identity so it takes the new screen.
  public private(set) var identity = 0

  /// Creates the model from the process's launch arguments.
  public init(arguments: [String]) {
    if arguments.contains(Self.demoArgument) { choose(.demo) }
  }

  /// Runs the app on a network, replacing any earlier choice.
  public func choose(_ choice: NetworkChoice) {
    identity += 1
    let network = AppNetwork(choice)
    devices = DevicesScreen(network: network)
    scenes = ScenesScreen(network: network)
  }
}
