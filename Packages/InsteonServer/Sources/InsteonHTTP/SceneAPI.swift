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
    let listing = await service.scenes()
    var meanings: [SceneKey: LinkDataMeaning] = [:]
    for scene in listing.scenes {
      for (index, member) in scene.members.enumerated() {
        meanings[SceneKey(scene: scene, member: index)] = await service.meaning(ofMemberData: member.data, of: member.address, group: scene.number)
      }
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return Response(status: .ok, headers: [.contentType: "application/json"], body: .init(byteBuffer: ByteBuffer(bytes: try encoder.encode(SceneListDTO(listing, meanings: meanings)))))
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
  /// The members the catalog doesn't describe, once each, so a client can say what it can't explain.
  let undescribedMembers: [String]
  /// Whether every database was read and every record has its other half.
  let whole: Bool

  init(_ listing: SceneListing, meanings: [SceneKey: LinkDataMeaning]) {
    scenes = listing.scenes.map { scene in SceneDTO(scene, meanings: meanings) }
    undescribedMembers = Array(Set(listing.scenes.flatMap { scene in
      scene.members.enumerated().filter { meanings[SceneKey(scene: scene, member: $0.offset)] == nil }.map { $0.element.address }
    })).sorted { $0.bytes.lexicographicallyPrecedes($1.bytes) }.map(\.description)
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

  init(_ scene: SceneListing.Scene, meanings: [SceneKey: LinkDataMeaning]) {
    number = Int(scene.number)
    controller = SceneWire.name(scene.controller)
    writable = scene.isWritable
    members = scene.members.enumerated().map { SceneMemberDTO($0.element, meaning: meanings[SceneKey(scene: scene, member: $0.offset)]) }
    halfLinks = scene.halfLinks.map(HalfLinkDTO.init)
  }
}

struct SceneMemberDTO: Encodable {
  let address: String
  let data: [Int]
  /// Whether the catalog says what the bytes mean for this device.
  let described: Bool
  let bytes: [LinkDataByteDTO]

  init(_ member: SceneListing.Member, meaning: LinkDataMeaning?) {
    address = member.address.description
    data = member.data.map(Int.init)
    described = meaning != nil
    bytes = meaning?.bytes.map(LinkDataByteDTO.init) ?? []
  }
}

struct LinkDataByteDTO: Encodable {
  let position: Int
  let name: String
  let label: String?
  let value: Int
  let valueName: String?
  let perGroup: Bool
  /// How sure the catalog is: `observed`, `documented`, `inferred` or `conflicting`.
  let verification: String

  init(_ field: LinkDataField) {
    position = field.position
    name = field.name
    label = field.label
    value = Int(field.value)
    valueName = field.valueName
    perGroup = field.isPerGroup
    verification = field.verification
  }
}

/// Which member of which scene a meaning is for: scenes are told apart by controller and number.
struct SceneKey: Hashable, Sendable {
  let controller: String
  let number: UInt8
  let member: Int

  init(scene: SceneListing.Scene, member: Int) {
    controller = SceneWire.name(scene.controller)
    number = scene.number
    self.member = member
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
