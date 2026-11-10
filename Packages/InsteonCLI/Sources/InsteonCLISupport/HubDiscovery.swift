import InsteonCore

/// How `insteon discover` looks for Hubs: which ways it asks, in what order, what it says
/// about each, and when finding nothing is a failure.
public enum HubDiscovery {

  /// Looks for Hubs the ways the options ask for: Insteon Connect first, then the local
  /// network, merging the Hubs each finds.
  ///
  /// A way that fails is noted, and the other's Hubs are still reported; the search fails
  /// only when every way it asked failed, with the last error. When the local network finds
  /// nothing and Insteon Connect wasn't asked, the note suggests it. Cancellation of the local
  /// search stops the command.
  ///
  /// - Parameters:
  ///   - options: The command's options.
  ///   - insteonConnect: Asks Insteon Connect for the Hubs that reported from this network.
  ///   - localNetwork: Searches the local network, stopping at the first Hub when its
  ///     argument is `true`.
  ///   - merge: Adds a Hub to those found, merging it with one already there, as
  ///     `HubSearch.merge(_:into:)` does.
  ///   - note: Prints a note on standard error.
  ///   - message: Describes an error.
  /// - Returns: The Hubs found.
  /// - Throws: The last error when every way failed, or `CancellationError`.
  public static func search<Hub>(
    _ options: DiscoverOptions,
    insteonConnect: () async throws -> [Hub],
    localNetwork: (_ stoppingAtFirst: Bool) async throws -> [Hub],
    merge: (Hub, inout [Hub]) -> Void,
    note: (String) -> Void,
    message: (any Error) -> String
  ) async throws -> [Hub] {

    var hubs: [Hub] = []
    var failures: [any Error] = []

    if options.asksInsteonConnect {

      note("Asking Insteon Connect...")

      do {

        for hub in try await insteonConnect() {

          merge(hub, &hubs)

        }

      } catch {

        note("Insteon Connect: \(message(error))")
        failures.append(error)

      }

    }

    if options.searchesLocalNetwork {

      do {

        let found: [Hub] = try await localNetwork(!options.searchesAllAddresses)

        for hub in found {

          merge(hub, &hubs)

        }

        // Insteon Connect sees the network's public IP address, so it's only suggested.
        if found.isEmpty, !options.asksInsteonConnect {

          note(
            "No Hub answered on the local network. 'insteon discover --insteon-connect' asks Insteon Connect "
              + "for the Hubs that reported from this network, which shares the network's public IP address with Insteon."
          )

        }

      } catch let error as CancellationError {

        throw error

      } catch {

        note("Local network: \(message(error))")
        failures.append(error)

      }

    }

    // Fail only when every way of looking failed, rather than reporting no Hubs.
    let ways: Int = (options.asksInsteonConnect ? 1 : 0) + (options.searchesLocalNetwork ? 1 : 0)

    if let failure = failures.last, failures.count == ways {

      throw failure

    }

    return hubs

  }

}
