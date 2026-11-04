import InsteonDeviceCatalog
import InsteonModem
import InsteonProtocol

// Reading the device's other settings before and after a write, to say what else it changed.
extension Device {

  /// The device's writable settings other than the one a write changes, read before the write
  /// and again after it with the reads ``readSettings(includingAdvanced:beforeReading:)``
  /// makes, reusing what the write's own reads already reported.
  struct OtherSettingsCheck {

    /// What was read of the other settings before a write.
    enum Before {

      /// The reading.
      case read(DeviceSettingsReading)

      /// Nothing was read, for the reason the outcome gives.
      case skipped(DeviceSettingChange.OtherSettings.Outcome)

    }

    /// The device.
    let device: Device

    /// The settings read: every one the catalog gives a way to write, the setting written
    /// included. A setting the catalog gives no way to write, such as a reading or a value the
    /// device measures, changes on its own rather than as a write's side effect, so it's left
    /// out. A flag that's never written, such as one that turns the radio off, is still read,
    /// since a write can change it.
    let items: [SettingItem]

    /// The setting written, as a settings page shows it.
    let written: DeviceSetting

    /// The button written, for a setting that's per button; otherwise `nil`.
    let writtenButton: Int?

    /// The buttons whose values are read: button 1, which holds the values that aren't per
    /// button, and the button written when it isn't button 1. Empty when no value is read.
    let buttons: [UInt8]

    /// The device's command set.
    let commands: CommandSet

    /// The device's description.
    let description: DeviceDescription

    /// A check of the writable settings around a write of `item` to `button`.
    init(device: Device, writing item: SettingItem, button: UInt8, description: DeviceDescription, commands: CommandSet) {

      let items: [SettingItem] = commands.settingItems.filter { (candidate: SettingItem) -> Bool in commands.isWritable(candidate) }
      let written: DeviceSetting = SettingPresentation.setting(for: item, in: commands)
      let values: [SettingItem] = items.filter(Device.isValue)
      let isAnyPerButton: Bool = values.contains { (value: SettingItem) -> Bool in commands.extendedSettings?.isValuePerButton(value.name) ?? false }

      self.device = device
      self.items = items
      self.written = written
      self.writtenButton = written.isPerButton ? Int(button) : nil
      self.buttons = values.isEmpty ? [] : (isAnyPerButton && button != 0x01 ? [0x01, button] : [0x01])
      self.commands = commands
      self.description = description

    }

    /// Whether there's nothing to compare: no setting but the one written, and no other
    /// button of it.
    var isEmpty: Bool {

      let others: Bool = items.contains { (item: SettingItem) -> Bool in SettingPresentation.setting(for: item, in: commands) != written }

      return !others && !(writtenButton != nil && buttons.count > 1)

    }

    /// The entries of a reading that are compared, each with its button: every entry but the
    /// setting written on the button written. A setting that's per button carries its button
    /// even when only button 1 was read, so it's named the same way every time.
    func compared(_ reading: DeviceSettingsReading) -> [(entry: DeviceSettingsReading.Entry, button: Int?)] {

      reading.entries.compactMap { (entry: DeviceSettingsReading.Entry) -> (entry: DeviceSettingsReading.Entry, button: Int?)? in

        let button: Int? = entry.button ?? (entry.setting.isPerButton ? 1 : nil)

        if entry.setting == written, button == writtenButton {

          return nil

        }

        return (entry, button)

      }

    }

    /// Reads the other settings, asking only for what `flags` and `values` don't already hold.
    ///
    /// - Parameters:
    ///   - flags: Get Operating Flags replies already read, by request.
    ///   - values: Extended Get replies already read, by button.
    /// - Returns: The reading.
    func read(knowing flags: [OperatingFlagsRequest: UInt8], values: [UInt8: [SettingName: UInt8]]) async throws -> DeviceSettingsReading {

      var reportedFlags: [OperatingFlagsRequest: UInt8] = flags
      var reportedValues: [UInt8: [SettingName: UInt8]] = values

      for query in Device.queries(of: items) where reportedFlags[query] == nil {

        if let acknowledgment = try await device.answer(StandardMessage(to: device.address, command: StandardDirectCommand.getOperatingFlags(query))) {

          reportedFlags[query] = acknowledgment.command.command2

        }

      }

      if let settings = commands.extendedSettings {

        for button in buttons where reportedValues[button] == nil {

          if let reported = try await device.readValues(settings: settings, button: button) {

            reportedValues[button] = reported

          }

        }

      }

      return DeviceSettingsReading(
        productName: description.displayName,
        commandSet: commands,
        items: items,
        operatingFlags: reportedFlags.filter { (query: OperatingFlagsRequest, _: UInt8) -> Bool in Device.queries(of: items).contains(query) },
        values: reportedValues.filter { (button: UInt8, _: [SettingName: UInt8]) -> Bool in buttons.contains(button) },
        buttons: buttons
      )

    }

