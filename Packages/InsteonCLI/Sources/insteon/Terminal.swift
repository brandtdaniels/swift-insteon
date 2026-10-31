import Foundation
import InsteonCLISupport
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Reads from the person at the terminal.
enum Terminal {

  /// Whether standard input is a terminal, so the command can wait for Return.
  static var readsFromTerminal: Bool {

    isatty(STDIN_FILENO) == 1

  }

  /// Waits for the person to press Return, or for the task to be canceled, such as by
  /// Control-C.
  ///
  /// What was typed before the wait, such as a Return pressed while the command connected to
  /// the modem or read its ALL-Link database, is discarded first, so only a Return pressed
  /// after the instructions ends the wait.
  ///
  /// The line is read on a thread of its own, so the wait doesn't hold up the tasks that keep
  /// the modem running. A read that a canceled wait leaves behind hands its line to the next
  /// wait, rather than taking it.
  ///
  /// - Throws: `CancellationError` if the task was canceled while waiting.
  static func waitForReturn() async throws {

    discardTypedAhead()

    _ = try await lines.line()

  }

  /// Standard input's lines, read one at a time for whichever prompt waits.
  private static let lines = LineReader { () -> String? in readLine() }

  /// Discards what the terminal has received but the command hasn't read yet.
  private static func discardTypedAhead() {

    if readsFromTerminal {

      _ = tcflush(STDIN_FILENO, TCIFLUSH)

    }

  }

  /// Asks the person a yes-or-no question on standard error, and waits for the answer.
  ///
  /// Only `y` or `yes`, in either case, is yes; anything else, an empty line or the end of
  /// input is no.
  ///
  /// - Parameter question: The question, ending with its choices, such as `[y/N]`.
  /// - Returns: Whether the person answered yes.
  /// - Throws: `CancellationError` if the task was canceled while waiting.
  static func confirm(_ question: String) async throws -> Bool {

    Output.prompt(question)

    let line: String? = try await lines.line()

    let text: String = (line ?? "").trimmingCharacters(in: .whitespaces).lowercased()

    return text == "y" || text == "yes"

  }

}
