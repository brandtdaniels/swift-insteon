import Crypto
import Foundation
import InsteonLinking
import InsteonProtocol

/// What a client asks to change in one scene's members: devices to add, with the on-level and ramp
/// rate each answers the scene with, and devices to remove.
///
/// A scene is a group the modem controls, from 1 through 254. Group 0 and group 255 are not scenes,
/// so a change for either can't be made.
///
/// ```swift
/// let change = SceneMembershipChange(
///   scene: 4,
///   additions: [.init(device: lamp, onLevel: 0xFF, rampRate: 0x1F)],
///   removals: [porch]
/// )
/// ```
public struct SceneMembershipChange: Hashable, Sendable {

  /// A device to add to the scene.
  public struct Addition: Hashable, Sendable {

    /// The device.
    public var device: InsteonAddress

    /// What the device's responder record holds for the on-level, or `nil` for full on (`0xFF`).
    public var onLevel: UInt8?

    /// What the device's responder record holds for the ramp rate, or `nil` for `0x1C` (0.5 s).
    public var rampRate: UInt8?

    /// The device's own group that answers the scene, such as one button of a keypad, or `nil` for
    /// the device's main group. The catalog must give the device the group.
    public var group: UInt8?

    /// Creates an addition.
    ///
    /// - Parameters:
    ///   - device: The device.
    ///   - onLevel: The on-level, or `nil` for full on.
    ///   - rampRate: The ramp rate, or `nil` for 0.5 s.
    ///   - group: The device's own group that answers the scene, or `nil` for its main group.
    ///     Defaults to `nil`.
    public init(device: InsteonAddress, onLevel: UInt8?, rampRate: UInt8?, group: UInt8? = nil) {

      self.device = device
      self.onLevel = onLevel
      self.rampRate = rampRate
      self.group = group

    }

  }

  /// The scene's ALL-Link group, from 1 through 254.
  public var scene: UInt8

  /// The devices to add, in the order given.
  public var additions: [Addition]

  /// The devices to remove, in the order given.
  public var removals: [InsteonAddress]

  /// Creates a change.
  ///
  /// - Parameters:
  ///   - scene: The scene's group, from 1 through 254.
  ///   - additions: The devices to add.
  ///   - removals: The devices to remove.
  /// - Returns: The change, or `nil` when `scene` is group 0 or group 255.
  public init?(scene: UInt8, additions: [Addition], removals: [InsteonAddress]) {

    guard (1...254).contains(scene) else {

      return nil

    }

    self.scene = scene
    self.additions = additions
    self.removals = removals

  }

}

/// One write a ``SceneMembershipPlan`` would make: a record added to, changed in or removed from
/// the modem's ALL-Link database or a device's.
public struct SceneMembershipStep: Hashable, Sendable {

  /// What a step writes.
  public enum Kind: String, Hashable, Sendable, CaseIterable {

    /// Writes the device's responder record for the scene into a slot that isn't in use, or into
    /// the slot of the record that marks the database's end.
    case addDeviceRecord

    /// Writes a record that marks the end of the device's database into the slot below the one
    /// the next step fills, so the database keeps an end.
    case markEndOfDatabase

    /// Adds the modem's controller record for the device in the scene.
    case addModemRecord

    /// Rewrites the data bytes of the device's responder record for the scene, in the slot it is
    /// in. It's the one step that writes over a record in use, so a plan with one is refused until
    /// it has been tried on hardware.
    case updateDeviceRecord

    /// Deletes the modem's controller record for the device in the scene.
    case removeModemRecord

    /// Clears the in-use bit of the device's responder record for the scene.
    case removeDeviceRecord

  }

  /// What can go wrong with a step beyond a write that doesn't read back.
  public enum Risk: String, Hashable, Sendable, CaseIterable {

    /// The step moves the end of the device's database down one slot.
    case movesEndOfDatabase

    /// The step removes the device's last record of the modem. An i2CS device rejects the modem
    /// from then on, so the write can't be read back.
    case rejectsModemOnceUnlinked

  }

  /// What the step writes.
  public var kind: Kind

  /// Whose database the record is in: the modem's or a device's.
  public var endpoint: LinkEndpoint

  /// The record as the step leaves it, at its ``LinkRecord/memoryAddress`` for a device. A record
  /// a step removes is not in use.
  public var record: LinkRecord

  /// What can go wrong with the step.
  public var risks: [Risk]

  /// Whether the step rewrites a record in use in place.
  public var isUpdateInPlace: Bool {

    kind == .updateDeviceRecord

  }

  /// Whether the step removes a record: deletes it from the modem or clears it in a device.
  public var isRemoval: Bool {

    kind == .removeModemRecord || kind == .removeDeviceRecord

  }

  init(kind: Kind, endpoint: LinkEndpoint, record: LinkRecord, risks: [Risk] = []) {

    self.kind = kind
    self.endpoint = endpoint
    self.record = record
    self.risks = risks

  }

}

/// Something a plan says about a device or the modem that a client should see: a warning, or the
/// reason the plan can't be applied.
public struct SceneMembershipFinding: Hashable, Sendable {

  /// What the finding says.
  public enum Code: String, Hashable, Sendable, CaseIterable {

    /// The device is a member of the scene already, with the record asked for, so no step is planned.
    case alreadyMember

    /// The device isn't a member of the scene, so no step is planned to remove it.
    case notAMember

    /// One half of the device's link to the scene was in place and the plan adds the other.
    case halfLinkCompleted

    /// The service holds no copy of the ALL-Link database, so nothing can be planned from it.
    case databaseNotCached

    /// The device reported no identity, so the catalog can't say what its record holds.
    case notIdentified

