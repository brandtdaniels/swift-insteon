import InsteonNetworking
import InsteonProtocol

extension Hub {

  /// Reads a page of a Hub 2242's slots: the device and group each is for, and its state.
  ///
  /// - Parameter page: The page, from 1 through 16.
  /// - Returns: The page's slots, in order.
  /// - Throws: ``HubError`` if the Hub rejected the request or the page couldn't be parsed, or
  ///   the HTTP client's error.
  public func slotStatuses(page: Int) async throws -> [HubSlotStatus] {

    precondition((1...16).contains(page), "A Hub's slot pages are 1 through 16.")

    let response = try await perform(.readSlots(page: page))

    return try HubSlotStatus.page(String(decoding: response.body, as: UTF8.self), page: page)

  }

  /// Writes a timer into a Hub 2242's slot, which the Hub then runs on its own.
  ///
  /// The Hub's timer request also carries the slot's state and its device and group, so the slot's
  /// page is read first and those are written back unchanged. Set what the timer sends with
  /// ``Hub/setCommands(_:for:)``.
  ///
  /// ```swift
  /// try await hub.setCommands(
  ///   HubSlotCommands(
  ///     on: .sendStandardMessage(StandardMessage(to: porchLight, command: StandardDirectCommand.on(level: 0xFF))),
  ///     off: .sendStandardMessage(StandardMessage(to: porchLight, command: StandardDirectCommand.off))
  ///   ),
  ///   for: slot
  /// )
  /// try await hub.setTimer(HubTimer(name: porch, on: .sunset, off: .clock(elevenPM), days: .everyDay), for: slot)
  /// ```
  ///
  /// - Parameters:
  ///   - timer: The timer. One with no times and no days removes the slot's timer.
  ///   - slot: The slot.
  /// - Throws: ``HubError/reservedSlot(_:)`` for a slot past 239,
  ///   ``HubError`` if the Hub rejected a request or the slot's page couldn't be parsed, or the
  ///   HTTP client's error.
  public func setTimer(_ timer: HubTimer, for slot: HubSlot) async throws {

    guard slot.holdsTimers else {

      throw HubError.reservedSlot(slot)

    }

    let status = try await slotStatuses(page: slot.page).first { $0.slot == slot }

    _ = try await perform(.writeTimer(slot, fields: Self.timerFields(timer, status: status)))

  }

  /// Sets the commands a Hub 2242 sends when a slot's timer turns it on and off.
  ///
  /// - Parameters:
  ///   - commands: The commands, or `nil` to send none.
  ///   - slot: The slot.
  /// - Throws: ``HubError/reservedSlot(_:)`` for a slot past 239,
  ///   ``HubError`` if the Hub rejected the request, or the HTTP client's error.
  public func setCommands(_ commands: HubSlotCommands?, for slot: HubSlot) async throws {

    guard slot.holdsTimers else {

      throw HubError.reservedSlot(slot)

    }

    _ = try await perform(.writeCommands(slot, commands))

  }

  /// Sets a Hub 2242's clock, which its timers run by.
  ///
  /// The Hub keeps the time of day and the day of the week, but not the date or time zone.
  ///
  /// - Parameters:
  ///   - time: The time of day.
  ///   - day: The day of the week.
  /// - Throws: ``HubError`` if the Hub rejected a request, or the HTTP client's error.
  public func setClock(to time: HubClockTime, on day: HubWeekday) async throws {

    _ = try await perform(.setTime(time))
    _ = try await perform(.setWeekday(day))

  }

  /// The timer request's fields after the slot number, in the order the Hub takes
  /// them: the name, the on and off times with fields that are always the same between them, the
  /// days Monday through Sunday, the slot's active, on and off flags, the slot's device and
  /// group, whether the slot raises an alert, and the kinds of the on and off times.
  static func timerFields(_ timer: HubTimer, status: HubSlotStatus?) -> String {

    let flags = status?.flags ?? []
    let target = status.map { $0.device.bytes + [$0.group.rawValue] } ?? [0, 0, 0, 0]
    // The app writes the alert field when the slot is used, raises an alert and is on.
    let alert = flags.isSuperset(of: [.used, .alert, .on])

    var fields = [timer.name.rawValue, "2", "t", text(of: timer.on), "ff", text(of: timer.off), "ff"]
    fields += HubWeekday.allCases.map { flag(timer.days.contains($0)) }
    fields += [flag(flags.contains(.active)), flag(flags.contains(.on)), flag(flags.contains(.off)), "t"]
    fields += [target.map(\.hexDigits).joined(), "t"]

    // The kinds of the two times follow the alert field with no separator.
    return fields.joined(separator: "=") + "=" + flag(alert) + kind(of: timer.on) + kind(of: timer.off)

  }

  private static func flag(_ value: Bool) -> String {

    value ? "t" : "f"

  }

  /// A time's field: the time of day, or `00:00` for sunrise, sunset or never.
  private static func text(of time: HubTimerTime?) -> String {

    if case let .clock(clock) = time {

      return clock.timerText

    }

    return "00:00"

  }

  /// A time's kind: 1 for sunset, 2 for a time of day or never, 3 for sunrise.
  private static func kind(of time: HubTimerTime?) -> String {

    switch time {
    case .sunset: "1"
    case .sunrise: "3"
    case .clock, nil: "2"
    }

  }

}
