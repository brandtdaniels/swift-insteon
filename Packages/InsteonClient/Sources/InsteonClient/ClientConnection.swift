import InsteonService

/// One connection to a service, over whichever of its paths answers first.
///
/// It tries its paths in order, keeps the one that opens, and gives the same calls whichever it
/// is, so a person on the local network and a person away use it the same way.
///
/// A call walks the paths, each at most once. A read that loses its path is asked once more on the
/// same path before the path is dropped, since one lost answer says little about it. A command that
/// may have been sent is never asked again: it throws ``ConnectionError/interrupted(path:)``, the
/// path is dropped, and the next call opens one afresh. A path that can prove nothing was sent, one
/// that refused the credential and one whose credential has too low a scope are passed over for both
/// kinds of call, since nothing was done. The error says what happened on the paths: a loss, then a
/// scope that is too low, then a refusal on every path that was tried, then the reasons paths were
/// not reached. The calls of every path the connection stops using are closed.
public actor ClientConnection: DeviceQuerying, DeviceCommanding {

  private let paths: [any ConnectionPath]
  private let skipped: [PathFailure]
  private var open: (index: Int, generation: Int, calls: any ConnectionCalls)?
  private var generations = 0
  nonisolated let retryDelays: [Duration]
  nonisolated let clock: any Clock<Duration>

  /// The name of the path in use, or `nil` before the first call and after a path is lost.
  public var currentPath: String? { open.map { paths[$0.index].name } }

  /// Creates a connection over paths, the most preferred first.
  ///
  /// - Parameters:
  ///   - paths: The paths to try.
  ///   - skipped: Routes that were left out and why, reported when no path is reached.
  ///   - retryDelays: How long events wait before each reconnect after a loss, the first for the
  ///     first loss and each later one for the next failure in a row. The last repeats. An event
  ///     restores the first.
  ///   - clock: Times those waits. A test passes one it controls.
  public init(
    paths: [any ConnectionPath],
    skipped: [PathFailure] = [],
    retryDelays: [Duration] = [.seconds(1), .seconds(2), .seconds(5), .seconds(10), .seconds(30)],
    clock: any Clock<Duration> = ContinuousClock()
  ) {
    self.paths = paths
    self.skipped = skipped
    self.retryDelays = retryDelays.isEmpty ? [.seconds(1)] : retryDelays
    self.clock = clock
  }

  /// The service's numbered events, resuming after `cursor`, kept across lost paths.
  ///
  /// The subscription goes through the path in use. When it is lost, the connection waits, reaches
  /// a path again through the ordered paths, and resumes after the last cursor the client saw. A
  /// ``SequencedItem/gap(_:current:)`` means the service can't replay what was missed: refresh what
  /// is displayed. Reading ends when the reading task is canceled, or by throwing a
  /// ``ConnectionError`` when every path refuses the credential or its scope is too low.
  ///
  /// - Parameter cursor: The last position the client saw, or `nil` to start at the present.
  public nonisolated func sequencedEvents(after cursor: EventCursor? = nil) -> ConnectionEvents {
    ConnectionEvents(connection: self, start: cursor)
  }

  /// The service's events, kept across lost paths, without the numbering. A
  /// ``ClientEvent/refresh(_:)`` says the client missed events: refresh what is displayed.
  public nonisolated func events() -> ClientEvents {
    ClientEvents(base: sequencedEvents(after: nil))
  }

  /// Subscribes through the path in use, or the first that opens.
  func subscribe(after cursor: EventCursor?) async throws -> (events: SequencedEvents, generation: Int) {
    let (events, generation) = try await performTagged(retryable: true) { try await $0.sequencedEvents(after: cursor) }
    return (events, generation)
  }

  /// Drops the path a subscription was on, if it is still the one in use.
  func lost(_ generation: Int) async { await drop(generation) }

  public func devices() async throws -> [ServiceDevice] {
    try await perform(retryable: true) { try await $0.devices() }
  }

  public func execute(_ command: ServiceCommand) async throws -> CommandReceipt {
    try await perform(retryable: false) { try await $0.execute(command) }
  }

  /// Closes the calls of the open path. The next call opens a path afresh.
  public func close() async {
    guard let old = open else { return }
    open = nil
    await old.calls.close()
  }

  /// What a call learned from the paths it tried.
  private struct Tally {
    var reasons: [PathFailure]
    var refused: [String] = []
    var unreachable = 0
    var unsupported: [String] = []
    var pathCount = 0
    var forbidden: ConnectionError?
    var lost: ConnectionError?

    /// The error for a call no path answered.
    var error: ConnectionError {
      if let lost { return lost }
      if let forbidden { return forbidden }
      if !refused.isEmpty, unreachable == 0 { return .unauthorized(paths: refused) }
      if !unsupported.isEmpty, unsupported.count == pathCount { return .unsupported(paths: unsupported) }
      return .noPathReached(reasons)
    }
  }

  /// Runs one call on the paths in order, each at most once.
  private func perform<Answer: Sendable>(retryable: Bool, _ operation: (any ConnectionCalls) async throws -> Answer) async throws -> Answer {
    try await performTagged(retryable: retryable, operation).0
  }

  /// Runs one call on the paths in order, each at most once, and says which opening answered.
  private func performTagged<Answer: Sendable>(retryable: Bool, _ operation: (any ConnectionCalls) async throws -> Answer) async throws -> (Answer, Int) {
    var tally = Tally(reasons: skipped)
    tally.pathCount = paths.count
    var passedOver: Set<Int> = []
    while let (index, generation, calls) = try await reach(passingOver: passedOver, tally: &tally) {
      passedOver.insert(index)
      let name = paths[index].name
      var attempts = retryable ? 2 : 1
      attempt: while attempts > 0 {
        attempts -= 1
        do {
          return (try await operation(calls), generation)
        } catch ConnectionPathError.notReached(let reason) {
          await drop(generation)
          tally.reasons.append(PathFailure(path: name, reason: reason))
          tally.unreachable += 1
          break attempt
        } catch ConnectionPathError.unauthorized {
          await drop(generation)
          tally.refused.append(name)
          tally.reasons.append(PathFailure(path: name, reason: "the credential was refused"))
          break attempt
        } catch ConnectionPathError.unsupported {
          // The path stays open for the calls it does carry.
          tally.reasons.append(PathFailure(path: name, reason: "the path doesn't carry this call"))
          tally.unsupported.append(name)
          tally.unreachable += 1
          break attempt
        } catch ConnectionPathError.forbidden {
          // The credential is good and the path is kept; another path may allow the call.
          tally.forbidden = .forbidden(path: name)
          break attempt
        } catch ConnectionPathError.interrupted {
          // A read is asked once more on a path that is still the open one; a command never.
          if attempts > 0, open?.generation == generation { continue attempt }
          await drop(generation)
          guard retryable else { throw ConnectionError.interrupted(path: name) }
          tally.lost = .interrupted(path: name)
          break attempt
        } catch ConnectionPathError.badResponse {
          await drop(generation)
          guard retryable else { throw ConnectionError.badResponse(path: name) }
          tally.lost = .badResponse(path: name)
          break attempt
        }
      }
    }
    throw tally.error
  }

  /// Drops the open path and closes its calls, if it is still the one a call used: another call may
  /// have replaced it since.
  private func drop(_ generation: Int) async {
    guard let old = open, old.generation == generation else { return }
    open = nil
    await old.calls.close()
  }

  /// The path in use, or the first that opens, leaving out paths this call has used. Returns `nil`
  /// when none is left.
  private func reach(passingOver passedOver: Set<Int>, tally: inout Tally) async throws -> (index: Int, generation: Int, calls: any ConnectionCalls)? {
    if let open, !passedOver.contains(open.index) { return open }
    for index in paths.indices where !passedOver.contains(index) {
      let path = paths[index]
      do {
        let calls = try await path.open()
        if let open, !passedOver.contains(open.index) {
          // Another call opened a path while this one did; keep that one and release this.
          await calls.close()
          return open
        }
        // A kept path that a call passed over is replaced: release it.
        if let old = open { await old.calls.close() }
        generations += 1
        open = (index, generations, calls)
        return (index, generations, calls)
      } catch ConnectionPathError.notReached(let reason) {
        tally.reasons.append(PathFailure(path: path.name, reason: reason))
        tally.unreachable += 1
      } catch ConnectionPathError.forbidden {
        tally.forbidden = tally.forbidden ?? .forbidden(path: path.name)
        tally.reasons.append(PathFailure(path: path.name, reason: "the credential's scope is too low for this path"))
      } catch ConnectionPathError.badResponse {
        tally.reasons.append(PathFailure(path: path.name, reason: "the path answered with something that isn't the service"))
        tally.unreachable += 1
      } catch ConnectionPathError.unauthorized {
        // A refusal on one path says nothing about another: each uses its own credential.
        tally.refused.append(path.name)
        tally.reasons.append(PathFailure(path: path.name, reason: "the credential was refused"))
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        // A path of another kind may fail in any way; it is that path's failure, not the search's.
        tally.reasons.append(PathFailure(path: path.name, reason: "the path failed to open"))
        tally.unreachable += 1
      }
    }
    return nil
  }

}
