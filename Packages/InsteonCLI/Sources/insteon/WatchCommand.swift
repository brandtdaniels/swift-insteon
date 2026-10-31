import Foundation
import InsteonCLISupport
import InsteonCore

/// `insteon watch`: prints what the modem hears until Control-C, as the network's
/// `DeviceMonitor` reads it.
enum WatchCommand {

  static func run(_ options: WatchOptions, network: DeviceNetwork) async {

    let changes: AsyncStream<DeviceMonitorEvent> = await network.monitor.changes(includingRaw: options.printsRawReplies)
    let timeFormatter = DateFormatter()
    timeFormatter.locale = Locale(identifier: "en_US_POSIX")
    timeFormatter.dateFormat = "HH:mm:ss"

    for line in WatchText.startHint {

      Output.note(line)

    }

    // The stream finishes when Control-C cancels this task, or when the modem closes.
    for await event in changes {

      Output.line("\(timeFormatter.string(from: Date()))  \(WatchText.line(for: event))")

    }

  }

}
