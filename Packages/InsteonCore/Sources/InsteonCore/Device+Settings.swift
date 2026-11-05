import InsteonDeviceCatalog
import InsteonLinking
import InsteonModem
import InsteonProtocol

// Reading the device's settings.
extension Device {

  /// Reads the device's settings the catalog describes: each Get Operating Flags request they
  /// need, once, and an extended Get for button 1, then for each of the device's other groups
  /// when a value is per button.
  ///
  /// A request the device rejects or doesn't answer leaves its settings unreported, rather
  /// than failing the reading.
  ///
  /// - Parameters:
  ///   - includingAdvanced: Whether to read the settings a settings page keeps out of sight
  ///     unless asked. Defaults to `true`.
  ///   - beforeReading: Called once the settings are known and before the device is asked for
  ///     them, so an app can say that a reading has begun. Defaults to doing nothing.
  /// - Returns: The settings and what the device reported.
  /// - Throws: ``DeviceSettingError/notIdentified`` or ``DeviceSettingError/noSettings(product:)``
  ///   when the settings aren't known, the errors of ``info()``, and the modem's
  ///   errors.
  public func readSettings(includingAdvanced: Bool = true, beforeReading: @Sendable () -> Void = {}) async throws -> DeviceSettingsReading {

    let (description, commands): (DeviceDescription, CommandSet) = try await describedSettings()
    let items: [SettingItem] = commands.settingItems.filter { (item: SettingItem) -> Bool in includingAdvanced || !item.isAdvanced }

    beforeReading()

    return try await read(items, description: description, commands: commands)

  }

  /// Reads items of the device's settings: each Get Operating Flags request they need, once,
  /// and an extended Get for button 1, then for each of the device's other groups when a value
  /// is per button. Nothing is sent for an item the catalog gives no way to read.
  func read(_ items: [SettingItem], description: DeviceDescription, commands: CommandSet) async throws -> DeviceSettingsReading {

    var flags: [OperatingFlagsRequest: UInt8] = [:]

    for query in Self.queries(of: items) {

      if let acknowledgment = try await answer(StandardMessage(to: address, command: StandardDirectCommand.getOperatingFlags(query))) {

        flags[query] = acknowledgment.command.command2

      }

    }

    let buttons: [UInt8] = Self.buttons(for: items, in: commands, description: description)
    var values: [UInt8: [SettingName: UInt8]] = [:]

    if let settings = commands.extendedSettings, items.contains(where: { (item: SettingItem) -> Bool in Self.isValue(item) }) {

      for button in buttons {

        if let reported = try await readValues(settings: settings, button: button) {

          values[button] = reported

        }

      }

    }

    return DeviceSettingsReading(
      productName: description.displayName,
      commandSet: commands,
      items: items,
      operatingFlags: flags,
      values: values,
      buttons: buttons
    )

  }

