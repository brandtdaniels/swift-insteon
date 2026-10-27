import Testing
import InsteonModem

struct TurnQueueTests {

  @Test func handsTurnsOutInOrder() async throws {

    var turns = TurnQueue()

    let taken = turns.request()
    let first = try #require(turns.request())
    let second = try #require(turns.request())

    #expect(taken == nil)

    turns.release()
    for await _ in first.handoff {}
    #expect(turns.settle(first))

    turns.release()
    for await _ in second.handoff {}
    #expect(turns.settle(second))

    turns.release()
    let free = turns.request()
    #expect(free == nil)

  }

  @Test func aCanceledWaiterLeavesTheQueue() throws {

    var turns = TurnQueue()

    _ = turns.request()
    let waiter = try #require(turns.request())

    // The waiter's wait ended without a handoff, as it does when its task is canceled.
    #expect(!turns.settle(waiter))

    // The turn comes free rather than going to the canceled waiter.
    turns.release()
    let free = turns.request()
    #expect(free == nil)

  }

}
