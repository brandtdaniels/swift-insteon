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

  /// Asks each device of the backup, one at a time and in the backup's order.
  ///
  /// - Parameters:
  ///   - backup: The backup whose devices are asked.
  ///   - ping: Asks one device to answer, and throws when it doesn't. It must change nothing.
  /// - Returns: Whether each device answered.
  /// - Throws: `CancellationError` if the task was canceled, which isn't a device that didn't
  ///   answer.
  public static func verify(_ backup: HomeBackup, ping: (InsteonAddress) async throws -> Void) async throws -> TransferVerification {

    var checks: [TransferDeviceCheck] = []

    for device in backup.devices {

      do {

        try await ping(device.address)

        checks.append(TransferDeviceCheck(address: device.address, name: device.name))

      } catch is CancellationError {

        throw CancellationError()

      } catch {

        checks.append(TransferDeviceCheck(address: device.address, name: device.name, problem: "\(error)"))

      }

    }

    return TransferVerification(checks: checks)

  }

}
