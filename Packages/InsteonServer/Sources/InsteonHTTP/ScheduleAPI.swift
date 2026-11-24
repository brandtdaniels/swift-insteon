import Foundation
import Hummingbird
import HTTPTypes
import InsteonProtocol
import InsteonScheduling
import InsteonService

/// Listing, storing and removing schedules and timers. Reading needs the `read` scope and writing the `admin`
/// scope, which the authentication middleware has already enforced.
struct ScheduleAPI<Service: ScheduleManaging>: Sendable {
  let service: Service

  func listSchedules() async throws -> Response {
    try json(ScheduleListDTO(schedules: try await service.schedules().map(ScheduleRecord.init)))
  }

  func putSchedule(_ request: Request, id: String?) async throws -> Response {
    guard HTTPBody.mediaType(request) == "application/json" else { throw HTTPInputError.unsupportedMedia }
    try HTTPBody.requireMarker(request)
    guard let id else { throw ScheduleRequestError.malformed }
    let schedule = try ScheduleBody(try await HTTPBody.read(request)).schedule(id: id)
    return try json(ScheduleStoredDTO(schedule: ScheduleRecord(try await service.putSchedule(schedule))))
  }

  func removeSchedule(_ request: Request, id: String?) async throws -> Response {
    try HTTPBody.requireMarker(request)
    guard let id else { throw ScheduleError.unknownSchedule }
    try await service.removeSchedule(id: id)
    return Response(status: .noContent)
  }

  func listTimers() async throws -> Response {
    try json(TimerListDTO(timers: try await service.timers().map(TimerRecord.init)))
  }

  func putTimer(_ request: Request, id: String?) async throws -> Response {
    guard HTTPBody.mediaType(request) == "application/json" else { throw HTTPInputError.unsupportedMedia }
    try HTTPBody.requireMarker(request)
    guard let id else { throw TimerRequestError.malformed }
    let timer = try TimerBody(try await HTTPBody.read(request)).timer(id: id)
    return try json(TimerStoredDTO(timer: TimerRecord(try await service.putTimer(timer))))
  }

  func removeTimer(_ request: Request, id: String?) async throws -> Response {
    try HTTPBody.requireMarker(request)
    guard let id else { throw ScheduleError.unknownTimer }
    try await service.removeTimer(id: id)
    return Response(status: .noContent)
  }

  private func json(_ value: some Encodable) throws -> Response {
    Response(status: .ok, headers: [.contentType: "application/json"], body: .init(byteBuffer: ByteBuffer(bytes: try JSONEncoder().encode(value))))
  }
}

/// A request body that isn't a schedule.
enum ScheduleRequestError: Error { case malformed }

/// A request body that isn't a timer.
enum TimerRequestError: Error { case malformed }

// MARK: Records

/// A scheduled action as the API and the schedules file write it.
public struct ScheduledActionRecord: Codable, Sendable, Equatable {
  /// The device's address.
  public let device: String
  /// `on` or `off`.
  public let action: String
  /// The percentage for `on`, when the schedule names one.
  public let levelPercent: Int?

  /// Writes an action.
  public init(_ action: ScheduledAction) {
    device = action.device.description
    switch action.kind {
    case let .on(level): self.action = ScheduleActionName.on.rawValue; levelPercent = level
    case .off: self.action = ScheduleActionName.off.rawValue; levelPercent = nil
    }
  }

  /// The action this record describes.
  /// - Throws: An error when the record isn't an action.
  public func scheduledAction() throws -> ScheduledAction {
    guard let address = InsteonAddress(device) else { throw ScheduleRequestError.malformed }
    switch ScheduleActionName(rawValue: action) {
    case .on: return ScheduledAction(device: address, kind: .on(levelPercent: levelPercent))
    case .off:
      guard levelPercent == nil else { throw ScheduleRequestError.malformed }
      return ScheduledAction(device: address, kind: .off)
    case nil: throw ScheduleRequestError.malformed
    }
  }
}

/// A schedule's time of day as the API and the schedules file write it.
public struct ScheduleTimeRecord: Codable, Sendable, Equatable {
  /// `clock`, `sunrise` or `sunset`.
  public let kind: String
  /// The hour of a `clock` time, from 0 through 23.
  public let hour: Int?
  /// The minute of a `clock` time, from 0 through 59.
  public let minute: Int?
  /// The seconds after sunrise or sunset, negative for before.
  public let offsetSeconds: Int?

  /// Writes a time of day.
  public init(_ time: DailyTime) {
    switch time {
    case let .clock(hour, minute): kind = ScheduleTimeKind.clock.rawValue; self.hour = hour; self.minute = minute; offsetSeconds = nil
    case let .sunrise(offset): kind = ScheduleTimeKind.sunrise.rawValue; hour = nil; minute = nil; offsetSeconds = Int(offset.components.seconds)
    case let .sunset(offset): kind = ScheduleTimeKind.sunset.rawValue; hour = nil; minute = nil; offsetSeconds = Int(offset.components.seconds)
    }
  }

