import InsteonModem
import Logging

/// How the server's log handler is made.
public enum ServerLogging {
  /// The handler the server logs through: standard error, at `level`.
  ///
  /// - Parameters:
  ///   - label: The logger's label.
  ///   - level: The lowest level that is written, from ``ServerOptions/logLevel``.
  public static func handler(label: String, level: Logger.Level) -> any LogHandler {
    var handler = StreamLogHandler.standardError(label: label)
    handler.logLevel = level
    return handler
  }

  /// The level `arguments` and `environment` choose, or `info` when they name none or a bad one.
  /// The bad value is refused with its code when the server's options are read, which happens
  /// after logging starts, so the refusal can be logged.
  ///
  /// - Parameters:
  ///   - arguments: The command line's arguments after the program name.
  ///   - environment: The process's environment.
  public static func level(arguments: [String], environment: [String: String]) -> Logger.Level {
    let option = arguments.firstIndex(of: "--log-level").flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
    return (option ?? environment["INSTEON_LOG_LEVEL"]).flatMap { Logger.Level(rawValue: $0.lowercased()) } ?? .info
  }

  /// `tracer` when `level` is `trace`, else nil, so a server above the trace level hands no
  /// tracer to the Hub or the serial port and they do no work for one.
  ///
  /// - Parameters:
  ///   - tracer: The tracer to use at the trace level.
  ///   - level: The server's log level.
  public static func gate(_ tracer: some WireTrace, level: Logger.Level) -> (any WireTrace)? {
    level <= .trace ? tracer : nil
  }

  /// The tracer that logs the wire's traffic at the trace level, or nil at any other level.
  ///
  /// - Parameters:
  ///   - level: The server's log level, from ``ServerOptions/logLevel``.
  ///   - logger: Where each line is logged, at trace level.
  ///   - maskAddresses: Whether Insteon addresses are shown as short tags, which is the default
  ///     unless ``ServerOptions/traceAddresses``.
  public static func wireTrace(level: Logger.Level, logger: Logger, maskAddresses: Bool) -> (any WireTrace)? {
    level <= .trace ? WireTraceLogger(logger: logger, maskAddresses: maskAddresses) : nil
  }
}
