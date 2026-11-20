import Foundation
import InsteonLoopbackTransport
import InsteonPluginKit

/// The reference transport: forwards a loopback port to the service and registers it as a route.
let help = """
Usage: insteon-reference-transport [--service URL] [--listen-port PORT] [--kind KIND]

Accepts TCP connections on 127.0.0.1 and forwards each, byte for byte, to the service.
It registers its address as a route with PUT /api/v1/routes/KIND, so pairing documents
issued afterward list it, and removes the route when it is stopped with Control-C or SIGTERM.

--service URL       The service's address (default: http://127.0.0.1:8080).
--listen-port PORT  The loopback port to accept on (default: 0, a port the system chooses).
--kind KIND         The route kind to register (default: loopback).

The token is read from the INSTEON_PLUGIN_TOKEN environment variable. It needs the admin
scope, because the transport registers a route. Create it with `insteon-server pair
--scope admin`, or POST /api/v1/clients.
"""

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(2)
}

struct Options {
  var service = "http://127.0.0.1:8080", listenPort = 0, kind = LoopbackTransport.kind

  init(_ words: [String]) {
    var arguments = words.makeIterator()
    while let argument = arguments.next() {
      switch argument {
      case "--help": print(help); exit(0)
      case "--service", "--listen-port", "--kind":
        guard let value = arguments.next() else { fail("\(argument) needs a value.\n\n" + help) }
        switch argument {
        case "--service": service = value
        case "--kind": kind = value
        default:
          guard let port = Int(value), (0...65535).contains(port) else { fail("--listen-port needs a port number.") }
          listenPort = port
        }
      default: fail(help)
      }
    }
  }
}

let options = Options(Array(CommandLine.arguments.dropFirst()))
let service = options.service, listenPort = options.listenPort, routeKind = options.kind
guard let url = URL(string: service), let upstreamPort = url.port, url.host == "127.0.0.1" || url.host == "localhost" else {
  fail("--service must be an http://127.0.0.1:PORT address: the transport forwards to the service's loopback port.")
}
guard let token = ProcessInfo.processInfo.environment["INSTEON_PLUGIN_TOKEN"], !token.isEmpty else {
  fail("Set INSTEON_PLUGIN_TOKEN to an admin client's token.")
}

let transport = LoopbackTransport(service: ServiceClient(baseURL: url, token: token), upstreamPort: upstreamPort, listenPort: listenPort, kind: routeKind)
let status: Int32 = await withTaskGroup(of: Int32.self) { group in
  group.addTask {
    do {
      try await transport.run { port in
        print("Forwarding 127.0.0.1:\(port) to the service and registered route \(routeKind). Stop with Control-C.")
        fflush(stdout)
      }
      return 0
    } catch {
      FileHandle.standardError.write(Data("The transport stopped: \(error)\n".utf8))
      return 1
    }
  }
  group.addTask {
    await TerminationSignal.received()
    return 0
  }
  let first = await group.next() ?? 1
  group.cancelAll()
  // The transport removes its route as it stops.
  while await group.next() != nil {}
  return first
}
exit(status)
