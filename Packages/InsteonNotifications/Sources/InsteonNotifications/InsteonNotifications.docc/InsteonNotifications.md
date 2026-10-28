# ``InsteonNotifications``

Let people know when their devices do something they care about.

## Overview

A ``NotificationRule`` says what someone wants to hear about: a device reporting an event its
device profile names, such as a leak sensor turning wet or a door opening; a device sending a
group command, such as a switch turned on from its paddle; or a sensor going quiet. A
``NotificationRuleSet`` checks the events a `DeviceEventInterpreter` reads, and the devices a
`HeartbeatMonitor` finds silent, against a home's rules, and returns the
``DeviceNotification``s to deliver.

```swift
var interpreter = DeviceEventInterpreter<ContinuousClock.Instant>(catalog: try .bundled())
var rules = NotificationRuleSet<ContinuousClock.Instant>(rules: [
  NotificationRule(id: "basement-leak", name: "Basement leak", trigger: .event("wet", from: basementSensor)),
  NotificationRule(id: "front-door", name: "Front door opened", trigger: .event("opened", from: frontDoor), cooldown: .seconds(300)),
])

for await reply in await modem.replies() {
  guard case let .messageReceived(message) = reply else { continue }

  for event in interpreter.events(from: message, at: .now) {
    for notification in rules.notifications(for: event, at: .now) {
      await deliver(notification.rule.name)
    }
  }
}
```

A rule's cooldown keeps a busy device, such as a motion sensor in a hallway, from notifying on
every pass, and a silence rule fires once each time its device goes quiet. Delivering a
notification, such as with a push notification or an email, is up to the app.

## Topics

### Rules

- ``NotificationRule``
- ``NotificationRuleID``
- ``NotificationTrigger``

### Checking events

- ``NotificationRuleSet``
- ``DeviceNotification``
