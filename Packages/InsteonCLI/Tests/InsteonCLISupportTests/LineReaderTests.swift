import Foundation
import Testing
import InsteonCLISupport

/// Lines a test hands out one at a time, to reads that block until it does.
final class ScriptedInput: @unchecked Sendable {

  private let ready = DispatchSemaphore(value: 0)

  private let lock = NSLock()

  private var lines: [String]

  private var started = 0

  init(_ lines: [String]) {

    self.lines = lines

  }

  /// How many reads have started.
  var reads: Int {

    lock.withLock { started }

  }

  /// Reads the next line once the test hands it out.
  func read() -> String? {

    lock.withLock { started += 1 }
    ready.wait()

    return lock.withLock { lines.isEmpty ? nil : lines.removeFirst() }

  }

  /// Lets one read return its line.
  func handOut() {

    ready.signal()

  }

}

struct LineReaderTests {

  // A prompt canceled while its line is being read leaves the read going, and the next
  // prompt gets the line, rather than a second read starting and the first one taking it.
  @Test(.timeLimit(.minutes(1)))
  func handsALineACanceledPromptLeftBehindToTheNextPrompt() async throws {

    let input = ScriptedInput(["yes"])
    let reader = LineReader { () -> String? in input.read() }

    let first = Task { () async throws -> String? in try await reader.line() }

    while !reader.hasWaiter {

      await Task.yield()

    }

    first.cancel()

    await #expect(throws: CancellationError.self) {

      _ = try await first.value

    }

    let second = Task { () async throws -> String? in try await reader.line() }

    while !reader.hasWaiter {

      await Task.yield()

    }

    input.handOut()

    #expect(try await second.value == "yes")
    #expect(input.reads == 1)

  }

  @Test(.timeLimit(.minutes(1)))
  func readsLinesInOrderAndTheEndOfInput() async throws {

    let input = ScriptedInput(["first", "second"])
    let reader = LineReader { () -> String? in input.read() }

    for expected in ["first", "second", nil] as [String?] {

      input.handOut()

      #expect(try await reader.line() == expected)

    }

  }

}