  /// The time of day this record describes.
  /// - Throws: An error when the record isn't a time of day.
  public func time() throws -> DailyTime {
    switch ScheduleTimeKind(rawValue: kind) {
    case .clock:
      guard let hour, let minute, offsetSeconds == nil else { throw ScheduleRequestError.malformed }
      return .clock(hour: hour, minute: minute)
    case .sunrise:
      guard hour == nil, minute == nil else { throw ScheduleRequestError.malformed }
      return .sunrise(offset: .seconds(offsetSeconds ?? 0))
    case .sunset:
      guard hour == nil, minute == nil else { throw ScheduleRequestError.malformed }
      return .sunset(offset: .seconds(offsetSeconds ?? 0))
    case nil: throw ScheduleRequestError.malformed
    }
  }
}

/// A schedule as the API and the schedules file write it.
public struct ScheduleRecord: Codable, Sendable, Equatable {
  /// The days and the time of day.
  public struct When: Codable, Sendable, Equatable {
    /// The time of day.
    public let time: ScheduleTimeRecord
    /// The weekdays, in the week's order.
    public let weekdays: [String]
  }

  /// The schedule's identifier.
  public let id: String
  /// The schedule's name.
  public let name: String
  /// Whether it runs at all.
  public let enabled: Bool
  /// The days and the time of day.
  public let when: When
  /// What it sends.
  public let action: ScheduledActionRecord
  /// Whether a missed run less than 15 minutes late still runs.
  public let catchUp: Bool
  /// When it runs next, as ISO 8601, or `nil`. The schedules file leaves it out.
  public let nextRun: String?

  init(_ entry: ScheduleEntry) {
    self.init(entry.schedule, nextRun: entry.nextRun)
  }

  private enum CodingKeys: String, CodingKey { case id, name, enabled, when, action, catchUp, nextRun }

  /// Writes `nextRun` as `null` when there is none, as the API describes it.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(name, forKey: .name)
    try container.encode(enabled, forKey: .enabled)
    try container.encode(when, forKey: .when)
    try container.encode(action, forKey: .action)
    try container.encode(catchUp, forKey: .catchUp)
    try container.encode(nextRun, forKey: .nextRun)
  }

  /// Writes a schedule, with the time it runs next when it has one.
  public init(_ schedule: ServiceSchedule, nextRun: Date? = nil) {
    id = schedule.id
    name = schedule.name
    enabled = schedule.isEnabled
    when = When(time: ScheduleTimeRecord(schedule.when.time), weekdays: schedule.when.weekdays.sorted { $0.rawValue < $1.rawValue }.map { WeekdayName.allCases[$0.rawValue - 1].rawValue })
    action = ScheduledActionRecord(schedule.action)
    catchUp = schedule.catchUp
    self.nextRun = nextRun.map { ISO8601DateFormatter().string(from: $0) }
  }

  /// The schedule this record describes.
  /// - Throws: An error when the record isn't a schedule.
  public func schedule() throws -> ServiceSchedule {
    try Self.schedule(id: id, name: name, enabled: enabled, when: when, action: action, catchUp: catchUp)
  }

  static func schedule(id: String, name: String, enabled: Bool, when: When, action: ScheduledActionRecord, catchUp: Bool) throws -> ServiceSchedule {
    var weekdays = Set<Weekday>()
    for name in when.weekdays {
      guard let day = WeekdayName(rawValue: name), let weekday = Weekday(rawValue: WeekdayName.allCases.firstIndex(of: day)! + 1), weekdays.insert(weekday).inserted else { throw ScheduleRequestError.malformed }
    }
    return ServiceSchedule(id: id, name: name, isEnabled: enabled, when: Schedule(time: try when.time.time(), weekdays: weekdays), action: try action.scheduledAction(), catchUp: catchUp)
  }
}

/// A timer as the API and the schedules file write it.
public struct TimerRecord: Codable, Sendable, Equatable {
  /// The timer's identifier.
  public let id: String
  /// The timer's name.
  public let name: String
  /// How long after it started it fires.
  public let delaySeconds: Int
  /// What it sends.
  public let action: ScheduledActionRecord
  /// When it fires, by the service's clock, as ISO 8601.
  public let dueAt: String?
  /// The seconds left, rounded up.
  public let remainingSeconds: Int?

  init(_ entry: TimerEntry) {
    id = entry.timer.id
    name = entry.timer.name
    delaySeconds = entry.timer.delaySeconds
    action = ScheduledActionRecord(entry.timer.action)
    dueAt = ISO8601DateFormatter().string(from: entry.dueAt)
    remainingSeconds = entry.remainingSeconds
  }

}

struct ScheduleListDTO: Encodable {
  let version = 1
  let schedules: [ScheduleRecord]
}

struct ScheduleStoredDTO: Encodable {
  let version = 1
  let schedule: ScheduleRecord
}

struct TimerListDTO: Encodable {
  let version = 1
  let timers: [TimerRecord]
}

struct TimerStoredDTO: Encodable {
  let version = 1
  let timer: TimerRecord
}

// MARK: Request bodies

