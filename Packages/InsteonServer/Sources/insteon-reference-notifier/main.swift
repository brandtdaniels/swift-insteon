import Foundation
import InsteonPluginKit

/// The reference notifier: follows the service's events and appends one line per notification.
let help = """
Usage: insteon-reference-notifier --state PATH [--service URL] [--output PATH] [--include-detail]

Follows GET /api/v1/events and delivers each `notification` event once, as a line of text:
the time the rule fired, then the rule's name. It records the last event it handled in the
state file and resumes from it after a restart, so nothing is delivered twice.

--state PATH        The notifier's own state file.
--service URL       The service's address (default: http://127.0.0.1:8080).
--output PATH       Append the lines to this file (default: standard output).
--include-detail    Add the device and the event to each line. Off by default, so a line
                    carries only the rule's name and the time.

The token is read from the INSTEON_PLUGIN_TOKEN environment variable. A read client is enough.
Progress goes to standard error and never includes the token.
"""

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(2)
}

struct Options {
  var service = "http://127.0.0.1:8080", statePath: String?, outputPath: String?, includesDetail = false

  init(_ words: [String]) {
    var arguments = words.makeIterator()
    while let argument = arguments.next() {
      switch argument {
      case "--help": print(help); exit(0)
      case "--include-detail": includesDetail = true
      case "--state", "--service", "--output":
        guard let value = arguments.next() else { fail("\(argument) needs a value.\n\n" + help) }
        switch argument {
        case "--state": statePath = value
        case "--service": service = value
        default: outputPath = value
        }
      default: fail(help)
      }
    }
  }
}

let options = Options(Array(CommandLine.arguments.dropFirst()))
let service = options.service, outputPath = options.outputPath, includesDetail = options.includesDetail
guard let statePath = options.statePath else { fail(help) }
guard let url = URL(string: service), url.scheme == "http" || url.scheme == "https", url.host != nil else { fail("--service must be an http or https address.") }
guard let token = ProcessInfo.processInfo.environment["INSTEON_PLUGIN_TOKEN"], !token.isEmpty else {
  fail("Set INSTEON_PLUGIN_TOKEN to a read client's token.")
}

func note(_ report: NotifierReport) {
  let text: String
  switch report {
  case .connected: text = "following the service's events"
  case let .delivered(id): text = "delivered \(id)"
  case let .deliveryFailed(id, attempt): text = "delivery of \(id) failed (attempt \(attempt)); retrying"
  case .disconnected: text = "disconnected; reconnecting"
  case let .gap(rules): text = "notifications may have been missed and can't be replayed" + (rules.map { " (the service holds \($0) rules)" } ?? "")
  }
  FileHandle.standardError.write(Data((text + "\n").utf8))
}

let notifier = Notifier(
  source: ServiceEventSource(service: ServiceClient(baseURL: url, token: token)),
  deliverer: outputPath.map { LineDeliverer.appending(to: URL(fileURLWithPath: $0)) } ?? .standardOutput,
  state: FileNotifierState(url: URL(fileURLWithPath: statePath)),
  includesDetail: includesDetail,
  report: note
)
let status: Int32 = await withTaskGroup(of: Int32.self) { group in
  group.addTask {
    do {
      try await notifier.run()
      return 0
    } catch is CancellationError {
      return 0
    } catch {
      FileHandle.standardError.write(Data("The notifier stopped: \(error)\n".utf8))
      return 1
    }
  }
  group.addTask {
    await TerminationSignal.received()
    return 0
  }
  let first = await group.next() ?? 1
  group.cancelAll()
  while await group.next() != nil {}
  return first
}
exit(status)
