import InsteonDeviceCatalog
import InsteonLinking
import InsteonProtocol

/// Keeps a device's operating flags as they were across a link in which the device is the
/// controller.
///
/// A device that enters linking mode as a controller can record its state as it does, and
/// some devices keep part of that state in an operating flag: an I/O module records its
/// sensor's state, which can change its flag that reverses the sensor. So, before such a
/// link, the flags the Insteon device catalog describes for the device's command set are read
/// with Get Operating Flags, and afterward read again; a flag the link changed is set back
/// with ``Device/writeSetting(_:to:button:)``, which reads it back to confirm.
///
/// Only flags a settings page can change are kept, and only for a device the registry knows,
/// so the device isn't asked for its identity. A device that rejects Get Operating Flags or
/// doesn't answer it, such as an i2CS device that isn't linked to the modem yet, has nothing
/// kept.
struct OperatingFlagsGuard: Sendable {

  /// The device.
  let device: Device

  /// The device's command set.
  let commands: CommandSet

  /// The flags to keep, in the command set's order.
  let items: [SettingItem]

  /// The flags as they were before the link, by setting key, as a settings page shows them.
  let before: [String: String]

  /// Reads the flags to keep before a link.
  ///
  /// - Parameters:
  ///   - device: The device.
  ///   - description: What the catalog says about the device.
  /// - Returns: The guard, or `nil` when there's nothing to keep: the catalog describes no flag
  ///   a settings page can change, or the device reported none.
  /// - Throws: `CancellationError` if the task is canceled, and the errors of the modem and
  ///   the connection to it, such as `ModemError.connectionClosed`.
  static func read(_ device: Device, description: DeviceDescription?) async throws -> OperatingFlagsGuard? {

    guard let commands = description?.commandSet else {

      return nil

    }

    let items: [SettingItem] = commands.settingItems.filter { (item: SettingItem) -> Bool in

      guard case .flag = item.source else {

        return false

      }

      return SettingPresentation.setting(for: item, in: commands).isWritable

    }

    guard !items.isEmpty else {

      return nil

    }

    let before: [String: String] = try await texts(of: items, in: commands, device: device)

    guard !before.isEmpty else {

      return nil

    }

    return OperatingFlagsGuard(device: device, commands: commands, items: items, before: before)

  }

  /// Reads the flags again after the link, and sets back each one the link changed.
  ///
  /// - Parameter failed: Called for each flag that couldn't be set back, with its key and
  ///   the error, so an app can say so. A flag that can't be set back doesn't stop the others.
  /// - Returns: The flags set back, in the command set's order.
  /// - Throws: `CancellationError` if the task is canceled, and the errors of the modem and
  ///   the connection to it, such as `ModemError.connectionClosed`.
  func restore(failed: (String, any Error) async -> Void) async throws -> [DeviceSettingChange] {

    let after: [String: String] = try await Self.texts(of: items, in: commands, device: device)
    var changes: [DeviceSettingChange] = []

    for item in items {

      let key: String = item.name.rawValue

      guard let was = before[key], let now = after[key], was != now else {

        continue

      }

      do {

        changes.append(try await device.writeSetting(key, to: was))

      } catch let error as CancellationError {

        throw error

      } catch {

        await failed(key, error)

      }

    }

    return changes

  }

  /// The flags a device reports, by setting key, as a settings page shows them.
  private static func texts(of items: [SettingItem], in commands: CommandSet, device: Device) async throws -> [String: String] {

    var flags: [OperatingFlagsRequest: UInt8] = [:]

    for query in Device.queries(of: items) {

      let message = StandardMessage(to: device.address, command: StandardDirectCommand.getOperatingFlags(query))

      if let acknowledgment = try await device.answer(message) {

        flags[query] = acknowledgment.command.command2

      }

    }

    let reading = DeviceSettingsReading(
      productName: nil,
      commandSet: commands,
      items: items,
      operatingFlags: flags,
      values: [:],
      buttons: [0x01]
    )
    var texts: [String: String] = [:]

    for entry in reading.entries {

      if let text = entry.text {

        texts[entry.setting.key] = text

      }

    }

    return texts

  }

}
