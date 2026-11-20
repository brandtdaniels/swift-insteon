import Foundation
import InsteonHTTP

/// `insteon-server pair`: creates a client and prints the pairing document that carries its token.
public enum PairCommand {
  /// Command-line help for `pair`.
  public static let help = """
  Usage: insteon-server pair --name NAME [--scope read|control|admin] [OPTIONS]

  Creates a client and prints its pairing document, which holds the client's token.
  The token is shown once: the server keeps only a salted hash of it. On a terminal the
  document is followed by a QR code of it.

  --name NAME          The client's name, 1 through 64 characters, such as Phone.
  --scope SCOPE        What the client may do (default: control). read reads and follows
                       events; control also sends commands; admin also manages clients.
  --no-qr              Print the document only.
  --listen IPV4        The address the server listens on, for the document's local route.
  --port PORT          The server's port (default: 8080).
  --advertise-url URL  Where clients reach the server, instead of http://LISTEN:PORT.
  --home-name NAME     The home's name in the document (default: Home).
  --state PATH         The state file; the client file sits beside it.

  The document lists the routes that transports registered with the server, after the local one.
  The server recognizes the new client at once, whether it is running or not.
  """

  /// What a person is told after the document: it can't be shown again.
  public static let notice = "The credential above is shown once. Revoke the client with DELETE /api/v1/clients/{id} if it is lost."

  private static let passedOn: Set<String> = ["--listen", "--port", "--advertise-url", "--home-name", "--state"]

  /// Creates the client and returns the text to print: the document, then its QR code.
  ///
  /// - Parameters:
  ///   - arguments: The options after `pair`.
  ///   - environment: The process environment, for the default state path.
  ///   - showsQRCode: Whether to follow the document with a QR code. `--no-qr` turns it off.
  /// - Throws: A ``ServerFailure`` source error: describe it with ``ServerFailure/init(_:)``.
  public static func run(arguments: [String], environment: [String: String], showsQRCode: Bool) async throws -> String {
    var name: String?, scope: ClientScope?, skipsQRCode = false
    var rest: [String] = []
    var index = 0
    while index < arguments.count {
      let argument = arguments[index]
      if argument == "--no-qr" {
        skipsQRCode = true
        index += 1
        continue
      }
      guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") else { throw ServerOptionError.invalidArguments }
      let value = arguments[index + 1]
      switch argument {
      case "--name":
        guard name == nil else { throw ServerOptionError.invalidArguments }
        name = value
      case "--scope":
        guard scope == nil, let parsed = ClientScope(rawValue: value) else { throw ServerOptionError.invalidClient }
        scope = parsed
      case let option where passedOn.contains(option):
        rest += [option, value]
      default:
        throw ServerOptionError.invalidArguments
      }
      index += 2
    }
    guard let name else { throw ServerOptionError.invalidClient }
    let options = try ServerOptions(arguments: rest, environment: environment)

    // Read first, so routes that can't be read leave no client behind.
    let routesFile = FileRoutePersistence.url(besideState: options.statePath)
    let registered: [RegisteredRoute]
    do { registered = try await RouteStore(persistence: FileRoutePersistence(url: routesFile)).routes() }
    catch { throw ServerRunError.routesFileUnusable(path: routesFile.path) }
    let file = FileClientPersistence.url(besideState: options.statePath)
    let clients = ClientStore(persistence: FileClientPersistence(url: file))
    let issued: IssuedClient
    do { issued = try await clients.issue(name: name, scope: scope ?? .control) }
    catch ClientError.invalidName { throw ServerOptionError.invalidClient }
    catch ClientError.limitReached { throw ServerRunError.clientLimitReached }
    catch { throw ServerRunError.clientFileUnusable(path: file.path) }
    let document: PairingDocument
    do { document = ServerRunner.pairingConfiguration(for: options).document(for: issued, serviceID: try await clients.serviceID(), registered: registered) }
    catch { throw ServerRunError.clientFileUnusable(path: file.path) }

    var output = String(decoding: try document.encoded(prettyPrinted: true), as: UTF8.self) + "\n"
    if showsQRCode, !skipsQRCode {
      do { output += "\n" + (try QRCode(text: String(decoding: try document.encoded(), as: UTF8.self))).rendered() }
      catch { output += "\nThe document is too long for a QR code. Carry the JSON instead.\n" }
    }
    return output
  }
}
