/// Takes turns for a network's links and unlinks, so one runs at a time, in the order they
/// asked.
///
/// A link spans many suspensions, such as waiting for the modem's report, so an actor's
/// isolation alone doesn't keep a second link from starting while the first waits. A caller
/// waits in ``LinkingTurns/begin()`` until the turn before it ends with
/// ``LinkingTurns/end()``. A caller canceled while it waits stops waiting, and its turn is
/// never taken.
///
/// The actor keeps a ticket only while its caller waits or is about to, so a cancellation
/// that arrives after the caller has its turn leaves nothing behind.
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

  /// The tickets of callers that asked for a turn and haven't been given it or stopped
  /// waiting.
  private var openTickets: Set<Int> = []

  /// The tickets of open callers canceled before they started waiting. Always a subset of
  /// the open tickets.
  private var canceledTickets: Set<Int> = []

  private var nextTicket: Int = 0

  /// How many callers are waiting for their turn. Tests read it to know a caller waits.
  var waitingCount: Int {

    waiters.count

  }

  /// How many tickets are open. Tests read it to know nothing is left behind.
  var openTicketCount: Int {

    openTickets.count

  }

  /// How many open tickets were canceled before their callers started waiting. Tests read it
  /// to know nothing is left behind.
  var canceledTicketCount: Int {

    canceledTickets.count

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
    openTickets.insert(ticket)

    try await withTaskCancellationHandler {

      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) -> Void in

        if canceledTickets.remove(ticket) != nil {

          openTickets.remove(ticket)
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
    let next: Waiter = waiters.removeFirst()

    openTickets.remove(next.ticket)
    next.continuation.resume()

  }

  /// Stops a canceled caller from waiting, or keeps it from starting to wait. A caller that
  /// already has its turn sees the cancellation in its own work, so nothing is kept for it.
  ///
  /// - Parameter ticket: The caller's ticket.
  func cancel(_ ticket: Int) {

    if let index = waiters.firstIndex(where: { (waiter: Waiter) -> Bool in waiter.ticket == ticket }) {

      let waiter: Waiter = waiters.remove(at: index)

      openTickets.remove(ticket)
      waiter.continuation.resume(throwing: CancellationError())

      return

    }

    // The caller asked but hasn't started waiting yet, so it's kept from starting.
    if openTickets.contains(ticket) {

      canceledTickets.insert(ticket)

    }

  }

}
