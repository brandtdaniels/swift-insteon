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
  let idempotency: IdempotencyStore
  let now: @Sendable () -> Date

  init(service: Service, logger: Logger, idempotency: IdempotencyStore = IdempotencyStore(), now: @escaping @Sendable () -> Date = { Date() }) {
    self.now = now
    self.service = service
    self.logger = logger
    self.idempotency = idempotency
  }

  /// Runs a scene the modem controls. It needs the `control` scope, which the authentication
  /// middleware has already enforced, and the request marker. With an `Idempotency-Key`, a repeat of
  /// the same run returns the recorded answer and sends nothing.
  func run(_ request: Request, number: String?) async throws -> Response {
    guard HTTPBody.mediaType(request) == "application/json" else { throw HTTPInputError.unsupportedMedia }
    try HTTPBody.requireMarker(request)
    guard let number, Self.isCanonicalDecimal(number), let group = UInt8(number), (1...254).contains(group) else { throw SceneInputError.invalidScene }
    let command = SceneCommand(number: group, action: try SceneCommandBody(try await HTTPBody.read(request)).action)
    let key = try IdempotencyKey(header: request.headers[values: .idempotencyKey])
    guard let key else { return try Self.response(await perform(command)) }
    let (outcome, replayed) = try await idempotency.perform(scope: .gateway, key: key.value, fingerprint: Self.fingerprint(command)) { await perform(command) }
    var response = try Self.response(outcome, replayed: replayed)
    if replayed { response.headers[.idempotentReplay] = "true" }
    return response
  }

  /// Plans adding and removing a scene's members. It needs the `admin` scope, which the authentication
  /// middleware has already enforced, and the request marker. The service reads only what it has cached,
  /// so nothing is sent to hardware and nothing is written.
  func planMembership(_ request: Request, number: String?) async throws -> Response {
    guard HTTPBody.mediaType(request) == "application/json" else { throw HTTPInputError.unsupportedMedia }
    try HTTPBody.requireMarker(request)
    guard let number, Self.isCanonicalDecimal(number), let group = UInt8(number), (1...254).contains(group) else { throw SceneInputError.invalidScene }
    let change = try SceneMembershipBody.change(scene: group, from: try await HTTPBody.read(request))
    let receipt: SceneMembershipPlanReceipt
    do {
      receipt = try await service.planSceneMembership(change)
    } catch {
      // A plan only reads the cache, so a failure is classified as a read: nothing was sent.
      throw CommandFailure(action: .status, underlying: error)
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return Response(status: .ok, headers: [.contentType: "application/json"], body: .init(byteBuffer: ByteBuffer(bytes: try encoder.encode(SceneMembershipPlanDTO(receipt)))))
  }

  /// One to three ASCII digits with no sign and no leading zero, so each scene has one path.
  private static func isCanonicalDecimal(_ text: String) -> Bool {
    (1...3).contains(text.utf8.count) && text.utf8.allSatisfy { (0x30...0x39).contains($0) } && text.utf8.first != 0x30
  }

  private func perform(_ command: SceneCommand) async -> IdempotentOutcome {
    let start = now()
    do {
      let receipt = try await service.runScene(command)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      // How long a run took, so a Hub's delay is visible without a wire log. No address is logged.
      logger.debug("scene run finished", metadata: [
        "scene": "\(command.number)", "action": "\(command.action == .on ? "on" : "off")", "seconds": "\(now().timeIntervalSince(start))",
        "isComplete": "\(receipt.isComplete)", "statusReportSeconds": "\(Self.text(receipt.statusReportAfter))", "failureReportSeconds": "\(Self.text(receipt.failureReportedAfter))", "acknowledged": "\(receipt.acknowledged.count)", "unacknowledged": "\(receipt.unacknowledged.count)"
      ])
      return .response(.ok, try encoder.encode(SceneReceiptDTO(receipt)))
    } catch {
      // A scene command changes devices, so a failure is classified as a control.
      let failure = HTTPFailure(CommandFailure(action: .on, underlying: error))
      logger.debug("scene run failed", metadata: ["scene": "\(command.number)", "code": "\(failure.code.rawValue)", "seconds": "\(now().timeIntervalSince(start))"])
      return .failure(failure)
    }
  }

  /// Seconds as a decimal, or `none` when the modem sent no such report.
  private static func text(_ duration: Duration?) -> String {
    guard let duration else { return "none" }
    return "\(Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18)"
  }

  /// Names a run by what it asks for, not by how the request spelled it.
  private static func fingerprint(_ command: SceneCommand) -> String {
    SecureDigest.of("POST\n/api/v1/scenes/\(command.number)/commands\n\(command.action)").map { String(format: "%02x", $0) }.joined()
  }

  private static func response(_ outcome: IdempotentOutcome, replayed: Bool = false) throws -> Response {
    switch outcome {
    case let .response(status, body): Response(status: status, headers: [.contentType: "application/json"], body: .init(byteBuffer: ByteBuffer(bytes: body)))
    case let .failure(failure): throw OutcomeFailure(failure: failure, replayed: replayed)
    }
  }

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

/// A scene number that is not a group from 1 through 254, or a membership change that is not an add list and
/// a remove list of devices.
enum SceneInputError: Error { case invalidScene, invalidMembership }

/// The body of a scene command: an `action` of `on` or `off`, and nothing else.
struct SceneCommandBody {
  let action: SceneCommand.Action

  private struct Raw: Decodable { let action: HTTPSceneAction }

  init(_ data: Data) throws {
    guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], Set(object.keys) == ["action"] else { throw HTTPInputError.invalid }
    action = try JSONDecoder().decode(Raw.self, from: data).action == .on ? .on : .off
  }
}

