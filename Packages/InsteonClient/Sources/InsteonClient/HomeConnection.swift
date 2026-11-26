import InsteonService

/// One connection to a home, over whichever of its paths answers first.
///
/// It tries its paths in order, keeps the one that opens, and gives the same calls whichever it
/// is, so a person at home and a person away use it the same way.
///
/// A read that loses its path is asked again once, on the paths tried afresh with the one that
/// just failed last. A command that may have been sent is never asked again: it throws
/// ``HomeError/interrupted(path:)``, the path is dropped, and the next call opens one afresh. A
/// command that was never sent, because its path couldn't be reached, moves on to the next path.
/// A refused credential throws ``HomeError/unauthorized(paths:)`` and drops the path.
public actor HomeConnection: DeviceQuerying, DeviceCommanding {

  private let paths: [any HomePath]
  private let skipped: [PathFailure]
  private var open: (index: Int, generation: Int, calls: any HomeCalls)?
  private var generations = 0

  /// The name of the path in use, or `nil` before the first call and after a path is lost.
  public var currentPath: String? { open.map { paths[$0.index].name } }

  /// Creates a connection over paths, the most preferred first.
  ///
  /// - Parameters:
  ///   - paths: The paths to try.
  ///   - skipped: Routes that were left out and why, reported when no path is reached.
  public init(paths: [any HomePath], skipped: [PathFailure] = []) {
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
  private func perform<Answer: Sendable>(retryable: Bool, _ operation: (any HomeCalls) async throws -> Answer) async throws -> Answer {
    var failed: Int?
    var reasons = skipped
    var last: HomeError?
    for _ in 0..<2 {
      let (index, generation, calls) = try await reach(lastFailed: failed)
      do {
        return try await operation(calls)
      } catch HomePathError.notReached(let reason) {
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
    throw last ?? HomeError.noPathReached(reasons)
  }

  /// Drops the open path and names what was lost, or rethrows an error that isn't the path's.
  private func lose(_ error: any Error, at index: Int, generation: Int) throws -> HomeError {
    let name = paths[index].name
    // Only the path this call used may be dropped: another call may have replaced it since.
    func drop() { if open?.generation == generation { open = nil } }
    switch error {
    case HomePathError.interrupted, HomePathError.notReached:
      drop()
      return .interrupted(path: name)
    case HomePathError.unauthorized:
      drop()
      return .unauthorized(paths: [name])
    case HomePathError.badResponse:
      drop()
      return .badResponse(path: name)
    case HomePathError.forbidden:
      return .forbidden(path: name)
    default:
      throw error
    }
  }

  /// The path in use, or the first that opens, trying the path that just failed last.
  private func reach(lastFailed: Int?) async throws -> (index: Int, generation: Int, calls: any HomeCalls) {
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
      } catch HomePathError.notReached(let reason) {
        failures.append(PathFailure(path: path.name, reason: reason))
      } catch HomePathError.forbidden {
        failures.append(PathFailure(path: path.name, reason: "the credential's scope is too low for this path"))
      } catch HomePathError.badResponse {
        failures.append(PathFailure(path: path.name, reason: "the path answered with something that isn't the service"))
      } catch HomePathError.unauthorized {
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
    if tried > 0, refusals.count == tried { throw HomeError.unauthorized(paths: refusals) }
    throw HomeError.noPathReached(failures)
  }

}
