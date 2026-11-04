import Foundation
import Testing
import InsteonCLISupport
import InsteonCore

/// What `insteon device ADDRESS set` prints about the other settings a write changed, as text
/// and as JSON, for made-up settings.
struct SettingChangeTextTests {

  let lingerTime = DeviceSetting(
    key: "lingerTime",
    label: "Linger time",
    section: "Load",
    summary: "How long the load lingers.",
    isAdvanced: false,
    isWritable: true,
    isPerButton: false,
    control: .byte(range: nil)
  )

  let sparkle = DeviceSetting(
    key: "sparkle",
    label: "Sparkle",
    section: "Load",
    summary: "Sparkles.",
    isAdvanced: false,
    isWritable: false,
    isPerButton: false,
    control: .toggle
  )

  let glimmer = DeviceSetting(
    key: "glimmer",
    label: "Glimmer",
    section: "Load",
    summary: "How much the load glimmers.",
    isAdvanced: false,
    isWritable: true,
    isPerButton: true,
    control: .byte(range: nil)
  )

  func change(_ otherSettings: DeviceSettingChange.OtherSettings) -> DeviceSettingChange {

    DeviceSettingChange(setting: lingerTime, button: nil, before: "0x00", requested: "0x05", after: "0x05", otherSettings: otherSettings)

  }

  // MARK: - Text

  @Test func printsALineForEachOtherSettingTheWriteChanged() {

    let written: DeviceSettingChange = change(.compared([
      DeviceSettingChange.OtherChange(setting: sparkle, button: nil, before: "off", after: "on"),
      DeviceSettingChange.OtherChange(setting: glimmer, button: 2, before: "0x10", after: "0x00")
    ]))

    #expect(SettingsText.report(written) == [
      "Linger time: 0x00 → 0x05",
      "Also changed: Sparkle: off → on",
      "Also changed: Glimmer (button 2): 0x10 → 0x00"
    ])

  }

  @Test func printsOnlyTheSettingWrittenWhenNothingElseChanged() {

    #expect(SettingsText.report(change(.compared([]))) == ["Linger time: 0x00 → 0x05"])
    #expect(SettingsText.report(change(.notCompared)) == ["Linger time: 0x00 → 0x05"])

  }

  @Test func saysTheWriteSucceededWhenTheOtherSettingsCouldntBeReadAgain() {

    #expect(SettingsText.report(change(.notReread)) == [
      "Linger time: 0x00 → 0x05",
      "The write succeeded, but the device's other settings couldn't be read again, so what else it changed isn't known."
    ])

  }

  // MARK: - JSON

  func json(_ change: DeviceSettingChange) throws -> [String: Any] {

    let data: Data = try JSONEncoder().encode(SettingChangeJSON(change))

    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

  }

  @Test func printsTheChangedSettingsAsJSON() throws {

    let object: [String: Any] = try json(change(.compared([
      DeviceSettingChange.OtherChange(setting: sparkle, button: nil, before: "off", after: "on"),
      DeviceSettingChange.OtherChange(setting: glimmer, button: 2, before: "0x10", after: "0x00")
    ])))
    let changed: [[String: Any]] = try #require(object["changedSettings"] as? [[String: Any]])

    #expect(object["name"] as? String == "lingerTime")
    #expect(object["label"] as? String == "Linger time")
    #expect(object["before"] as? String == "0x00")
    #expect(object["requested"] as? String == "0x05")
    #expect(object["after"] as? String == "0x05")
    #expect(object["otherSettings"] as? String == "compared")
    #expect(changed.count == 2)
    #expect(changed.first?["name"] as? String == "sparkle")
    #expect(changed.first?["label"] as? String == "Sparkle")
    #expect(changed.first?["before"] as? String == "off")
    #expect(changed.first?["after"] as? String == "on")
    #expect(changed.first?["button"] == nil)
    #expect(changed.last?["button"] as? Int == 2)

  }

  @Test func printsAnEmptyListAndSaysWhyWhenNothingWasCompared() throws {

    let unread: [String: Any] = try json(change(.notReread))
    let uncompared: [String: Any] = try json(change(.notCompared))

    #expect((unread["changedSettings"] as? [Any])?.isEmpty == true)
    #expect(unread["otherSettings"] as? String == "notReread")
    #expect(uncompared["otherSettings"] as? String == "notCompared")

  }

}
