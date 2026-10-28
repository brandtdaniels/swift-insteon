import Testing
import InsteonDeviceCatalog
import InsteonNotifications
import InsteonProtocol

struct NotificationRuleSetTests {

  let leakSensor = InsteonAddress(0x2A, 0x3B, 0x4C)

  let frontDoor = InsteonAddress(0x1A, 0x2B, 0x3C)

  let hallSwitch = InsteonAddress(0x3A, 0x4B, 0x5C)

  let start = ContinuousClock.now

  func groupCommand(from device: InsteonAddress, group: AllLinkGroupNumber = 0x01, command1: UInt8, event: DeviceEventName?) -> DeviceEvent {

    .groupCommand(GroupCommand(controller: device, group: group, command1: command1, command2: nil, source: .broadcast), event: event)

  }

  @Test func firesOnANamedEventFromItsDevice() {

    let leak = NotificationRule(id: "leak", name: "Basement leak", trigger: .event("wet", from: leakSensor))
    var rules = NotificationRuleSet<ContinuousClock.Instant>(rules: [leak])

    #expect(rules.notifications(for: groupCommand(from: leakSensor, group: 0x02, command1: 0x11, event: "wet"), at: start) == [DeviceNotification(rule: leak, instant: start)])
    #expect(rules.notifications(for: groupCommand(from: leakSensor, command1: 0x11, event: "dry"), at: start).isEmpty)
    #expect(rules.notifications(for: groupCommand(from: frontDoor, command1: 0x11, event: "wet"), at: start).isEmpty)
    #expect(rules.notifications(for: .statusChanged(leakSensor), at: start).isEmpty)

  }

  // A switch's profile names no events, so its rule names the group command.
  @Test func firesOnAGroupCommandFromAProductWithNoNamedEvents() {

    let on = NotificationRule(id: "hall-on", name: "Hall light on", trigger: .groupCommand(command1: 0x11, group: 0x01, from: hallSwitch))
    var rules = NotificationRuleSet<ContinuousClock.Instant>(rules: [on])

    #expect(rules.notifications(for: groupCommand(from: hallSwitch, command1: 0x11, event: nil), at: start).map(\.rule.id) == ["hall-on"])
    #expect(rules.notifications(for: groupCommand(from: hallSwitch, command1: 0x13, event: nil), at: start).isEmpty)
    #expect(rules.notifications(for: groupCommand(from: hallSwitch, group: 0x02, command1: 0x11, event: nil), at: start).isEmpty)
    #expect(on.trigger.device == hallSwitch)

  }

  @Test func staysQuietDuringItsCooldown() {

    let door = NotificationRule(id: "door", name: "Front door opened", trigger: .event("opened", from: frontDoor), cooldown: .seconds(300))
    var rules = NotificationRuleSet<ContinuousClock.Instant>(rules: [door])
    let opened = groupCommand(from: frontDoor, command1: 0x11, event: "opened")

    #expect(rules.notifications(for: opened, at: start).count == 1)
    #expect(rules.notifications(for: opened, at: start.advanced(by: .seconds(299))).isEmpty)
    #expect(rules.notifications(for: opened, at: start.advanced(by: .seconds(300))).count == 1)

  }

  @Test func leavesOutDisabledRulesAndKeepsTheRulesOrder() {

    let first = NotificationRule(id: "first", name: "First", trigger: .event("opened", from: frontDoor))
    let off = NotificationRule(id: "off", name: "Off", trigger: .event("opened", from: frontDoor), isEnabled: false)
    let second = NotificationRule(id: "second", name: "Second", trigger: .event("opened", from: frontDoor))
    var rules = NotificationRuleSet<ContinuousClock.Instant>(rules: [first, off, second])

    #expect(rules.notifications(for: groupCommand(from: frontDoor, command1: 0x11, event: "opened"), at: start).map(\.rule.id) == ["first", "second"])

  }

  @Test func firesOnceEachTimeADeviceGoesSilent() {

    let quiet = NotificationRule(id: "quiet", name: "Leak sensor quiet", trigger: .silence(of: leakSensor))
    var rules = NotificationRuleSet<ContinuousClock.Instant>(rules: [quiet])

    #expect(rules.notifications(forSilent: [], at: start).isEmpty)
    #expect(rules.notifications(forSilent: [leakSensor], at: start).map(\.device) == [leakSensor])
    #expect(rules.notifications(forSilent: [leakSensor], at: start.advanced(by: .seconds(60))).isEmpty)

    // Heard from again, then silent again.
    #expect(rules.notifications(forSilent: [], at: start.advanced(by: .seconds(120))).isEmpty)
    #expect(rules.notifications(forSilent: [leakSensor], at: start.advanced(by: .seconds(180))).count == 1)
    #expect(rules.notifications(for: groupCommand(from: leakSensor, command1: 0x11, event: "wet"), at: start).isEmpty)

  }

  @Test func replacesARuleWithTheSameIdentifierAndForgetsWhenItFired() {

    let door = NotificationRule(id: "door", name: "Front door opened", trigger: .event("opened", from: frontDoor), cooldown: .seconds(300))
    var rules = NotificationRuleSet<ContinuousClock.Instant>(rules: [door])
    let opened = groupCommand(from: frontDoor, command1: 0x11, event: "opened")

    #expect(rules.notifications(for: opened, at: start).count == 1)

    var renamed = door
    renamed.name = "Front door"
    rules.add(renamed)

    #expect(rules.rules == [renamed])
    #expect(rules.notifications(for: opened, at: start.advanced(by: .seconds(1))).map(\.rule.name) == ["Front door"])

    rules.remove("door")

    #expect(rules.rule(id: "door") == nil)
    #expect(rules.notifications(for: opened, at: start.advanced(by: .seconds(600))).isEmpty)

  }

}
