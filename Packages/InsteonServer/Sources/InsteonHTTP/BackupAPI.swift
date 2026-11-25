import Foundation
import Hummingbird
import HTTPTypes
import InsteonCore
import InsteonService

/// Reading a backup of the cached network. It needs the `admin` scope, which the authentication
/// middleware has already enforced, because the backup lists every device's ALL-Link database and
/// the transports' routes.
///
/// The service answers from its cache and sends nothing to hardware. The notification rules, the
/// routes and the schedules are read from the same places the `/api/v1/notification-rules`,
/// `/api/v1/routes` and `/api/v1/schedules` operations read, so a file that can't be read fails the
/// backup with the same error code instead of leaving it out. Schedules are written as the
/// schedules file writes them, without the time each runs next, which isn't configuration. Timers
/// are left out: a timer is a countdown.
struct BackupAPI<Service: HomeBackupProviding & NotificationRuleManaging & ScheduleManaging>: Sendable {
  let service: Service
  let routes: any RouteStoring

  func get() async throws -> Response {
    let rules = try await service.notificationRules().map(NotificationRuleRecord.init)
    let registered = try await routes.routes()
    let schedules = try await service.schedules().map { ScheduleRecord($0.schedule) }
    let backup = await service.homeBackup().including(
      notificationRules: try rules.map { try JSONDecoder().decode(BackupValue.self, from: JSONEncoder().encode($0)) },
      routes: registered.map { BackupRoute(kind: $0.kind, ticket: $0.ticket) },
      schedules: try schedules.map { try JSONDecoder().decode(BackupValue.self, from: JSONEncoder().encode($0)) }
    )
    return Response(status: .ok, headers: [.contentType: "application/json"], body: .init(byteBuffer: ByteBuffer(bytes: try backup.encoded())))
  }
}
