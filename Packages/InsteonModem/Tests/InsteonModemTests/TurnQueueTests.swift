import Testing
import InsteonModem

// `#expect` and `#require` can't call mutating methods, so each call to the queue is made first.
struct TurnQueueTests {

  @Test func handsTurnsOutInOrder() async throws {

    var turns = TurnQueue()

    let tookTheTurn = turns.request() == nil
    let firstTicket = turns.request()
    let secondTicket = turns.request()

    #expect(tookTheTurn)
    let first = try #require(firstTicket)
    let second = try #require(secondTicket)

    turns.release()
    for await _ in first.handoff {}
    let firstHasTurn = turns.settle(first)
    #expect(firstHasTurn)

    turns.release()
    for await _ in second.handoff {}
    let secondHasTurn = turns.settle(second)
    #expect(secondHasTurn)

    turns.release()
    let isFree = turns.request() == nil
    #expect(isFree)

  }

  @Test func aCanceledWaiterLeavesTheQueue() throws {

    var turns = TurnQueue()

    _ = turns.request()
    let waiterTicket = turns.request()
    let waiter = try #require(waiterTicket)

    // The waiter's wait ended without a handoff, as it does when its task is canceled.
    let waiterHasTurn = turns.settle(waiter)
    #expect(!waiterHasTurn)

    // The turn comes free rather than going to the canceled waiter.
    turns.release()
    let isFree = turns.request() == nil
    #expect(isFree)

  }

}