    /// Reads the other settings before the write, once the write's own read was answered.
    ///
    /// - Parameters:
    ///   - isOwnReported: Whether the device answered the write's own read. When it didn't,
    ///     nothing more is asked, so a device that doesn't answer isn't kept waiting on.
    ///   - flags: Get Operating Flags replies the write's own read already holds.
    ///   - values: Extended Get replies the write's own read already holds.
    /// - Returns: The reading, or how the comparison ended before it began.
    func readBefore(
      isOwnReported: Bool,
      knowing flags: [OperatingFlagsRequest: UInt8] = [:],
      values: [UInt8: [SettingName: UInt8]] = [:]
    ) async throws -> Before {

      guard !isEmpty else {

        return .skipped(.nothingToCompare)

      }

      guard isOwnReported else {

        return .skipped(.notReportedBefore)

      }

      let reading: DeviceSettingsReading = try await read(knowing: flags, values: values)

      guard compared(reading).contains(where: { (pair: (entry: DeviceSettingsReading.Entry, button: Int?)) -> Bool in pair.entry.text != nil }) else {

        return .skipped(.notReportedBefore)

      }

      return .read(reading)

    }

    /// Reads the other settings again after a confirmed write and compares them with what was
    /// read before.
    ///
    /// The write already succeeded, so nothing here fails it: a read that throws, or is
    /// canceled, ends the comparison with ``DeviceSettingChange/OtherSettings/rereadFailure``
    /// saying why, and a canceled task stays canceled for the caller's next wait.
    ///
    /// - Parameters:
    ///   - before: What was read before the write.
    ///   - flags: Get Operating Flags replies the write's read-back already holds.
    ///   - values: Extended Get replies the write's read-back already holds.
    /// - Returns: What the other settings did across the write.
    func compare(
      with before: Before,
      knowing flags: [OperatingFlagsRequest: UInt8] = [:],
      values: [UInt8: [SettingName: UInt8]] = [:]
    ) async -> DeviceSettingChange.OtherSettings {

      let earlier: DeviceSettingsReading

      switch before {
      case let .read(reading):
        earlier = reading
      case let .skipped(outcome):
        return DeviceSettingChange.OtherSettings(outcome: outcome)
      }

      let later: DeviceSettingsReading

      do {

        later = try await read(knowing: flags, values: values)

      } catch is CancellationError {

        // A modem can throw CancellationError on its own; only a canceled task is canceled.
        return .notReread(Task.isCancelled ? .canceled : .failed)

      } catch ModemError.connectionClosed {

        return .notReread(.connectionClosed)

      } catch {

        return .notReread(.failed)

      }

      return otherSettings(before: earlier, after: later)

    }

    /// What the compared settings did between two readings of the same items and buttons:
    /// each one whose value differs, in order; each one the earlier reading reported that the
    /// later one didn't, as unread; and ``DeviceSettingChange/OtherSettings/ReadFailure/notAnswered``
    /// when the later reading has none of the values the earlier one has. A setting the
    /// earlier reading didn't report is left out.
    func otherSettings(before earlier: DeviceSettingsReading, after later: DeviceSettingsReading) -> DeviceSettingChange.OtherSettings {

      var changes: [DeviceSettingChange.OtherChange] = []
      var unread: [DeviceSettingChange.UnreadSetting] = []
      var reportedBefore: Int = 0

      // The readings are of the same items and buttons, so their entries line up one for one.
      for (first, second) in zip(compared(earlier), compared(later)) {

        guard let before = first.entry.text else {

          continue

        }

        reportedBefore += 1

        guard let reported = second.entry.text else {

          unread.append(DeviceSettingChange.UnreadSetting(setting: first.entry.setting, button: first.button))

          continue

        }

        if reported != before {

          changes.append(DeviceSettingChange.OtherChange(setting: first.entry.setting, button: first.button, before: before, after: reported))

        }

      }

      if unread.count == reportedBefore {

        return .notReread(.notAnswered)

      }

      return .compared(changes, unread: unread)

    }

  }

}
