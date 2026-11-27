import InsteonModem
import Foundation
import Logging

/// A ``WireTrace`` that logs each line at the trace level: what crossed the wire, in hex, and how
/// long it was since the last line.
///
/// A line reads `+0.510s hub read end=12 cursor=advanced 02 50 @A1 @B2 CB 11 00`. A Hub's buffer
/// read also says `gap=` how long it was since the read before it. Addresses are shown as tags
/// unless masking is off.
public final class WireTraceLogger: WireTrace, Sendable {

  private let logger: Logger

  private let maskAddresses: Bool

  // `lock` guards `state`; the state is `nonisolated(unsafe)` for that reason alone.
  private let lock = NSLock()

  nonisolated(unsafe) private var state: State

  private struct State {
    var masker: AddressMasker
    var previous: ContinuousClock.Instant
    var previousRead: ContinuousClock.Instant?
    /// The quiet reads since the last one that was logged, which aren't logged one by one.
    var quiet: QuietReads?
  }

  /// Reads that brought nothing, after the first of them was logged.
  private struct QuietReads {
    /// The first quiet read's instant, which starts the time the summary reports.
    var since: ContinuousClock.Instant
    var last: ContinuousClock.Instant
    var count = 0
  }

  /// How long quiet reads go unsummarized at most: 30 seconds.
  static let summaryInterval: Duration = .seconds(30)

  /// Creates a tracer.
  ///
  /// - Parameters:
  ///   - logger: Where lines are logged, at the trace level.
  ///   - maskAddresses: Whether to show addresses as short tags.
  ///   - salt: Seeds the tags. Defaults to a random one, so each run's tags differ.
  ///   - start: The instant the first line's time is counted from. Defaults to the instant the tracer is made.
  public init(logger: Logger, maskAddresses: Bool, salt: UInt64 = .random(in: .min ... .max), start: ContinuousClock.Instant = .now) {

    self.logger = logger
    self.maskAddresses = maskAddresses
    state = State(masker: AddressMasker(salt: salt), previous: start)

  }

  /// Logs the bytes.
  public func trace(_ direction: WireTraceDirection, _ bytes: [UInt8], at instant: ContinuousClock.Instant) {

    let lines: [String] = lock.withLock {

      var lines: [String] = []

      // A quiet read after a change is logged once; the ones after it are counted.
      if case let .hubBuffer(_, step) = direction, step == .unchanged {

        let gap = state.previousRead.map { " gap=\(Self.seconds(instant - $0))" } ?? ""
        let first = state.quiet == nil
        state.previousRead = instant

        if first {

          state.quiet = QuietReads(since: instant, last: instant)
          lines.append("+\(Self.seconds(instant - state.previous)) hub read end=\(endIndexText(direction)) cursor=unchanged\(gap)")
          state.previous = instant

        } else {

          state.quiet?.count += 1
          state.quiet?.last = instant

          if let quiet = state.quiet, instant - quiet.since >= Self.summaryInterval {

            lines.append(summary(quiet))
            state.previous = instant
            state.quiet = QuietReads(since: instant, last: instant)

          }

        }

        return lines

      }

      // Anything else ends a quiet stretch, so its summary comes first.
      if let quiet = state.quiet {

        if quiet.count > 0 {

          lines.append(summary(quiet))
          state.previous = quiet.last

        }

        state.quiet = nil

      }

      let elapsed = Self.seconds(instant - state.previous)
      state.previous = instant

      let text: String
      let label: String
      switch direction {
      case .written:
        label = "serial write"
        text = render(bytes, in: .outbound)
      case .received:
        label = "serial read"
        text = render(bytes, in: .inbound)
      case let .hubRequest(path):
        label = "hub request \(path)"
        text = render(bytes, in: .outbound)
      case let .hubBuffer(endIndex, step):
        var gap = ""
        if let previousRead = state.previousRead { gap = " gap=\(Self.seconds(instant - previousRead))" }
        state.previousRead = instant
        // A cleared buffer starts the next frame over.
        if step == .cleared || step == .refilled { state.masker.resetInbound() }
        label = "hub read end=\(endIndex) cursor=\(step)\(gap)"
        text = render(bytes, in: .inbound)
      }

      lines.append("+\(elapsed) \(label)" + (text.isEmpty ? "" : " " + text))

      return lines

    }

    for line in lines { logger.trace("\(line)") }

  }

  /// The summary line of a quiet stretch, timed to its last read, which the state's `previous` must then follow.
  private func summary(_ quiet: QuietReads) -> String {

    "+\(Self.seconds(quiet.last - state.previous)) hub read unchanged x\(quiet.count) for \(Self.seconds(quiet.last - quiet.since))"

  }

  private func endIndexText(_ direction: WireTraceDirection) -> String {

    if case let .hubBuffer(endIndex, _) = direction { "\(endIndex)" } else { "" }

  }

  private func render(_ bytes: [UInt8], in stream: AddressMasker.Stream) -> String {

    maskAddresses ? state.masker.mask(bytes, in: stream) : bytes.map { Self.hex($0) }.joined(separator: " ")

  }

  static func hex(_ byte: UInt8) -> String {

    let digits = String(byte, radix: 16, uppercase: true)

    return digits.count == 1 ? "0" + digits : digits

  }

  /// Seconds with three decimals, such as `0.510s`.
  private static func seconds(_ duration: Duration) -> String {

    let milliseconds = max(0, Int(duration.components.seconds) * 1000 + Int(duration.components.attoseconds / 1_000_000_000_000_000))

    return "\(milliseconds / 1000).\(String(format: "%03d", milliseconds % 1000))s"

  }

}
