import Crypto
import Foundation
import InsteonProtocol

/// What a client with no terminal grants before ``DeviceLinkingCoordinator/apply(_:consent:)->DatabaseLinkResult``
/// writes ALL-Link records: that records may be written, and which plan it has seen.
public struct DatabaseLinkConsent: Hashable, Sendable {

  /// Whether the client agrees that ALL-Link records are written.
  public var writeLinkRecords: Bool

  /// The ``DatabaseLinkPlan/fingerprint`` of the plan the client was shown.
  public var readFingerprint: String

  /// Creates a consent.
  ///
  /// - Parameters:
  ///   - writeLinkRecords: Whether the client agrees that ALL-Link records are written.
  ///   - readFingerprint: The fingerprint of the plan the client was shown.
  public init(writeLinkRecords: Bool, readFingerprint: String) {

    self.writeLinkRecords = writeLinkRecords
    self.readFingerprint = readFingerprint

  }

  /// Whether the consent grants the writes of a plan: it agrees to them and names the plan's
  /// fingerprint.
  ///
  /// - Parameter plan: The plan.
  /// - Returns: `true` when the plan may be carried out.
  public func grants(_ plan: DatabaseLinkPlan) -> Bool {

    writeLinkRecords && readFingerprint == plan.fingerprint

  }

}

/// Why ``DeviceLinkingCoordinator/apply(_:consent:)->DatabaseLinkResult`` wrote nothing for want of consent.
public enum DatabaseLinkConsentRefusal: Error, Hashable, Sendable {

  /// The consent doesn't agree to the writes, or names another plan than the one given.
  /// Nothing was sent.
  case consentRequired

}

extension DatabaseLinkConsentRefusal: CustomStringConvertible, LocalizedError {

  /// A one-line explanation of the refusal.
  public var description: String {

    switch self {
    case .consentRequired:
      "Writing ALL-Link records needs consent that names the plan that was shown. Nothing was written."
    }

  }

  /// The same text as the refusal's `description`, for `localizedDescription`.
  public var errorDescription: String? {

    description

  }

}

extension DatabaseLinkPlan {

  /// A SHA-256 over what the plan is and what it was made from, as `sha256:` and 64
  /// hexadecimal digits, so consent names exactly what a person was shown.
  ///
  /// It covers the device, the modem, the direction, the engine, each step's kind, memory
  /// address and record, the records of the device's database and the modem's as they were
  /// read, and the relay state and how the relay holds it. The same read gives the same
  /// fingerprint; a plan from another read, even of one record, gives another.
  public var fingerprint: String {

    var lines: [String] = [
      "device \(Self.hex(device.bytes))",
      "modem \(Self.hex(modem.bytes))",
      "direction \(direction.rawValue)",
      "engine \(engine)",
      "relayState \(relayState?.rawValue ?? "none")"
    ]

    if let relayHolding {

      lines.append("holding \(relayHolding.releasedBy) \(relayHolding.restState.rawValue) \(relayHolding.pulsesOnEveryCommandWhen) \(relayHolding.flagsOn)")

    }

    for step in steps {

      lines.append("step \(step.kind.rawValue) \(step.record.memoryAddress.map { String(format: "%04X", $0) } ?? "modem") \(Self.hex(Self.bytes(of: step.written)))")

    }

    for response in deviceRecords {

      lines.append("deviceRecord \(String(format: "%04X", response.address)) \(response.hasIntactChecksum) \(Self.hex(Self.bytes(of: response.record)))")

    }

    for record in allModemRecords {

      lines.append("modemRecord \(Self.hex(Self.bytes(of: record)))")

    }

    let digest = SHA256.hash(data: Data(lines.joined(separator: "\n").utf8))

    return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()

  }

  private static func bytes(of record: AllLinkRecord) -> [UInt8] {

    [record.flags.rawValue, record.group.rawValue] + record.address.bytes + [record.data1, record.data2, record.data3]

  }

  private static func hex(_ bytes: [UInt8]) -> String {

    bytes.map { String(format: "%02X", $0) }.joined()

  }

}

extension DeviceLinkingCoordinator {

  /// Carries out a plan once the consent names it, and sends nothing without.
  ///
  /// The consent is checked before any message is sent, so a plan that wasn't agreed to reads
  /// and writes nothing. Past it, this is ``apply(_:)``.
  ///
  /// - Parameters:
  ///   - plan: The plan.
  ///   - consent: What the client granted.
  /// - Returns: Each step's outcome and what reading both databases again found.
  /// - Throws: ``DatabaseLinkConsentRefusal`` when the consent doesn't grant the plan, and
  ///   what ``apply(_:)`` throws.
  public func apply(_ plan: DatabaseLinkPlan, consent: DatabaseLinkConsent) async throws -> DatabaseLinkResult {

    guard consent.grants(plan) else {

      throw DatabaseLinkConsentRefusal.consentRequired

    }

    return try await apply(plan)

  }

}
