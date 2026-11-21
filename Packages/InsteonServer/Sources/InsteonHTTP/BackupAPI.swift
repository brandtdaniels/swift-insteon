import Foundation
import Hummingbird
import HTTPTypes
import InsteonCore
import InsteonService

/// Reading a backup of the cached network. It needs the `admin` scope, which the authentication
/// middleware has already enforced, because the backup lists every device's ALL-Link database and
/// the transports' routes.
///
/// The service answers from its cache and sends nothing to hardware. The notification rules and the
/// routes are read from the same places the `/api/v1/notification-rules` and `/api/v1/routes`
/// operations read, so a rules or routes file that can't be read fails the backup with the same
/// error code instead of leaving them out.
struct BackupAPI<Service: HomeBackupProviding & NotificationRuleManaging>: Sendable {
  let service: Service
  let routes: any RouteStoring

  func get() async throws -> Response {
    let rules = try await service.notificationRules().map(NotificationRuleRecord.init)
    let registered = try await routes.routes()
    let backup = await service.homeBackup().including(
      notificationRules: try rules.map { try JSONDecoder().decode(BackupValue.self, from: JSONEncoder().encode($0)) },
      routes: registered.map { BackupRoute(kind: $0.kind, ticket: $0.ticket) }
    )
    return Response(status: .ok, headers: [.contentType: "application/json"], body: .init(byteBuffer: ByteBuffer(bytes: try backup.encoded())))
  }
}
