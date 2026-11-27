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
    let level = ServerLogging.level(arguments: arguments, environment: ProcessInfo.processInfo.environment)
    LoggingSystem.bootstrap { ServerLogging.handler(label: $0, level: level) }
    let logger = Logger(label: "insteon-server")
    do {
      if arguments.first == "pair" {
        let options = Array(arguments.dropFirst())
        if options == ["--help"] || options == ["-h"] {
          print(PairCommand.help)
          return
        }
        let text = try await PairCommand.run(arguments: options, environment: ProcessInfo.processInfo.environment, showsQRCode: isatty(STDOUT_FILENO) != 0)
        print(text, terminator: "")
        FileHandle.standardError.write(Data((PairCommand.notice + "\n").utf8))
        return
      }
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
