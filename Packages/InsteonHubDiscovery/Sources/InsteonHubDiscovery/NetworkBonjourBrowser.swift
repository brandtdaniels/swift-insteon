#if canImport(Network)
import Foundation
import Network
import InsteonNetworking

/// Browses Bonjour with the Network framework, on platforms that have it.
///
/// A browse is a read of multicast DNS answers: it sends no request to any host it lists.
/// Resolving a service opens a TCP connection to the port the service names, to learn the
/// address it resolves to, and closes it at once without sending a byte. ``HubDiscovery``
/// resolves only a service whose model record names a Hub Pro.
///
/// On iOS, iPadOS, tvOS and visionOS, an app must list the service types it browses in its
/// `Info.plist` as `NSBonjourServices`, here `_hap._tcp`, as well as say why it uses the local
/// network.
public struct NetworkBonjourBrowser: BonjourBrowsing {

  /// How long resolving one service has to take: 3 seconds.
  public static let resolveTimeout: Duration = .seconds(3)

  /// Creates a browser.
  public init() {}

  /// Lists the services of a type as they're found, until the stream stops being read.
  ///
  /// - Parameter type: The service type, such as `_hap._tcp`.
  /// - Returns: The services found, each once as it appears.
  public func browse(type: String) async -> AsyncStream<BonjourService> {

    AsyncStream { continuation in

      let browser = NWBrowser(for: .bonjourWithTXTRecord(type: type, domain: nil), using: .tcp)

      browser.browseResultsChangedHandler = { _, changes in

        for case let .added(result) in changes {

          guard case let .service(name, type, domain, _) = result.endpoint else {

            continue

          }

          var record: [String: String] = [:]

          if case let .bonjour(text) = result.metadata {

            record = text.dictionary

          }

          continuation.yield(BonjourService(name: name, type: type, domain: domain, port: 0, textRecord: record))

        }

      }

      browser.stateUpdateHandler = { state in

        switch state {
        case .failed, .cancelled:
          continuation.finish()
        default:
          break
        }

      }

      continuation.onTermination = { _ in browser.cancel() }

      browser.start(queue: DispatchQueue(label: "swift-insteon.bonjour-browse"))

    }

  }

  /// Finds the IPv4 address a service resolves to.
  ///
  /// - Parameter service: A service the browse listed.
  /// - Returns: The address, or `nil` if the service doesn't resolve to an IPv4 address in
  ///   ``NetworkBonjourBrowser/resolveTimeout``.
  public func resolveAddress(of service: BonjourService) async -> String? {

    let connection = NWConnection(
      to: .service(name: service.name, type: service.type, domain: service.domain, interface: nil),
      using: .tcp
    )
    let result = OneShot<String?>()

    connection.stateUpdateHandler = { state in

      switch state {
      case .ready:
        if case let .hostPort(host, _)? = connection.currentPath?.remoteEndpoint, case let .ipv4(address) = host {

          result.finish(.success(address.rawValue.map { String($0) }.joined(separator: ".")))

        } else {

          result.finish(.success(nil))

        }
      case .failed, .cancelled:
        result.finish(.success(nil))
      default:
        break
      }

    }

    return await withTaskCancellationHandler {

      connection.start(queue: DispatchQueue(label: "swift-insteon.bonjour-resolve"))

      let address: String? = try? await withDeadline(Self.resolveTimeout) { try await result.value() }

      connection.cancel()

      return address

    } onCancel: {

      connection.cancel()
      result.finish(.success(nil))

    }

  }

}
#endif
