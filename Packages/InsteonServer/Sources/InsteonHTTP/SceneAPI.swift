import Foundation
import Hummingbird
import HTTPTypes
import InsteonCore
import InsteonLinking
import InsteonProtocol
import InsteonService
import Logging

/// Listing the scenes of the network. It needs the `read` scope, which the authentication middleware
/// has already enforced. The service answers from the ALL-Link databases it has cached and sends
/// nothing to hardware.
struct SceneAPI<Service: SceneProviding>: Sendable {
  let service: Service
  let logger: Logger

  func list() async throws -> Response {
    try await answer(await service.scenes())
  }

  /// Reads the databases from the hardware and answers with the listing a read of the cache gives
  /// afterward. It needs the `control` scope, which the authentication middleware has already
  /// enforced, and the request marker, so a page can't start a read of the hardware by accident.
  func refresh(_ request: Request) async throws -> Response {
    try HTTPBody.requireMarker(request)
    let listing: SceneListing
    do {
      listing = try await service.refreshScenes()
    } catch {
      // A refresh only reads, so a failure is classified as a read: safe to repeat, nothing sent.
      throw CommandFailure(action: .status, underlying: error)
    }
    // One line for each device left unread, with the address a person needs to find it.
    for address in listing.unreadable {
      logger.warning("scene refresh left a device unread", metadata: ["address": "\(address)", "reason": "\(listing.unreadableReason(of: address).rawValue)"])
    }
    return try await answer(listing)
  }

  private func answer(_ listing: SceneListing) async throws -> Response {
    // One question for each distinct member, so a device that holds several records of the same
    // bytes is not asked about again.
    var asked: [MemberQuestion: LinkDataMeaning?] = [:]
    var meanings: [[LinkDataMeaning?]] = []
    for scene in listing.scenes {
      var row: [LinkDataMeaning?] = []
      for member in scene.members {
        let question = MemberQuestion(address: member.address, data: member.data, group: scene.number)
        if asked[question] == nil {
          asked[question] = .some(await service.meaning(ofMemberData: member.data, of: member.address, group: scene.number))
        }
        row.append(asked[question] ?? nil)
      }
      meanings.append(row)
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return Response(status: .ok, headers: [.contentType: "application/json"], body: .init(byteBuffer: ByteBuffer(bytes: try encoder.encode(SceneListDTO(listing, meanings: meanings)))))
  }
}

/// What the service is asked about one member: the same question has the same answer.
private struct MemberQuestion: Hashable {
  let address: InsteonAddress
  let data: [UInt8]
  let group: UInt8
}

/// A listing as it goes on the wire. A scene's `controller` is `modem` or a device's address.
struct SceneListDTO: Encodable {
  let version = 1
  let scenes: [SceneDTO]
  let looseHalfLinks: [HalfLinkDTO]
  /// Each device whose database was not read, with why.
  let unreadable: [UnreadableDTO]
  let unlisted: [String]
  let modemUnread: Bool
  /// The members the catalog doesn't describe, once each, so a client can say what it can't explain.
  let undescribedMembers: [String]
  /// Whether every database was read and every record has its other half.
  let whole: Bool

  /// - Parameter meanings: What each member's bytes mean, in the order of `listing.scenes` and each
  ///   scene's `members`; `nil` for a member the catalog doesn't describe.
  init(_ listing: SceneListing, meanings: [[LinkDataMeaning?]]) {
    scenes = zip(listing.scenes, meanings).map { SceneDTO($0, meanings: $1) }
    var undescribed: Set<InsteonAddress> = []
    for (scene, row) in zip(listing.scenes, meanings) {
      for (member, meaning) in zip(scene.members, row) where meaning == nil { undescribed.insert(member.address) }
    }
    undescribedMembers = undescribed.sorted { $0.bytes.lexicographicallyPrecedes($1.bytes) }.map(\.description)
    looseHalfLinks = listing.looseHalfLinks.map(HalfLinkDTO.init)
    unreadable = listing.unreadable.map { UnreadableDTO(address: $0.description, reason: listing.unreadableReason(of: $0).rawValue) }
    unlisted = listing.unlisted.map(\.description)
    modemUnread = listing.isModemUnread
    whole = listing.isWhole
  }
}

struct UnreadableDTO: Encodable {
  let address: String
  let reason: String
}

struct SceneDTO: Encodable {
  let number: Int
  let controller: String
  let writable: Bool
  let members: [SceneMemberDTO]
  let halfLinks: [HalfLinkDTO]

  init(_ scene: SceneListing.Scene, meanings: [LinkDataMeaning?]) {
    number = Int(scene.number)
    controller = SceneWire.name(scene.controller)
    writable = scene.isWritable
    members = zip(scene.members, meanings).map { SceneMemberDTO($0, meaning: $1) }
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