/// The body of a membership plan request: `add`, a list of `{device, onLevel, rampRate}`, and `remove`,
/// a list of addresses, each with at most 32 devices, and at least one device in all.
enum SceneMembershipBody {
  static let longestList = 32

  private struct Raw: Decodable {
    let add: [RawAddition]?
    let remove: [String]?
  }

  private struct RawAddition: Decodable {
    let device: String
    let onLevel: Int?
    let rampRate: Int?
    let group: Int?
  }

  static func change(scene: UInt8, from data: Data) throws -> SceneMembershipChange {
    guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], Set(object.keys).isSubset(of: ["add", "remove"]) else { throw SceneInputError.invalidMembership }
    if let added = object["add"] as? [Any] {
      for element in added {
        guard let fields = element as? [String: Any], Set(fields.keys).isSubset(of: ["device", "onLevel", "rampRate", "group"]) else { throw SceneInputError.invalidMembership }
      }
    }
    let raw: Raw
    do { raw = try JSONDecoder().decode(Raw.self, from: data) } catch { throw SceneInputError.invalidMembership }
    let added = raw.add ?? []
    let removed = raw.remove ?? []
    guard added.count + removed.count > 0, added.count <= longestList, removed.count <= longestList else { throw SceneInputError.invalidMembership }
    var additions: [SceneMembershipChange.Addition] = []
    for item in added {
      guard let address = InsteonAddress(item.device) else { throw HTTPInputError.invalidAddress }
      additions.append(SceneMembershipChange.Addition(device: address, onLevel: try byte(item.onLevel), rampRate: try byte(item.rampRate), group: try item.group.map(group)))
    }
    var removals: [InsteonAddress] = []
    for text in removed {
      guard let address = InsteonAddress(text) else { throw HTTPInputError.invalidAddress }
      removals.append(address)
    }
    // A device named twice for the same group, or in both lists, is for the planner to refuse.
    guard let change = SceneMembershipChange(scene: scene, additions: additions, removals: removals) else { throw SceneInputError.invalidMembership }
    return change
  }

  /// A device's own group, from 1 through 255.
  private static func group(_ value: Int) throws -> UInt8 {
    guard (1...255).contains(value), let group = UInt8(exactly: value) else { throw SceneInputError.invalidMembership }
    return group
  }

  private static func byte(_ value: Int?) throws -> UInt8? {
    guard let value else { return nil }
    guard let byte = UInt8(exactly: value) else { throw SceneInputError.invalidMembership }
    return byte
  }
}

/// A membership plan as it goes on the wire.
struct SceneMembershipPlanDTO: Encodable {
  let version = 1
  let scene: Int
  /// A hash of the steps, which names the plan until it expires.
  let planId: String
  let expiresAt: String
  /// Whether the plan has steps and no refusal.
  let isApplicable: Bool
  let isEmpty: Bool
  let steps: [StepDTO]
  let devices: [DeviceDTO]
  let warnings: [FindingDTO]
  let refusals: [FindingDTO]
  /// The consent the apply step will need, or null when the plan can't be applied.
  let consent: ConsentDTO?

