/// Hands out exclusive turns in the order they're requested, for an actor that must do one
/// thing at a time, such as sending a command and waiting for its echo.
///
/// Waiting can be canceled: a canceled waiter leaves the queue, or passes the turn on if it was
/// already handed one. Keep the queue in the actor that uses it:
///
/// ```swift
/// if let ticket = turns.request() {
///   for await _ in ticket.handoff {}
///   guard turns.settle(ticket) else { throw CancellationError() }
/// }
///
/// // A task canceled as it was handed the turn passes it on.
/// if Task.isCancelled {
///   turns.release()
///   throw CancellationError()
/// }
///
/// defer { turns.release() }
/// ```
package struct TurnQueue: Sendable {

  /// A place in the queue.
  package struct Ticket: Sendable {

    fileprivate let id: Int

    /// Finishes when the turn is handed to this ticket, or when the waiting task is canceled.
    package let handoff: AsyncStream<Void>

  }

  private var isTaken = false

  private var nextID = 0

  private var waiting: [(id: Int, handoff: AsyncStream<Void>.Continuation)] = []

  private var handed: Set<Int> = []

  /// Creates a queue whose turn is free.
  package init() {}

  /// Takes the turn if it's free, or joins the queue.
  ///
  /// - Returns: `nil` if the caller holds the turn, or a ticket to wait on.
  package mutating func request() -> Ticket? {

    guard isTaken else {

      isTaken = true

      return nil

    }

    let id = nextID
    nextID += 1

    let (handoff, continuation) = AsyncStream<Void>.makeStream()
    waiting.append((id, continuation))

    return Ticket(id: id, handoff: handoff)

  }

  /// Settles a ticket once its handoff finishes.
  ///
  /// - Parameter ticket: The ticket whose wait ended.
  /// - Returns: `true` if the caller holds the turn, or `false` if the wait was canceled
  ///   first, in which case the ticket leaves the queue.
  package mutating func settle(_ ticket: Ticket) -> Bool {

    if handed.remove(ticket.id) != nil {

      return true

    }

    waiting.removeAll { $0.id == ticket.id }

    return false

  }

  /// Ends the current turn and hands it to the longest waiter, if any.
  package mutating func release() {

    guard !waiting.isEmpty else {

      isTaken = false

      return

    }

    let next = waiting.removeFirst()
    handed.insert(next.id)
    next.handoff.finish()

  }

}