    /// The catalog doesn't describe the identity the device reported.
    case notInCatalog

    /// The device's engine takes no database writes, or the catalog doesn't confirm that it does.
    case unsupportedEngine

    /// The device runs i2CS and rejects the modem, so it rejects database writes too.
    case rejectsModem

    /// Records of the device's database failed their checksum.
    case damagedRecords

    /// The device's database ends without the record that marks its end.
    case noEndOfDatabase

    /// The device's database has no room for the record.
    case databaseFull

    /// The catalog doesn't give the device the group asked for.
    case unknownGroup

    /// The device's group the scene would use doesn't respond to a controller's commands.
    case groupCannotRespond

    /// The catalog doesn't say what the data bytes of the device's responder record hold.
    case undescribedLinkData

    /// The catalog names a data byte of the device's responder record without a value to write.
    case unknownLinkDataByte

    /// A value was asked for a data byte the device's responder record doesn't have, or for one
    /// the catalog fixes.
    case valueNotTaken

    /// A value is outside the range the catalog gives the data byte.
    case valueOutOfRange

    /// The step rewrites a record in use, which isn't made until it has been tried on hardware.
    case notYetSupported

    /// The change names the same device and group twice, so which record is meant isn't clear.
    case duplicateEntry

    /// The change adds a device and removes it, so which of the two is meant isn't clear.
    case addedAndRemoved

  }

  /// What the finding says.
  public var code: Code

  /// The device it's about, or `nil` for the modem.
  public var device: InsteonAddress?

  /// A sentence that says more, such as how many records are needed, or `nil`.
  public var detail: String?

  /// Creates a finding.
  ///
  /// - Parameters:
  ///   - code: What it says.
  ///   - device: The device it's about, or `nil` for the modem.
  ///   - detail: A sentence that says more, or `nil`.
  public init(code: Code, device: InsteonAddress?, detail: String? = nil) {

    self.code = code
    self.device = device
    self.detail = detail

  }

}

/// What the catalog and the cache say about a device a plan names.
public struct SceneMembershipDevice: Hashable, Sendable {

  /// The device.
  public var address: InsteonAddress

  /// The product's name for a person, or `nil` when the catalog doesn't have the device.
  public var product: String?

  /// The engine the device runs, as the service recorded it or the catalog says, or `nil`.
  public var engine: InsteonEngine?

  /// Whether the device takes a remote write of its ALL-Link database: its engine does, it
  /// doesn't reject the modem, and the cached database was read whole.
  public var acceptsRemoteWrite: Bool

}

/// What adding and removing a scene's members would write, from the ALL-Link databases the service
/// holds and the Insteon device catalog. A plan is made without sending anything.
///
/// The steps are in the order they would be made: for an addition the device's record, then the
/// modem's, and for a removal the modem's record, then the device's, so an i2CS device keeps the
/// record it needs until its last write. Applying a plan takes consent that names it:
/// ``requiredConsent``.
public struct SceneMembershipPlan: Hashable, Sendable {

  /// The scene's ALL-Link group.
  public var scene: UInt8

  /// The writes, in the order they would be made.
  public var steps: [SceneMembershipStep]

  /// What the plan notes without refusing.
  public var warnings: [SceneMembershipFinding]

  /// Why the plan can't be applied. A plan with a refusal can't be applied as it is.
  public var refusals: [SceneMembershipFinding]

  /// The devices the change names, with whether each takes a remote write.
  public var devices: [SceneMembershipDevice]

  /// A SHA-256 over the scene and the steps, as `sha256:` and 64 hexadecimal digits. The same
  /// change on the same databases gives the same identifier.
  public var id: String

  /// A SHA-256 over the steps and the records of the databases they were made from, as `sha256:`
  /// and 64 hexadecimal digits, so consent names exactly what a person was shown.
  public var fingerprint: String

  /// Whether the plan writes nothing.
  public var isEmpty: Bool {

    steps.isEmpty

  }

  /// Whether the plan has steps and no refusal.
  public var isApplicable: Bool {

    !steps.isEmpty && refusals.isEmpty

  }

  /// The consent applying the plan needs, the same as for a database link plan, or `nil` when the
  /// plan can't be applied.
  public var requiredConsent: DatabaseLinkConsent? {

    isApplicable ? DatabaseLinkConsent(writeLinkRecords: true, readFingerprint: fingerprint) : nil

  }

  init(scene: UInt8, steps: [SceneMembershipStep], warnings: [SceneMembershipFinding], refusals: [SceneMembershipFinding], devices: [SceneMembershipDevice], readLines: [String]) {

    self.scene = scene
    self.steps = steps
    self.warnings = warnings
    self.refusals = refusals
    self.devices = devices

    var stepLines: [String] = ["scene \(scene)"]

    for step in steps {

      stepLines.append("step \(step.kind.rawValue) \(Self.name(step.endpoint)) \(step.record.memoryAddress.map { String(format: "%04X", $0) } ?? "modem") \(step.record.isController) \(step.record.isInUse) \(step.record.group.rawValue) \(Self.hex(step.record.address.bytes)) \(Self.hex(step.record.data))")

    }

    id = Self.digest(stepLines)
    fingerprint = Self.digest(stepLines + readLines)

  }

  private static func name(_ endpoint: LinkEndpoint) -> String {

    switch endpoint {
    case .modem:
      "modem"
    case let .device(address):
      hex(address.bytes)
    }

  }

  static func hex(_ bytes: [UInt8]) -> String {

    bytes.map { String(format: "%02X", $0) }.joined()

  }

  private static func digest(_ lines: [String]) -> String {

    "sha256:" + SHA256.hash(data: Data(lines.joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()

  }

}
