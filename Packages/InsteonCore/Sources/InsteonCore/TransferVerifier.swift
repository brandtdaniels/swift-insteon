import Foundation
import InsteonModem
import InsteonProtocol

/// Whether one device of a backup answered through the connected modem.
public struct TransferDeviceCheck: Hashable, Sendable {

  /// The device's address.
  public var address: InsteonAddress

  /// The device's name in the backup, or `nil`.
  public var name: String?

  /// Whether the device answered.
  public var answered: Bool {

    problem == nil

  }

  /// Why the device didn't answer, or `nil` if it did.
  public var problem: String?

  /// Creates a check.
  ///
  /// - Parameters:
  ///   - address: The device's address.
  ///   - name: The device's name, or `nil`.
  ///   - problem: Why it didn't answer, or `nil` if it did.
  public init(address: InsteonAddress, name: String? = nil, problem: String? = nil) {

    self.address = address
    self.name = name
    self.problem = problem

  }

}

/// Which devices of a backup answered through the connected modem.
public struct TransferVerification: Hashable, Sendable {

  /// Each device of the backup, in the backup's order.
  public var checks: [TransferDeviceCheck]

  /// Whether every device answered.
  public var isComplete: Bool {

    checks.allSatisfy(\.answered)

  }

  /// Creates a verification.
  ///
  /// - Parameter checks: Each device's check.
  public init(checks: [TransferDeviceCheck]) {

    self.checks = checks

  }

}

/// Asks each device of a backup whether it answers through the connected modem, which is how a
/// person sees that a transfer left the home working.
///
/// ```swift
/// let result = try await TransferVerifier.verify(backup) { address in try await network.device(address).ping() }
/// print(result.isComplete)
/// ```
public enum TransferVerifier {

  /// Whether an error is a device's own failure to answer, as a timeout or a rejection is, rather
  /// than the connection's: a modem that errs another way, or a network request that can't
  /// connect, says nothing about the devices.
  ///
  /// - Parameter error: The error a ping threw.
  /// - Returns: `true` if the device didn't answer.
  public static func isDeviceFailure(_ error: any Error) -> Bool {

    if let error = error as? ModemError {

      switch error {
      case .deviceTimedOut, .deviceRejected:
        return true
      default:
        return false
      }

    }

    return !(error is URLError)

  }

  /// Asks each device of the backup, one at a time and in the backup's order.
  ///
  /// - Parameters:
  ///   - backup: The backup whose devices are asked.
  ///   - isDeviceFailure: Whether an error is the device's own failure to answer. Any other error,
  ///     such as a lost connection, ends the run and is thrown, since it says nothing about the
  ///     devices that weren't asked. Defaults to every error being the device's.
  ///   - describing: Says in a sentence why an error means a device didn't answer. Defaults to
  ///     the error's own text.
  ///   - ping: Asks one device to answer, and throws when it doesn't. It must change nothing.
  /// - Returns: Whether each device answered.
  /// - Throws: `CancellationError` if the task was canceled, which isn't a device that didn't
  ///   answer, and any error `isDeviceFailure` says isn't the device's own.
  public static func verify(_ backup: HomeBackup, isDeviceFailure: (any Error) -> Bool = TransferVerifier.isDeviceFailure, describing: (any Error) -> String = { (error: any Error) -> String in "\(error)" }, ping: (InsteonAddress) async throws -> Void) async throws -> TransferVerification {

    var checks: [TransferDeviceCheck] = []

    for device in backup.devices {

      do {

        try await ping(device.address)

        checks.append(TransferDeviceCheck(address: device.address, name: device.name))

      } catch is CancellationError {

        throw CancellationError()

      } catch where !isDeviceFailure(error) {

        throw error

      } catch {

        checks.append(TransferDeviceCheck(address: device.address, name: device.name, problem: describing(error)))

      }

    }

    return TransferVerification(checks: checks)

  }

}
