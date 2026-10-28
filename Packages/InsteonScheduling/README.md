# InsteonScheduling

Work out when schedules run, in a home's time zone, through daylight saving changes.

- `Schedule`, `DailyTime` and `Weekday`: a clock time or a time relative to sunrise or sunset, on some days of the week
- `ScheduleCalendar`: the next time a schedule runs, worked out day by day in the home's time zone, so daylight saving changes are handled by the time zone's rules
- `SunTimes`: where sunrise and sunset come from
- `SolarCalculator` and `GeographicCoordinate`: sunrise and sunset worked out for a place with NOAA's equations

See the DocC catalog in `Sources/InsteonScheduling/InsteonScheduling.docc` for the full documentation.
