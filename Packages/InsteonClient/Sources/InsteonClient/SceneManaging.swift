import InsteonCore
import InsteonLinking
import InsteonProtocol
import InsteonService

/// The calls a screen needs to list, read and run scenes, the same on a connection to a service and
/// on a service in the same process.
public protocol SceneManaging: Sendable {

  /// The scenes from the ALL-Link databases the service holds. Nothing is sent to hardware.
  func scenes() async throws -> SceneList

  /// Reads the ALL-Link databases from the hardware, then answers the scenes.
  func refreshScenes() async throws -> SceneList

  /// Runs a scene the modem controls, once.
  ///
  /// - Parameters:
  ///   - number: The scene's ALL-Link group number, from 1 through 254.
  ///   - action: What to tell the scene.
  ///   - idempotencyKey: A token that makes a repeat of the same run return the recorded answer
  ///     and send nothing, or `nil` to make one for this call.
  func runScene(_ number: Int, action: SceneAction, idempotencyKey: String?) async throws -> SceneRunReceipt

}

extension SceneManaging {

  /// Runs a scene the modem controls, once, with a key made for the call.
  public func runScene(_ number: Int, action: SceneAction) async throws -> SceneRunReceipt {
    try await runScene(number, action: action, idempotencyKey: nil)
  }

}

extension ClientConnection: SceneManaging {}

/// A service in this process, answering the calls of ``SceneManaging`` in the client's shapes.
///
/// It maps the service's listing, with what the Insteon device catalog says each member's bytes
/// mean, and its receipt. It adds no behavior: the service decides what a scene is, whether it can
/// run and what a refusal means.
public struct ServiceScenes<Service: SceneProviding>: SceneManaging {

  private let service: Service

  /// Creates the adapter.
  ///
  /// - Parameter service: The service that lists and runs scenes.
  public init(_ service: Service) {
    self.service = service
  }

  public func scenes() async throws -> SceneList {
    await list(of: await service.scenes())
  }

  public func refreshScenes() async throws -> SceneList {
    await list(of: try await service.refreshScenes())
  }

  /// A service runs each scene once and has no use for a key: a run in this process has no answer to lose.
  ///
  /// - Throws: ``ConnectionError/invalidScene`` for a number that isn't a group from 1 through 254,
  ///   before anything is sent, then the service's own errors.
  public func runScene(_ number: Int, action: SceneAction, idempotencyKey: String? = nil) async throws -> SceneRunReceipt {
    guard let group = UInt8(exactly: number), (1...254).contains(group) else { throw ConnectionError.invalidScene }
    let receipt = try await service.runScene(SceneCommand(number: group, action: action == .on ? .on : .off))
    return SceneRunReceipt(
      scene: Int(receipt.scene), action: receipt.action == .on ? .on : .off, acknowledged: receipt.acknowledged, unacknowledged: receipt.unacknowledged,
      isComplete: receipt.isComplete, responderCount: receipt.responderCount, persistence: receipt.persistence)
  }

  private func list(of listing: SceneListing) async -> SceneList {
    var undescribed: Set<InsteonAddress> = []
    var scenes: [SceneList.Scene] = []
    for scene in listing.scenes {
      var members: [SceneList.Member] = []
      for member in scene.members {
        let meaning = await service.meaning(ofMemberData: member.data, of: member.address, group: scene.number)
        if meaning == nil { undescribed.insert(member.address) }
        members.append(SceneList.Member(address: member.address, data: member.data, isDescribed: meaning != nil, bytes: meaning?.bytes.map(Self.byte) ?? []))
      }
      scenes.append(SceneList.Scene(number: Int(scene.number), source: Self.source(scene.controller), isWritable: scene.isWritable, members: members, halfLinks: scene.halfLinks.map(Self.halfLink)))
    }
    return SceneList(
      scenes: scenes, looseHalfLinks: listing.looseHalfLinks.map(Self.halfLink),
      unreadable: listing.unreadable.map { SceneList.UnreadableDevice(address: $0, reason: Self.reason(listing.unreadableReason(of: $0))) },
      unlisted: listing.unlisted, isModemUnread: listing.isModemUnread,
      undescribedMembers: undescribed.sorted { $0.bytes.lexicographicallyPrecedes($1.bytes) }, isWhole: listing.isWhole)
  }

  private static func source(_ endpoint: LinkEndpoint) -> SceneList.Source {
    switch endpoint {
    case .modem: .modem
    case let .device(address): .device(address)
    }
  }

  private static func byte(_ field: LinkDataField) -> SceneList.Byte {
    SceneList.Byte(position: field.position, name: field.name, label: field.label, value: field.value, valueName: field.valueName, isPerGroup: field.isPerGroup, verification: SceneList.Verification(field.verification))
  }

  private static func halfLink(_ half: AllLinkGroupReading.HalfLink) -> SceneList.HalfLink {
    SceneList.HalfLink(
      endpoint: source(half.endpoint), group: Int(half.record.group.rawValue), address: half.record.address,
      role: half.record.flags.contains(.controller) ? .controller : .responder, data: [half.record.data1, half.record.data2, half.record.data3])
  }

  private static func reason(_ reason: BackupUnreadableReason) -> SceneList.UnreadableReason {
    SceneList.UnreadableReason(reason.rawValue)
  }
}