  struct StepDTO: Encodable {
    let order: Int
    let kind: String
    /// `modem`, or the address of the device the step writes to.
    let target: String
    /// `write` for a record the step adds or changes, `delete` for one it removes.
    let effect: String
    let record: RecordDTO
    let updateInPlace: Bool
    let risks: [String]

    init(_ step: SceneMembershipStep, order: Int) {
      self.order = order
      kind = step.kind.rawValue
      target = SceneWire.name(step.endpoint)
      effect = step.isRemoval ? "delete" : "write"
      record = RecordDTO(step.record)
      updateInPlace = step.isUpdateInPlace
      risks = step.risks.map(\.rawValue)
    }
  }

  struct RecordDTO: Encodable {
    let role: String
    let group: Int
    let address: String
    let data: [Int]
    /// Where the record is in a device's database, or null for the modem's.
    let memoryAddress: String?

    init(_ record: LinkRecord) {
      role = record.isController ? "controller" : "responder"
      group = Int(record.group.rawValue)
      address = record.address.description
      data = record.data.map(Int.init)
      memoryAddress = record.memoryAddress.map { String(format: "0x%04X", $0) }
    }

    func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(role, forKey: .role)
      try container.encode(group, forKey: .group)
      try container.encode(address, forKey: .address)
      try container.encode(data, forKey: .data)
      try container.encode(memoryAddress, forKey: .memoryAddress)
    }

    private enum CodingKeys: String, CodingKey { case role, group, address, data, memoryAddress }
  }

  struct DeviceDTO: Encodable {
    let address: String
    let product: String?
    let engine: String?
    let acceptsRemoteWrite: Bool

    init(_ device: SceneMembershipDevice) {
      address = device.address.description
      product = device.product
      engine = device.engine.map { "\($0)" }
      acceptsRemoteWrite = device.acceptsRemoteWrite
    }

    func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(address, forKey: .address)
      try container.encode(product, forKey: .product)
      try container.encode(engine, forKey: .engine)
      try container.encode(acceptsRemoteWrite, forKey: .acceptsRemoteWrite)
    }

    private enum CodingKeys: String, CodingKey { case address, product, engine, acceptsRemoteWrite }
  }

  struct FindingDTO: Encodable {
    let code: String
    /// The device it is about, or null for the modem.
    let device: String?
    let detail: String?

    init(_ finding: SceneMembershipFinding) {
      code = finding.code.rawValue
      device = finding.device?.description
      detail = finding.detail
    }

    func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(code, forKey: .code)
      try container.encode(device, forKey: .device)
      try container.encode(detail, forKey: .detail)
    }

    private enum CodingKeys: String, CodingKey { case code, device, detail }
  }

  struct ConsentDTO: Encodable {
    let writeLinkRecords: Bool
    let readFingerprint: String
  }

  init(_ receipt: SceneMembershipPlanReceipt) {
    let plan = receipt.plan
    scene = Int(plan.scene)
    planId = plan.id
    expiresAt = ISO8601DateFormatter().string(from: receipt.expiresAt)
    isApplicable = plan.isApplicable
    isEmpty = plan.isEmpty
    steps = plan.steps.enumerated().map { StepDTO($1, order: $0 + 1) }
    devices = plan.devices.map(DeviceDTO.init)
    warnings = plan.warnings.map(FindingDTO.init)
    refusals = plan.refusals.map(FindingDTO.init)
    consent = plan.requiredConsent.map { ConsentDTO(writeLinkRecords: $0.writeLinkRecords, readFingerprint: $0.readFingerprint) }
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(version, forKey: .version)
    try container.encode(scene, forKey: .scene)
    try container.encode(planId, forKey: .planId)
    try container.encode(expiresAt, forKey: .expiresAt)
    try container.encode(isApplicable, forKey: .isApplicable)
    try container.encode(isEmpty, forKey: .isEmpty)
    try container.encode(steps, forKey: .steps)
    try container.encode(devices, forKey: .devices)
    try container.encode(warnings, forKey: .warnings)
    try container.encode(refusals, forKey: .refusals)
    try container.encode(consent, forKey: .consent)
  }

  private enum CodingKeys: String, CodingKey { case version, scene, planId, expiresAt, isApplicable, isEmpty, steps, devices, warnings, refusals, consent }
}
