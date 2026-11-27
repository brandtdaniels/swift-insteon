import InsteonProtocol
import InsteonService

/// The scenes of an Insteon network as a service lists them, and what could not be read.
///
/// A scene is a group the modem controls, with its members and what each member stores. A list is
/// ``isWhole`` only when every database was read and every record has its other half, so a screen
/// never shows an incomplete scene as a complete one.
public struct SceneList: Equatable, Sendable {

  /// A scene's source: what starts it.
  public enum Source: Equatable, Sendable {
    /// The modem starts the scene. A client can run it.
    case modem
    /// A device starts the scene, as a keypad button does. It is listed and watched, not run.
    case device(InsteonAddress)
    /// A kind of source the service names that this library has no case for, kept as the service wrote it.
    case other(String)
  }

  /// How sure the Insteon device catalog is of what a data byte means.
  public enum Verification: Equatable, Sendable {
    /// Seen on hardware.
    case observed
    /// Stated in a public document.
    case documented
    /// Worked out from related facts.
    case inferred
    /// Sources disagree.
    case conflicting
    /// Something the service says that this library has no case for, kept as the service wrote it.
    case other(String)

    init(_ name: String) {
      switch name {
      case "observed": self = .observed
      case "documented": self = .documented
      case "inferred": self = .inferred
      case "conflicting": self = .conflicting
      default: self = .other(name)
      }
    }
  }

  /// One of a member's stored data bytes, with what the catalog says it means.
  public struct Byte: Equatable, Sendable {
    /// Which data byte this is, from 1 through 3.
    public let position: Int
    /// The catalog's name for the byte, such as `onLevel`.
    public let name: String
    /// A name for a person, when the catalog has one.
    public let label: String?
    /// The byte's value.
    public let value: UInt8
    /// The catalog's name for the value, such as `On`, when it has one.
    public let valueName: String?
    /// Whether the byte names the member's own group, so it differs for each scene it joins.
    public let isPerGroup: Bool
    /// How sure the catalog is.
    public let verification: Verification

    /// Creates a byte.
    public init(position: Int, name: String, label: String?, value: UInt8, valueName: String?, isPerGroup: Bool, verification: Verification) {
      self.position = position
      self.name = name
      self.label = label
      self.value = value
      self.valueName = valueName
      self.isPerGroup = isPerGroup
      self.verification = verification
    }
  }

  /// A device that answers a scene.
  public struct Member: Equatable, Sendable {
    /// The member's address.
    public let address: InsteonAddress
    /// The three data bytes the member stores for the scene, as the ALL-Link record holds them.
    public let data: [UInt8]
    /// Whether the catalog says what the bytes mean for this device. When it doesn't, ``bytes``
    /// is empty and ``data`` is all there is to show.
    public let isDescribed: Bool
    /// What each byte means, when ``isDescribed``.
    public let bytes: [Byte]

    /// Creates a member.
    public init(address: InsteonAddress, data: [UInt8], isDescribed: Bool, bytes: [Byte]) {
      self.address = address
      self.data = data
      self.isDescribed = isDescribed
      self.bytes = bytes
    }
  }

  /// An ALL-Link record whose other half is missing, so a link is not complete.
  public struct HalfLink: Equatable, Sendable {
    /// Which role a record has.
    public enum Role: Equatable, Sendable {
      /// The record is a controller's.
      case controller
      /// The record is a responder's.
      case responder
    }

    /// The database the record is in: the modem or a device.
    public let endpoint: Source
    /// The record's ALL-Link group.
    public let group: Int
    /// The address the record names.
    public let address: InsteonAddress
    /// The record's role.
    public let role: Role
    /// The record's three data bytes.
    public let data: [UInt8]

    /// Creates a half link.
    public init(endpoint: Source, group: Int, address: InsteonAddress, role: Role, data: [UInt8]) {
      self.endpoint = endpoint
      self.group = group
      self.address = address
      self.role = role
      self.data = data
    }
  }

  /// A scene.
  public struct Scene: Equatable, Sendable {
    /// The scene's ALL-Link group number, in decimal.
    public let number: Int
    /// What starts the scene.
    public let source: Source
    /// Whether a client can run the scene: the modem is its source.
    public let isWritable: Bool
    /// The devices that answer the scene.
    public let members: [Member]
    /// Records of the scene whose other half is missing.
    public let halfLinks: [HalfLink]

    /// Creates a scene.
    public init(number: Int, source: Source, isWritable: Bool, members: [Member], halfLinks: [HalfLink]) {
      self.number = number
      self.source = source
      self.isWritable = isWritable
      self.members = members
      self.halfLinks = halfLinks
    }
  }

