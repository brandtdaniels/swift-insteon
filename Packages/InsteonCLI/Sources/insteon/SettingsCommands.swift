import InsteonCLICore
import InsteonCore
import InsteonDeviceCatalog
import InsteonProtocol

/// `insteon device ADDRESS settings` and `set`: reads and changes the settings the Insteon
/// device catalog describes, through a `Device`.
enum SettingsCommands {

  // MARK: - settings

  static func show(_ device: Device, showsAdvanced: Bool, printsJSON: Bool) async throws {

    let address: InsteonAddress = device.address
    let reading: DeviceSettingsReading

    do {

      reading = try await device.readSettings(includingAdvanced: showsAdvanced, beforeReading: { () -> Void in

        Output.note("Reading the settings of \(address)...")

      })

    } catch let error as DeviceSettingError {

      throw CommandFailure(description: failure(error, device: address))

    }

    let reported = ReportedSettings(operatingFlags: reading.operatingFlags, values: reading.values)
    let lines: [SettingLine] = SettingsText.lines(for: reading.commandSet, reported: reported, buttons: reading.buttons, showsAdvanced: showsAdvanced)

    if printsJSON {

      try Output.json(lines)

      return

    }

    printLines(lines, device: address, product: reading.productName)

    let hidden: Int = reading.commandSet.settingItems.count - reading.items.count

    if hidden > 0 {

      Output.line("\(Wording.count(hidden, "advanced setting")) not shown; --advanced shows them.")

    }

    if lines.contains(where: \.isWritable) {

      Output.line("Change a writable one with 'insteon device \(address) set NAME VALUE'.")

    }

  }

  private static func printLines(_ lines: [SettingLine], device: InsteonAddress, product: String?) {

    let named: String = product.map { ", " + $0 } ?? ""

    Output.line("Settings of \(device)\(named):")

    var rows: [[String]] = []
    var section: String?

    for line in lines {

      if line.section != section {

        rows.append([""])
        rows.append([line.section])
        section = line.section

      }

      rows.append(["  " + line.title + ":", line.valueText, line.notes])

    }

    Output.table(rows)
    Output.line()

  }

  // MARK: - set

  static func set(_ request: SettingRequest, device: Device) async throws {

    let address: InsteonAddress = device.address
    let change: DeviceSettingChange

    do {

      change = try await device.writeSetting(request.name, to: request.value, button: request.button.map { (button: UInt8) -> Int in Int(button) })

    } catch let error as DeviceSettingError {

      throw CommandFailure(description: failure(error, device: address))

    }

    let before: String = change.before ?? "not reported"

    guard let after = change.after else {

      let what: String = change.setting.control == .toggle ? "flag" : "value"

      Output.line("\(change.title): \(before) → \(change.requested), not confirmed: the device didn't report the \(what) afterward.")

      return

    }

    Output.line("\(change.title): \(before) → \(after)")

  }

  // MARK: - Failures

  /// Why the settings couldn't be read or a setting written, as a sentence.
  private static func failure(_ error: DeviceSettingError, device: InsteonAddress) -> String {

    switch error {
    case .notIdentified:
      return "\(device) didn't report its identity, so its settings can't be looked up. Check that it's linked and in range."
    case let .noSettings(product):
      return "The Insteon device catalog doesn't describe the settings of \(product)."
    case let .noSuchSetting(name, product):
      return "The Insteon device catalog has no setting '\(name)' for \(product). 'insteon device \(device) settings --advanced' lists them."
    case let .isReading(label):
      return "\(label) is a reading the device reports, so it can't be changed."
    case let .takesNoButton(label):
      return "\(label) is the whole device's, so it takes no --button."
    case let .unreadableState(text, label):
      return "'\(text)' isn't a state for \(label): expected on or off."
    case let .noCommandForState(label, isOn):
      return "\(label) can't be turned \(SettingsText.flag(isOn)) on this device: "
        + "the Insteon device catalog gives no command that does it."
    case let .readOnly(label):
      return "\(label) is read-only for this device: the Insteon device catalog gives no command that writes it."
    case let .unreadableValue(problem, value, label, commandSet):
      return SettingsText.inputProblem(problem, value: value, label: label, in: commandSet)
    case let .missingValue(label, other):
      return "Writing \(label) also writes \(other), which the device didn't report, so nothing was changed."
    case let .unwritableValue(problem, label, value):
      return "The Insteon device catalog's command for \(label) can't take \(value): \(fieldProblem(problem)), so nothing was changed."
    case .engineRejected:
      return "\(device) rejected Get Insteon Engine Version, as an i2CS device does when it isn't linked to the modem, "
        + "so its settings can't be written. Link it first with 'insteon link \(device)'."
    case let .notChanged(title, requested, reported):
      return "\(title) wasn't changed to \(requested): the device reports \(reported)."
    }

  }

  /// Why a catalog's extended command couldn't take a value, as a clause.
  private static func fieldProblem(_ error: FieldError) -> String {

    switch error {
    case let .mismatchedKind(name):
      "its parameter \(name) is a different kind of value"
    case let .outOfRange(name):
      "it's outside what its parameter \(name) takes"
    case let .unknownName(name):
      "its parameter \(name) has no such name"
    case let .missingValue(name):
      "it has no parameter for \(name)"
    }

  }

}