  /// Changes one of the device's settings, and reads it back to confirm the change.
  ///
  /// Some settings are never written: a flag the catalog guards with `FlagGuard.keep`, such
  /// as one that turns off the device's radio or powerline or requires a checksum in every
  /// message, any of which can cut the device off from the modem. A flag the catalog guards
  /// with `FlagGuard.neverSet`, such as one that locks linking from the device itself, is only
  /// turned off, never on, so a device is never left locked. A command the catalog guards with
  /// `CommandGuard.never` is never sent, nor is a Set Operating Flags command with the same
  /// bytes. All of these are refused before anything is sent. A value whose byte holds
  /// operating flags, which the catalog marks with `SettingValue.flagsQuery`, such as a
  /// sensor's configuration byte, is refused before it's written when it would set a bit
  /// that's never set, or change a bit that's kept; the device is asked for the byte first,
  /// to compare. The guarded bits of an extended command's flags parameter are checked
  /// the same way.
  ///
  /// A flag is changed with Set Operating Flags, in the form the device takes: extended with a
  /// checksum for an i2CS device, extended with the command repeated while the flag the
  /// catalog names in `OperatingFlag.extendedWhen` is set, and standard otherwise; or with the
  /// standard command the catalog names for the state. A value is changed with an extended Set
  /// that keeps the other values it writes as the device reported them, or with the extended
  /// command the catalog names.
  ///
  /// A write can change other settings as well, as some devices turn a flag on when a value
  /// that isn't zero is written. So the device's settings the catalog gives a way to write
  /// are read before the write and again once it's confirmed, with the requests
  /// ``readSettings(includingAdvanced:beforeReading:)`` makes, and
  /// ``DeviceSettingChange/otherSettings`` holds each one whose value differs. A flag that's
  /// never written, such as one that turns the radio off, is compared too, since a write can
  /// change it. A reading or a value the catalog gives no way to write, such as a measure of
  /// noise, changes on its own rather than as a side effect, so it's left out.
  ///
  /// Each Get Operating Flags request and extended Get the comparison needs is sent once before
  /// the write and once after it, and the write's own read and read-back count among them, since
  /// they carry the other settings that share their reply. A flag write's other requests are
  /// separate: Get Insteon Engine Version, and the read of the flag the written flag's
  /// `extendedWhen` names. A value write sends neither. Values are read for button 1 and, for a setting that's per button, the button
  /// written, so a flag write or a write to button 1 compares button 1 only; a change to
  /// another button's values isn't seen. The setting written is compared on every button read
  /// but the one written. A setting that's per button carries its button, even when only
  /// button 1 was read.
  ///
  /// The other settings aren't read when the catalog describes none, when the device doesn't
  /// answer the write's own read before it, or when the write isn't confirmed or the device
  /// reports another value. A setting the device didn't report before the write is left out,
  /// and one it reported before but not after is in
  /// ``DeviceSettingChange/OtherSettings/unread``.
  ///
  /// Once the write is confirmed, nothing about the other settings fails it: when they can't be
  /// read again, ``DeviceSettingChange/OtherSettings/rereadFailure`` says why, the connection
  /// closing included. A task canceled while they're read again gets the change, with the
  /// failure ``DeviceSettingChange/OtherSettings/ReadFailure/canceled``, and stays canceled,
  /// so its next wait throws `CancellationError`. A `CancellationError` the modem throws while
  /// the task isn't canceled is ``DeviceSettingChange/OtherSettings/ReadFailure/failed``.
  ///
  /// - Parameters:
  ///   - key: The setting's key, such as `"rampRate"`, or its label, in any case.
  ///   - text: The value, such as `"on"`, `"0.5 s"`, `"50%"` or `"0x1C"`.
  ///   - button: The button or group, for a setting that's per button, or `nil` for button 1.
  ///     Defaults to `nil`.
  /// - Returns: The value before and after, and the other settings the write changed. A
  ///   change the device didn't report afterward isn't confirmed, and its other settings
  ///   aren't compared.
  /// - Throws: ``DeviceSettingError`` when the setting or the value isn't one the device takes,
  ///   ``DeviceSettingError/neverWritten(label:)`` or
  ///   ``DeviceSettingError/leavesProgrammingLocked(label:)`` for a setting that isn't written,
  ///   or ``DeviceSettingError/notChanged(title:requested:reported:)`` when the device reports
  ///   another value afterward; ``DeviceControlError/noSuchGroup(_:product:)`` for a button
  ///   that isn't a group number; and the modem's errors.
  public func writeSetting(_ key: String, to text: String, button: Int? = nil) async throws -> DeviceSettingChange {

    let (description, commands): (DeviceDescription, CommandSet) = try await describedSettings()

    guard let item = commands.settingItem(named: key) else {

      throw DeviceSettingError.noSuchSetting(key, product: DeviceControlModel.product(of: description))

    }

    // Refused before anything is sent, whatever else the catalog says about writing it.
    if DeviceSettingSafety.isNeverWritten(item, in: commands) {

      throw DeviceSettingError.neverWritten(label: item.label)

    }

    var buttonNumber: UInt8?

    if let button {

      guard let number = UInt8(exactly: button) else {

        throw DeviceControlError.noSuchGroup(button, product: DeviceControlModel.product(of: description))

      }

      buttonNumber = number

    }

    let setting: DeviceSetting = SettingPresentation.setting(for: item, in: commands)
    let others = OtherSettingsCheck(device: self, writing: item, button: buttonNumber ?? 0x01, description: description, commands: commands)
    let change: DeviceSettingChange

    switch item.source {
    case .reading:
      throw DeviceSettingError.isReading(label: item.label)
    case let .flag(flag):
      change = try await write(flag, item: item, setting: setting, to: text, button: buttonNumber, description: description, commands: commands, others: others)
    case let .value(value):
      change = try await write(value, item: item, setting: setting, to: text, button: buttonNumber, commands: commands, others: others)
    }

    if change.isConfirmed {

      await network.recordAnswer(of: address, level: nil)

    }

    return change

  }

}