  /// Why a device's ALL-Link database was not read.
  public enum UnreadableReason: Equatable, Sendable {
    /// The device didn't answer.
    case noAnswer
    /// The device rejected the modem, as an i2CS device does until it is linked to it.
    case rejectedModem
    /// Records failed their checksum on each of two readings.
    case damagedRecords
    /// The service holds no copy and none has been read.
    case notCached
    /// The network doesn't give out ALL-Link databases, as a Hub Pro doesn't.
    case unavailableFromSource
    /// The modem didn't confirm sending the request, so the device was never asked.
    case modemStoppedEchoing
    /// The Hub stopped answering while it was reachable before.
    case hubStoppedAnswering
    /// The reading failed for another reason.
    case failed
    /// The database ended without the record that marks its end, so part of it is missing.
    case incomplete
    /// A reason the service gives that this library has no case for, kept as the service wrote it.
    case other(String)

    init(_ name: String) {
      switch name {
      case "noAnswer": self = .noAnswer
      case "rejectedModem": self = .rejectedModem
      case "damagedRecords": self = .damagedRecords
      case "notCached": self = .notCached
      case "unavailableFromSource": self = .unavailableFromSource
      case "modemStoppedEchoing": self = .modemStoppedEchoing
      case "hubStoppedAnswering": self = .hubStoppedAnswering
      case "failed": self = .failed
      case "incomplete": self = .incomplete
      default: self = .other(name)
      }
    }
  }

  /// A device whose ALL-Link database was not read, and why.
  public struct UnreadableDevice: Equatable, Sendable {
    /// The device's address.
    public let address: InsteonAddress
    /// Why it was not read.
    public let reason: UnreadableReason

    /// Creates an entry.
    public init(address: InsteonAddress, reason: UnreadableReason) {
      self.address = address
      self.reason = reason
    }
  }

  /// The scenes, in the order the service lists them.
  public let scenes: [Scene]
  /// Records of any group whose other half is missing and that belong to no scene listed.
  public let looseHalfLinks: [HalfLink]
  /// The devices whose databases were not read, each with why.
  public let unreadable: [UnreadableDevice]
  /// The devices the service had no list to read for.
  public let unlisted: [InsteonAddress]
  /// Whether the modem's own database was not read.
  public let isModemUnread: Bool
  /// The members the catalog doesn't describe, once each.
  public let undescribedMembers: [InsteonAddress]
  /// Whether every database was read and every record has its other half.
  public let isWhole: Bool

  /// Creates a list.
  public init(scenes: [Scene], looseHalfLinks: [HalfLink], unreadable: [UnreadableDevice], unlisted: [InsteonAddress], isModemUnread: Bool, undescribedMembers: [InsteonAddress], isWhole: Bool) {
    self.scenes = scenes
    self.looseHalfLinks = looseHalfLinks
    self.unreadable = unreadable
    self.unlisted = unlisted
    self.isModemUnread = isModemUnread
    self.undescribedMembers = undescribedMembers
    self.isWhole = isWhole
  }

}

/// What a scene is told to do. Each member recalls the level or state its own record holds, so a
/// scene takes no level.
public enum SceneAction: Equatable, Sendable {
  /// Light On at full level to the scene's group.
  case on
  /// Light Off to the scene's group.
  case off
}

/// How a scene's run went, as the modem reported it.
public struct SceneRunReceipt: Equatable, Sendable {
  /// The scene's ALL-Link group number.
  public let scene: Int
  /// What the scene was told to do.
  public let action: SceneAction
  /// The members that acknowledged their ALL-Link cleanup. It is empty for a modem that passes no
  /// per-member acknowledgment up, so an empty list never means that no member acted.
  public let acknowledged: [InsteonAddress]
  /// The members that did not acknowledge their cleanup, and may still have acted.
  public let unacknowledged: [InsteonAddress]
  /// Whether the modem reported that it reached every member.
  public let isComplete: Bool
  /// How many members the scene had in the list the run was made from.
  public let responderCount: Int
  /// Whether the service saved what it learned.
  public let persistence: PersistenceOutcome

  /// Creates a receipt.
  public init(scene: Int, action: SceneAction, acknowledged: [InsteonAddress], unacknowledged: [InsteonAddress], isComplete: Bool, responderCount: Int, persistence: PersistenceOutcome) {
    self.scene = scene
    self.action = action
    self.acknowledged = acknowledged
    self.unacknowledged = unacknowledged
    self.isComplete = isComplete
    self.responderCount = responderCount
    self.persistence = persistence
  }
}
