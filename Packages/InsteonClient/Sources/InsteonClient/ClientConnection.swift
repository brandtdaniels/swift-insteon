import InsteonService

/// One connection to a service, over whichever of its paths answers first.
///
/// It tries its paths in order, keeps the one that opens, and gives the same calls whichever it
/// is, so a person on the local network and a person away use it the same way.
///
/// A read that loses its path is asked again once, on the paths tried afresh with the one that
/// just failed last. A command that may have been sent is never asked again: it throws
/// ``ConnectionError/interrupted(path:)``, the path is dropped, and the next call opens one afresh. A
/// command that was never sent, because its path couldn't be reached, moves on to the next path.
/// A refused credential throws ``ConnectionError/unauthorized(paths:)`` and drops the path.
public actor ClientConnection: DeviceQuerying, DeviceCommanding {

  private let paths: [any ConnectionPath]
  private let skipped: [PathFailure]
  private var open: (index: Int, generation: Int, calls: any ConnectionCalls)?
  private var generations = 0

  /// The name of the path in use, or `nil` before the first call and after a path is lost.
  public var currentPath: String? { open.map { paths[$0.index].name } }

  /// Creates a connection over paths, the most preferred first.
  ///
  /// - Parameters:
  ///   - paths: The paths to try.
  ///   - skipped: Routes that were left out and why, reported when no path is reached.
  public init(paths: [any ConnectionPath], skipped: [PathFailure] = []) {
    self.paths = paths
    self.skipped = skipped
  }

  public func devices() async throws -> [ServiceDevice] {
    try await perform(retryable: true) { try await $0.devices() }
  }

  public func execute(_ command: ServiceCommand) async throws -> CommandReceipt {
    try await perform(retryable: false) { try await $0.execute(command) }
  }

  /// Runs one call, and once more on another path when the first attempt didn't get an answer.
  ///
  /// A path that can prove nothing was sent (`notReached`) or whose credential has too low a scope
  /// (`forbidden`) is passed over for both kinds of call, since nothing was done. A path that was
  /// lost or answered wrongly after the request may have been sent is passed over only for a read,
  /// which is safe to ask again; a command is reported instead and never repeated.
  private func perform<Answer: Sendable>(retryable: Bool, _ operation: (any ConnectionCalls) async throws -> Answer) async throws -> Answer {
    var failed: Int?
    var reasons = skipped
    var last: ConnectionError?
    for _ in 0..<2 {
      let (index, generation, calls) = try await reach(lastFailed: failed)
      do {
        return try await operation(calls)
      } catch ConnectionPathError.notReached(let reason) {
        if open?.generation == generation { open = nil }
        reasons.append(PathFailure(path: paths[index].name, reason: reason))
      } catch {
        let loss = try lose(error, at: index, generation: generation)
        switch loss {
        case .forbidden: last = loss
        case .interrupted where retryable, .badResponse where retryable: last = loss
        default: throw loss
        }
      }
      failed = index
    }
    throw last ?? ConnectionError.noPathReached(reasons)
  }

  /// Drops the open path and names what was lost, or rethrows an error that isn't the path's.
  private func lose(_ error: any Error, at index: Int, generation: Int) throws -> ConnectionError {
    let name = paths[index].name
    // Only the path this call used may be dropped: another call may have replaced it since.
    func drop() { if open?.generation == generation { open = nil } }
    switch error {
    case ConnectionPathError.interrupted, ConnectionPathError.notReached:
      drop()
      return .interrupted(path: name)
    case ConnectionPathError.unauthorized:
      drop()
      return .unauthorized(paths: [name])
    case ConnectionPathError.badResponse:
      drop()
      return .badResponse(path: name)
    case ConnectionPathError.forbidden:
      return .forbidden(path: name)
    default:
      throw error
    }
  }

  /// The path in use, or the first that opens, trying the path that just failed last.
  private func reach(lastFailed: Int?) async throws -> (index: Int, generation: Int, calls: any ConnectionCalls) {
    if let open, open.index != lastFailed { return open }
    var failures = skipped
    var refusals: [String] = []
    var tried = 0
    let order = paths.indices.filter { $0 != lastFailed } + (lastFailed.map { [$0] } ?? [])
    for index in order {
      let path = paths[index]
      tried += 1
      do {
        let calls = try await path.open()
        // A call that was waiting on another opening may have set it already.
        if let open, open.index != lastFailed {
          // Another call opened a path while this one did; keep that one and release this.
          await calls.close()
          return open
        }
        generations += 1
        open = (index, generations, calls)
        return (index, generations, calls)
      } catch ConnectionPathError.notReached(let reason) {
        failures.append(PathFailure(path: path.name, reason: reason))
      } catch ConnectionPathError.forbidden {
        failures.append(PathFailure(path: path.name, reason: "the credential's scope is too low for this path"))
      } catch ConnectionPathError.badResponse {
        failures.append(PathFailure(path: path.name, reason: "the path answered with something that isn't the service"))
      } catch ConnectionPathError.unauthorized {
        // A refusal on one path says nothing about another: each uses its own credential.
        refusals.append(path.name)
        failures.append(PathFailure(path: path.name, reason: "the credential was refused"))
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        // A path of another kind may fail in any way; it is that path's failure, not the search's.
        failures.append(PathFailure(path: path.name, reason: "the path failed to open"))
      }
    }
    if tried > 0, refusals.count == tried { throw ConnectionError.unauthorized(paths: refusals) }
    throw ConnectionError.noPathReached(failures)
  }

}
