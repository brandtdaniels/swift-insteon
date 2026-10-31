/// Takes turns for a network's links and unlinks, so one runs at a time, in the order they
/// asked.
///
/// A link spans many suspensions, such as waiting for the modem's report, so an actor's
/// isolation alone doesn't keep a second link from starting while the first waits. A caller
/// waits in ``LinkingTurns/begin()`` until the turn before it ends with
/// ``LinkingTurns/end()``. A caller canceled while it waits stops waiting, and its turn is
/// never taken.
actor LinkingTurns {

  /// A caller waiting for its turn.
  private struct Waiter {

    let ticket: Int

    let continuation: CheckedContinuation<Void, any Error>

  }

  /// Whether a turn is being taken.
  private var isTaken: Bool = false

  /// The callers waiting, in the order they asked.
  private var waiters: [Waiter] = []

  /// The tickets of callers canceled before they started waiting.
  private var canceledTickets: Set<Int> = []

  private var nextTicket: Int = 0

  /// How many callers are waiting for their turn. Tests read it to know a caller waits.
  var waitingCount: Int {

    waiters.count

  }

  /// Waits for the caller's turn and takes it. Call ``LinkingTurns/end()`` once the turn is
  /// over, however it ends.
  ///
  /// - Throws: `CancellationError` if the task is canceled while it waits; the turn isn't
  ///   taken then.
  func begin() async throws {

    guard isTaken else {

      isTaken = true

      return

    }

    let ticket: Int = nextTicket

    nextTicket += 1

    try await withTaskCancellationHandler {

      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) -> Void in

        if canceledTickets.remove(ticket) != nil {

          continuation.resume(throwing: CancellationError())

        } else {

          waiters.append(Waiter(ticket: ticket, continuation: continuation))

        }

      }

    } onCancel: {

      Task { () async -> Void in

        await self.cancel(ticket)

      }

    }

  }

  /// Ends the turn, and hands it to the next caller waiting, if any.
  func end() {

    guard !waiters.isEmpty else {

      isTaken = false

      return

    }

    // The turn passes straight to the next caller, so it stays taken.
    waiters.removeFirst().continuation.resume()

  }

  /// Stops a canceled caller from waiting, or keeps it from starting to wait.
  private func cancel(_ ticket: Int) {

    guard let index = waiters.firstIndex(where: { (waiter: Waiter) -> Bool in waiter.ticket == ticket }) else {

      // The caller either hasn't started waiting yet or already has its turn; once it has
      // its turn, its work sees the cancellation itself.
      canceledTickets.insert(ticket)

      return

    }

    waiters.remove(at: index).continuation.resume(throwing: CancellationError())

  }

}
