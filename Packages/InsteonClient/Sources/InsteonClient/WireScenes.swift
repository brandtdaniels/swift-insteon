import InsteonProtocol
import InsteonService

/// A scene list as the service writes it, in the answer to a listing and to a refresh.
struct WireSceneList: Decodable {
  let scenes: [Scene]
  let looseHalfLinks: [HalfLink]
  let unreadable: [Unreadable]
  let unlisted: [String]
  let modemUnread: Bool
  let undescribedMembers: [String]
  let whole: Bool

  struct Scene: Decodable {
    let number: Int
    let controller: String
    let writable: Bool
    let members: [Member]
    let halfLinks: [HalfLink]
  }

  struct Member: Decodable {
    let address: String
    let data: [UInt8]
    let described: Bool
    let bytes: [Byte]
  }

  struct Byte: Decodable {
    let position: Int
    let name: String
    let label: String?
    let value: UInt8
    let valueName: String?
    let perGroup: Bool
    let verification: String
  }

  struct HalfLink: Decodable {
    let endpoint: String
    let group: Int
    let address: String
    let role: String
    let data: [UInt8]
  }

  struct Unreadable: Decodable {
    let address: String
    let reason: String
  }

  /// The list, or a bad response for anything the service's contract doesn't allow. One entry that
  /// can't be read fails the whole list, since a partial list would look complete.
  func list() throws -> SceneList {
    SceneList(
      scenes: try scenes.map { try $0.scene() }, looseHalfLinks: try looseHalfLinks.map { try $0.halfLink() },
      unreadable: try unreadable.map { SceneList.UnreadableDevice(address: try Self.address($0.address), reason: SceneList.UnreadableReason($0.reason)) },
      unlisted: try unlisted.map(Self.address), isModemUnread: modemUnread, undescribedMembers: try undescribedMembers.map(Self.address), isWhole: whole)
  }

  fileprivate static func address(_ text: String) throws -> InsteonAddress {
    guard let address = InsteonAddress(text) else { throw ConnectionPathError.badResponse }
    return address
  }

  fileprivate static func source(_ text: String) throws -> SceneList.Source {
    text == "modem" ? .modem : .device(try address(text))
  }
}

extension WireSceneList.Scene {
  fileprivate func scene() throws -> SceneList.Scene {
    SceneList.Scene(number: number, source: try WireSceneList.source(controller), isWritable: writable, members: try members.map { try $0.member() }, halfLinks: try halfLinks.map { try $0.halfLink() })
  }
}

extension WireSceneList.Member {
  fileprivate func member() throws -> SceneList.Member {
    SceneList.Member(
      address: try WireSceneList.address(address), data: data, isDescribed: described,
      bytes: bytes.map {
        SceneList.Byte(position: $0.position, name: $0.name, label: $0.label, value: $0.value, valueName: $0.valueName, isPerGroup: $0.perGroup, verification: SceneList.Verification($0.verification))
      })
  }
}

extension WireSceneList.HalfLink {
  fileprivate func halfLink() throws -> SceneList.HalfLink {
    let role: SceneList.HalfLink.Role
    switch self.role {
    case "controller": role = .controller
    case "responder": role = .responder
    default: throw ConnectionPathError.badResponse
    }
    return SceneList.HalfLink(endpoint: try WireSceneList.source(endpoint), group: group, address: try WireSceneList.address(address), role: role, data: data)
  }
}

/// A scene run's receipt as the service writes it.
struct WireSceneReceipt: Decodable {
  let scene: Int
  let action: String
  let outcome: String
  let acknowledged: [String]
  let unacknowledged: [String]
  let isComplete: Bool
  let responderCount: Int
  let persistence: String

  /// The receipt, or a bad response for anything the service's contract doesn't allow.
  func receipt() throws -> SceneRunReceipt {
    let action: SceneAction
    switch self.action {
    case "on": action = .on
    case "off": action = .off
    default: throw ConnectionPathError.badResponse
    }
    // A scene's answer only ever says the modem acknowledged sending the group command.
    guard outcome == "acknowledged" else { throw ConnectionPathError.badResponse }
    guard let persistence = PersistenceOutcome(wireName: persistence) else { throw ConnectionPathError.badResponse }
    return SceneRunReceipt(
      scene: scene, action: action, acknowledged: try acknowledged.map(WireSceneList.address), unacknowledged: try unacknowledged.map(WireSceneList.address),
      isComplete: isComplete, responderCount: responderCount, persistence: persistence)
  }
}

extension PersistenceOutcome {
  /// The outcome the service names, or `nil` for a name it doesn't use.
  init?(wireName: String) {
    switch wireName {
    case "notConfigured": self = .notConfigured
    case "notAttempted": self = .notAttempted
    case "saved": self = .saved
    case "failed": self = .failed
    default: return nil
    }
  }
}
