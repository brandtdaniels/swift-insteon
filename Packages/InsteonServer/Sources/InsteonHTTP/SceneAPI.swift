import Foundation
import Hummingbird
import HTTPTypes
import InsteonCore
import InsteonLinking
import InsteonProtocol
import InsteonService

/// Listing the scenes of the home. It needs the `read` scope, which the authentication middleware
/// has already enforced. The service answers from the ALL-Link databases it has cached and sends
/// nothing to hardware.
struct SceneAPI<Service: SceneProviding>: Sendable {
  let service: Service

  func list() async throws -> Response {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return Response(status: .ok, headers: [.contentType: "application/json"], body: .init(byteBuffer: ByteBuffer(bytes: try encoder.encode(SceneListDTO(await service.scenes())))))
  }
}

/// A listing as it goes on the wire. A scene's `controller` is `modem` or a device's address.
struct SceneListDTO: Encodable {
  let version = 1
  let scenes: [SceneDTO]
  let looseHalfLinks: [HalfLinkDTO]
  let unreadable: [String]
  let unlisted: [String]
  let modemUnread: Bool
  /// Whether every database was read and every record has its other half.
  let whole: Bool

  init(_ listing: SceneListing) {
    scenes = listing.scenes.map(SceneDTO.init)
    looseHalfLinks = listing.looseHalfLinks.map(HalfLinkDTO.init)
    unreadable = listing.unreadable.map(\.description)
    unlisted = listing.unlisted.map(\.description)
    modemUnread = listing.isModemUnread
    whole = listing.isWhole
  }
}

struct SceneDTO: Encodable {
  let number: Int
  let controller: String
  let writable: Bool
  let members: [SceneMemberDTO]
  let halfLinks: [HalfLinkDTO]

  init(_ scene: SceneListing.Scene) {
    number = Int(scene.number)
    controller = SceneWire.name(scene.controller)
    writable = scene.isWritable
    members = scene.members.map(SceneMemberDTO.init)
    halfLinks = scene.halfLinks.map(HalfLinkDTO.init)
  }
}

struct SceneMemberDTO: Encodable {
  let address: String
  let data: [Int]

  init(_ member: SceneListing.Member) {
    address = member.address.description
    data = member.data.map(Int.init)
  }
}

struct HalfLinkDTO: Encodable {
  let endpoint: String
  let group: Int
  let address: String
  let role: String
  let data: [Int]

  init(_ half: AllLinkGroupReading.HalfLink) {
    endpoint = SceneWire.name(half.endpoint)
    group = Int(half.record.group.rawValue)
    address = half.record.address.description
    role = half.record.flags.contains(.controller) ? "controller" : "responder"
    data = [half.record.data1, half.record.data2, half.record.data3].map(Int.init)
  }
}

enum SceneWire {
  static func name(_ endpoint: LinkEndpoint) -> String {
    switch endpoint {
    case .modem: "modem"
    case let .device(address): address.description
    }
  }
}
