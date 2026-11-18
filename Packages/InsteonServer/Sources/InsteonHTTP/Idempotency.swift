import Foundation
import HTTPTypes

/// Why a keyed command can't proceed.
enum IdempotencyError: Error, Equatable {
  /// The `Idempotency-Key` header isn't one token of 1 through 128 characters from `A-Z a-z 0-9 . _ ~ : -`.
  case invalidKey
  /// The key was used for a different command.
  case reused
}

/// A client-chosen token that names one command, so a repeat of it can be recognized.
struct IdempotencyKey: Equatable, Sendable {
  static let maximumLength = 128
  private static let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._~:-")

  let value: String

  /// - Parameter header: Every value the request carries for the header.
  /// - Returns: `nil` when the header is absent.
  /// - Throws: ``IdempotencyError/invalidKey`` for more than one value, an empty or long value, or a character outside the set.
  init?(header values: [String]) throws {
    guard !values.isEmpty else { return nil }
    guard values.count == 1, let value = values.first, (1...Self.maximumLength).contains(value.count), value.allSatisfy(Self.allowed.contains) else {
      throw IdempotencyError.invalidKey
    }
    self.value = value
  }
}

/// Who owns a key. Keys of different principals never meet, so one client can't replay another's command.
struct IdempotencyScope: Hashable, Sendable {
  let principal: String
  /// The one principal the gateway's single password authenticates.
  static let gateway = IdempotencyScope(principal: "gateway")
}

/// How many answers the store keeps and for how long.
struct IdempotencyPolicy: Sendable {
  /// The most answers kept; the oldest leaves first.
  let capacity: Int
  /// Seconds an answer is kept after it is recorded.
  let retention: TimeInterval
  /// 256 answers for 10 minutes.
  static let standard = IdempotencyPolicy(capacity: 256, retention: 600)
}

/// What a command produced: the response a client sees, or a failure to report.
enum IdempotentOutcome: Sendable, Equatable {
  case response(HTTPResponse.Status, Data)
  case failure(HTTPFailure)

  /// Whether a repeat should get this outcome instead of running the command again: the command
  /// succeeded, or it may have reached the device. A refusal that sent nothing is never recorded,
  /// because repeating it costs nothing and may succeed once its cause is gone.
  var isRecorded: Bool {
    switch self {
    case .response: true
    case let .failure(failure): failure.sent
    }
  }

  static func == (left: Self, right: Self) -> Bool {
    switch (left, right) {
    case let (.response(leftStatus, leftBody), .response(rightStatus, rightBody)): leftStatus == rightStatus && leftBody == rightBody
    case let (.failure(left), .failure(right)): left.code == right.code && left.sent == right.sent
    default: false
    }
  }
}

/// A recorded or running command's failure, thrown so the error pipeline answers it, with the
/// `Idempotent-Replay` header when it repeats an earlier answer.
struct OutcomeFailure: Error {
  let failure: HTTPFailure
  let replayed: Bool
}

/// Remembers the outcome of keyed commands, in bounded memory, so a client that lost a response can repeat
/// the command and get the same answer without the command being sent again.
///
/// A key is recorded only after its command finishes, and only when ``IdempotentOutcome/isRecorded``.
/// A repeat that arrives while the command runs waits for its outcome and gets it, recorded or not,
/// without sending anything. The store never retries.
actor IdempotencyStore {
  private struct Entry {
    let fingerprint: String
    var state: State
  }
  private enum State {
    case running([CheckedContinuation<IdempotentOutcome, Never>])
    case recorded(IdempotentOutcome, expires: Date)
  }
  private struct Slot: Hashable {
    let scope: IdempotencyScope
    let key: String
  }

  private let policy: IdempotencyPolicy
  private let now: @Sendable () -> Date
  private let onWait: (@Sendable () -> Void)?
  private var entries: [Slot: Entry] = [:]
  /// Recorded slots, oldest first.
  private var order: [Slot] = []

  /// - Parameters:
  ///   - now: The time, read from a clock the caller injects, so expiry is deterministic.
  ///   - onWait: Called when a repeat starts waiting for a running command.
  init(policy: IdempotencyPolicy = .standard, now: @escaping @Sendable () -> Date = { Date() }, onWait: (@Sendable () -> Void)? = nil) {
    self.policy = policy
    self.now = now
    self.onWait = onWait
  }

  /// How many answers are recorded.
  var count: Int { order.count }

  /// Runs `work` once for a key, or answers a repeat.
  ///
  /// - Parameters:
  ///   - fingerprint: Identifies the command; a key used with another fingerprint is reused.
  ///   - work: Runs the command. It doesn't throw: every failure is an outcome.
  /// - Throws: ``IdempotencyError/reused``.
  func perform(scope: IdempotencyScope, key: String, fingerprint: String, _ work: @Sendable () async -> IdempotentOutcome) async throws -> (outcome: IdempotentOutcome, replayed: Bool) {
    let slot = Slot(scope: scope, key: key)
    expire()
    if let entry = entries[slot] {
      guard entry.fingerprint == fingerprint else { throw IdempotencyError.reused }
      switch entry.state {
      case let .recorded(outcome, _):
        return (outcome, true)
      case .running:
        let outcome = await withCheckedContinuation { (continuation: CheckedContinuation<IdempotentOutcome, Never>) in
          if case var .running(waiters) = entries[slot]?.state {
            waiters.append(continuation)
            entries[slot]?.state = .running(waiters)
          } else {
            // The command finished between the check and here; it can't, on one actor, but never strand a caller.
            continuation.resume(returning: .failure(HTTPFailure(.busy)))
          }
          onWait?()
        }
        return (outcome, true)
      }
    }
    entries[slot] = Entry(fingerprint: fingerprint, state: .running([]))
    let outcome = await work()
    var waiters: [CheckedContinuation<IdempotentOutcome, Never>] = []
    if case let .running(parked)? = entries[slot]?.state { waiters = parked }
    if outcome.isRecorded {
      entries[slot]?.state = .recorded(outcome, expires: now().addingTimeInterval(policy.retention))
      order.append(slot)
      evictOverflow()
    } else {
      entries[slot] = nil
    }
    for waiter in waiters { waiter.resume(returning: outcome) }
    return (outcome, false)
  }

  private func expire() {
    let current = now()
    while let oldest = order.first, case let .recorded(_, expires)? = entries[oldest]?.state, expires <= current {
      entries[oldest] = nil
      order.removeFirst()
    }
  }

  private func evictOverflow() {
    while order.count > policy.capacity {
      entries[order.removeFirst()] = nil
    }
  }
}

extension HTTPField.Name {
  /// Marks a response that repeats an earlier answer instead of running the command.
  static let idempotentReplay = HTTPField.Name("Idempotent-Replay")!
  /// Carries the client's key for a command.
  static let idempotencyKey = HTTPField.Name("Idempotency-Key")!
}
