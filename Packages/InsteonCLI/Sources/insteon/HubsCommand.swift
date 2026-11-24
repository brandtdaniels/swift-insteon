import Foundation
import InsteonCLISupport

/// `insteon hubs`: lists the Hub files. Needs no modem, and never prints a user name or a
/// password.
enum HubsCommand {

  static func run() throws {

    let files = HubFiles(store: LocalHubFiles(), environment: ProcessInfo.processInfo.environment)

    guard files.hubsDirectory != nil else {

      throw ConfigurationError.noConfigurationDirectory

    }

    let listing = files.listing()
    let rows = HubListText.rows(for: listing)

    if rows.isEmpty {

      Output.line(HubListText.emptyMessage(for: listing))

    } else {

      Output.table(rows)

    }

    for note in HubListText.notes(for: listing) {

      Output.line(note)

    }

  }

}
