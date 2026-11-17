import Foundation
import InsteonServerSupport
import Logging
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
    LoggingSystem.bootstrap { StreamLogHandler.standardError(label: $0) }
    let logger = Logger(label: "insteon-server")
    do {
      try await ServerRunner.run(arguments: arguments, environment: ProcessInfo.processInfo.environment, logger: logger)
    } catch is CancellationError {
      return
    } catch {
      // The description names the cause and the setting to check, never a credential or client text.
      let failure = ServerFailure(error)
      failure.record(in: logger)
      exit(failure.exitStatus)
    }
  }
}
