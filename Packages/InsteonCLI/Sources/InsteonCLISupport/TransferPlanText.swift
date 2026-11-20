import InsteonCore
import InsteonProtocol

/// What `insteon transfer plan` prints: every step, grouped per device, each marked with its
/// effect and the exact record it would write.
public enum TransferPlanText {

  /// The plan as lines of text, for standard output.
  ///
  /// - Parameter plan: The plan.
  /// - Returns: The lines.
  public static func lines(_ plan: TransferPlan) -> [String] {

    var lines: [String] = []
    let from: String = plan.oldModem.map { "\($0)" } ?? "a modem the backup doesn't name"

    lines.append("Plan to move the devices in the backup from \(from) to \(plan.newModem). It writes nothing.")
    lines.append("Backup checksum: \(plan.backupChecksum)")

    if !plan.warnings.isEmpty {

      lines.append("")
      lines.append("Read this first:")

      for warning in plan.warnings {

        lines.append("  * \(warning)")

      }

    }

    if !plan.modemSteps.isEmpty || !plan.modemFindings.isEmpty {

      lines.append("")
      lines.append("The new modem, \(plan.newModem):")
      lines.append(contentsOf: steps(plan.modemSteps))
      lines.append(contentsOf: findings(plan.modemFindings))

    }

    for device in plan.devices {

      lines.append("")
      lines.append("Device \(label(device.address, name: device.name, type: device.type)), runs \(device.engine.rawValue):")
      lines.append(contentsOf: steps(device.steps))
      lines.append(contentsOf: findings(device.findings))

    }

    if !plan.unchangedDevices.isEmpty {

      lines.append("")
      lines.append("Nothing to change, no link to the old modem: \(plan.unchangedDevices.map { "\($0)" }.joined(separator: ", ")).")

    }

    if !plan.manual.isEmpty {

      lines.append("")
      lines.append("Link by hand, in this order (\(plan.manual.count) \(plan.manual.count == 1 ? "device" : "devices")), after the steps above:")

      for item in plan.manual {

        lines.append("  \(item.order). \(label(item.address, name: item.name, type: item.type)): \(reason(item.reason))")

        for link in item.linksToRestore {

          lines.append("       link to make again: \(describe(link))")

        }

        for (index, step) in item.steps.enumerated() {

          lines.append("       \(letter(index)). \(step)")

        }

      }

    }

    lines.append("")
    lines.append(summary(plan))

    return lines

  }

  /// The one line that counts the plan's steps and devices.
  ///
  /// - Parameter plan: The plan.
  /// - Returns: The line.
  public static func summary(_ plan: TransferPlan) -> String {

    let counts: [TransferEffect: Int] = plan.stepCounts
    let order: [TransferEffect] = [.readOnly, .configuration, .link, .destructive]
    let parts: [String] = order.compactMap { (effect: TransferEffect) -> String? in counts[effect].map { "\($0) \(effect.rawValue)" } }
    let steps: String = parts.isEmpty ? "No steps" : "\(plan.steps.count) \(plan.steps.count == 1 ? "step" : "steps") (\(parts.joined(separator: ", ")))"

    return "\(steps) on \(plan.devices.filter { !$0.steps.isEmpty }.count) \(plan.devices.filter { !$0.steps.isEmpty }.count == 1 ? "device" : "devices"), \(plan.manual.count) \(plan.manual.count == 1 ? "device" : "devices") to link by hand. Nothing was written."

  }

  // MARK: - Pieces

  private static func steps(_ steps: [TransferStep]) -> [String] {

    var lines: [String] = []

    for step in steps {

      lines.append("  \(step.number). [\(step.effect.rawValue)] \(step.summary)")

      if let record = step.record, step.action == .rewriteRecord || step.action == .addModemRecord || step.action == .removeModemRecord {

        let place: String = record.memoryAddress.map { " at \(hex($0))" } ?? ""

        lines.append("       writes: \(describe(record))\(place)")

      }

    }

    return lines

  }

  private static func findings(_ findings: [TransferFinding]) -> [String] {

    findings.map { "  left as it is: \($0.summary)" }

  }

  private static func describe(_ record: BackupRecord) -> String {

    "\(record.role.rawValue), group \(record.group), \(record.address), data \(pairs(record.data))"

  }

  private static func label(_ address: InsteonAddress, name: String?, type: String?) -> String {

    let detail: [String] = [name, type].compactMap { $0 }

    return detail.isEmpty ? "\(address)" : "\(address) (\(detail.joined(separator: ", ")))"

  }

  private static func reason(_ reason: ManualTransferReason) -> String {

    switch reason {
    case .noDatabase:
      "the backup holds no ALL-Link database for it"
    case .incompleteDatabase:
      "the backup's ALL-Link database for it is partial"
    case .noRemoteWrites:
      "it runs i1, which has no remote writes to its ALL-Link database"
    case .rejectsUntilLinked:
      "it runs i2CS and rejects a modem it isn't linked to"
    case .engineUnknown:
      "the backup doesn't say which engine it runs"
    case .noModemDatabase:
      "the backup holds no ALL-Link database of the old modem"
    }

  }

  private static func letter(_ index: Int) -> String {

    String(UnicodeScalar(UInt8(97 + min(index, 25))))

  }

  private static func pairs(_ bytes: [UInt8]) -> String {

    bytes.map { Hex.pairs([$0]) }.joined(separator: " ")

  }

  private static func hex(_ value: UInt16) -> String {

    Hex.address(value)

  }

}