/// Reads the pieces of a JSON object strictly: a field of another type or a field nobody asked for refuses it.
struct StrictObject<Failure: Error> {
  let object: [String: Any]
  let failure: Failure

  init(_ value: Any?, allowing keys: Set<String>, requiring required: Set<String> = [], failure: Failure) throws {
    guard let object = value as? [String: Any], Set(object.keys).isSubset(of: keys), required.isSubset(of: Set(object.keys)) else { throw failure }
    self.object = object
    self.failure = failure
  }

  func string(_ key: String) throws -> String? {
    guard let value = object[key] else { return nil }
    guard let text = value as? String else { throw failure }
    return text
  }

  func integer(_ key: String) throws -> Int? {
    guard let value = object[key] else { return nil }
    guard let number = value as? NSNumber, String(cString: number.objCType) != "c", number.doubleValue == Double(number.intValue) else { throw failure }
    return number.intValue
  }

  func boolean(_ key: String) throws -> Bool? {
    guard let value = object[key] else { return nil }
    guard let number = value as? NSNumber, String(cString: number.objCType) == "c" else { throw failure }
    return number.boolValue
  }

  func nested(_ key: String, allowing keys: Set<String>, requiring required: Set<String> = []) throws -> StrictObject? {
    guard let value = object[key] else { return nil }
    return try StrictObject(value, allowing: keys, requiring: required, failure: failure)
  }

  func strings(_ key: String) throws -> [String]? {
    guard let value = object[key] else { return nil }
    guard let list = value as? [Any] else { throw failure }
    return try list.map { element in
      guard let text = element as? String else { throw failure }
      return text
    }
  }
}

private func actionRecord(from object: StrictObject<some Error>?) throws -> ScheduledActionRecord? {
  guard let object else { return nil }
  guard let device = try object.string("device"), let action = try object.string("action") else { throw object.failure }
  return ScheduledActionRecord(device: device, action: action, levelPercent: try object.integer("levelPercent"))
}

extension ScheduledActionRecord {
  fileprivate init(device: String, action: String, levelPercent: Int?) {
    self.device = device
    self.action = action
    self.levelPercent = levelPercent
  }
}

/// The body of a request to store a schedule. Unknown fields, at any level, are refused.
struct ScheduleBody {
  private let name: String
  private let enabled: Bool
  private let when: ScheduleRecord.When
  private let action: ScheduledActionRecord
  private let catchUp: Bool

  init(_ data: Data) throws {
    let failure = ScheduleRequestError.malformed
    let top = try StrictObject(try? JSONSerialization.jsonObject(with: data), allowing: ["name", "enabled", "when", "action", "catchUp"], requiring: ["name", "when", "action"], failure: failure)
    guard let name = try top.string("name"),
          let whenObject = try top.nested("when", allowing: ["time", "weekdays"], requiring: ["time"]),
          let timeObject = try whenObject.nested("time", allowing: ["kind", "hour", "minute", "offsetSeconds"], requiring: ["kind"]),
          let kind = try timeObject.string("kind"),
          let actionRecord = try actionRecord(from: try top.nested("action", allowing: ["device", "action", "levelPercent"], requiring: ["device", "action"])) else { throw failure }
    self.name = name
    enabled = try top.boolean("enabled") ?? true
    catchUp = try top.boolean("catchUp") ?? false
    action = actionRecord
    when = ScheduleRecord.When(
      time: ScheduleTimeRecord(kind: kind, hour: try timeObject.integer("hour"), minute: try timeObject.integer("minute"), offsetSeconds: try timeObject.integer("offsetSeconds")),
      weekdays: try whenObject.strings("weekdays") ?? WeekdayName.allCases.map(\.rawValue)
    )
  }

  func schedule(id: String) throws -> ServiceSchedule {
    try ScheduleRecord.schedule(id: id, name: name, enabled: enabled, when: when, action: action, catchUp: catchUp)
  }
}

extension ScheduleTimeRecord {
  fileprivate init(kind: String, hour: Int?, minute: Int?, offsetSeconds: Int?) {
    self.kind = kind
    self.hour = hour
    self.minute = minute
    self.offsetSeconds = offsetSeconds
  }
}

/// The body of a request to start a timer. Unknown fields, at any level, are refused.
struct TimerBody {
  private let name: String
  private let delaySeconds: Int
  private let action: ScheduledActionRecord

  init(_ data: Data) throws {
    let failure = TimerRequestError.malformed
    let top = try StrictObject(try? JSONSerialization.jsonObject(with: data), allowing: ["name", "delaySeconds", "action"], requiring: ["name", "delaySeconds", "action"], failure: failure)
    guard let name = try top.string("name"), let delay = try top.integer("delaySeconds"),
          let actionRecord = try actionRecord(from: try top.nested("action", allowing: ["device", "action", "levelPercent"], requiring: ["device", "action"])) else { throw failure }
    self.name = name
    delaySeconds = delay
    action = actionRecord
  }

  func timer(id: String) throws -> ServiceTimer {
    do { return ServiceTimer(id: id, name: name, delaySeconds: delaySeconds, action: try action.scheduledAction()) } catch { throw TimerRequestError.malformed }
  }
}
