import Foundation
import Testing
import InsteonCLISupport

/// The writes a test's saver made, from any task.
final class Writes: @unchecked Sendable {

  private let lock = NSLock()

  private var writes: [[Int]] = []

  /// Each write's learned and since values, in order.
  var all: [[Int]] {

    lock.withLock { writes }

  }

  /// Records a write.
  func record(_ learned: Int, since: Int) -> Bool {

    lock.withLock { writes.append([learned, since]) }

    return true

  }

}

struct OrderedSaverTests {

  // A second save asked for while the first is reading waits for it, so it writes what
  // changed since the first, not since the start, and never undoes it.
  @Test(.timeLimit(.minutes(1)))
  func savesOneAtATimeInOrder() async throws {

    let saver = OrderedSaver(saved: 0)
    let writes = Writes()
    let (reached, reachedSignal) = AsyncStream<Void>.makeStream()
    let (gate, opening) = AsyncStream<Void>.makeStream()

    let first = Task { () async -> Void in

      await saver.save(
        reading: { () async -> Int in

          reachedSignal.yield()

          for await _ in gate {

            break

          }

          return 1

        },
        writing: { (learned: Int, since: Int) -> Bool in writes.record(learned, since: since) }
      )

    }

    var reachedRead = reached.makeAsyncIterator()
    _ = await reachedRead.next()

    let second = Task { () async -> Void in

      await saver.save(reading: { () async -> Int in 2 }, writing: { (learned: Int, since: Int) -> Bool in writes.record(learned, since: since) })

    }

    while await saver.requested < 2 {

      await Task.yield()

    }

    // The second save hasn't read or written while the first one waits.
    #expect(writes.all.isEmpty)

    opening.yield()
    await first.value
    await second.value

    #expect(writes.all == [[1, 0], [2, 1]])
    #expect(await saver.lastSaved == 2)

  }

  @Test(.timeLimit(.minutes(1)))
  func writesAgainWhatWasntWritten() async {

    let saver = OrderedSaver(saved: 0)

    await saver.save(reading: { () async -> Int in 1 }, writing: { (_: Int, _: Int) -> Bool in false })

    #expect(await saver.lastSaved == 0)

    await saver.save(reading: { () async -> Int in 2 }, writing: { (_: Int, since: Int) -> Bool in since == 0 })

    #expect(await saver.lastSaved == 2)

  }

}
