import Foundation
import InsteonServerSupport
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@main
struct InsteonServer {
  static func main() async {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments == ["--help"] || arguments == ["-h"] {
      print(ServerRunner.help)
      return
    }
    do {
      try await ServerRunner.run(arguments: arguments, environment: ProcessInfo.processInfo.environment)
    } catch let error as ServerOptionError {
      fail(error.description)
    } catch let error as ServerRunError {
      fail(error.description)
    } catch is CancellationError {
      return
    } catch {
      // Arbitrary errors can contain request details. Keep diagnostics out of shared logs.
      fail("The server could not start or its connection failed. Check the protected settings, listener, catalog, state file and Hub or modem.")
    }
  }

  private static func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("insteon-server: " + message + "\n").utf8))
    exit(1)
  }
}
