# ``InsteonScheduling``

Work out when schedules run, in a home's time zone, through daylight saving changes.

## Overview

The INSTEON Hub 2 kept its schedules in Insteon's cloud, and only the Hub 1 ran timers of its
own, so a schedule today belongs to an app that stays running at home. ``ScheduleCalendar``
works out when each ``Schedule`` next runs: at a clock time or relative to sunrise or sunset,
on some days of the week.

Times are worked out in the home's time zone with the system calendar, so daylight saving is
handled by the time zone's own rules: a schedule for 6:30 p.m. runs at 6:30 p.m. local time
all year. On the days the clocks change, a time the clocks skip runs as long after the change
as it was meant to be after the hour, and a time that happens twice runs the first time.

```swift
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "America/Denver")!

let schedules = ScheduleCalendar(calendar: calendar)
let porchLights = Schedule(time: .clock(hour: 18, minute: 30))

// Each run is looked for after the last, so a sleep that wakes early can't repeat it.
var last = Date.now

while let next = schedules.nextRun(of: porchLights, after: last) {
  try await Task.sleep(for: .seconds(max(0, next.timeIntervalSinceNow)))

  do {
    try await modem.sendAllLinkCommand(group: 0x01, command: StandardDirectCommand.on(level: 0xFF).command)
  } catch {
    // Report the failure, and keep the schedule going.
  }

  last = next
}
```

Sunrise and sunset come from a ``SunTimes`` the app supplies; this package doesn't calculate
them.

## Topics

### Schedules

- ``Schedule``
- ``DailyTime``
- ``Weekday``

### Working out runs

- ``ScheduleCalendar``
- ``SunTimes``
