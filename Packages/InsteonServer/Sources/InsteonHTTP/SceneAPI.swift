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

  /// Writes a plan's ALL-Link records. It needs the `admin` scope, which the authentication middleware has
  /// already enforced, the request marker, and consent in the body that agrees to the writes and names the
  /// plan. Consent is never implied by the scope. With an `Idempotency-Key`, a repeat of the same apply returns
  /// the recorded answer and writes nothing.
  func applyMembership(_ request: Request, number: String?, planId: String?, requestID: String) async throws -> Response {
    guard HTTPBody.mediaType(request) == "application/json" else { throw HTTPInputError.unsupportedMedia }
    try HTTPBody.requireMarker(request)
    guard let number, Self.isCanonicalDecimal(number), let scene = UInt8(number), (1...254).contains(scene) else { throw SceneInputError.invalidScene }
    let body = try SceneMembershipApplyBody(try await HTTPBody.read(request))
    let key = try IdempotencyKey(header: request.headers[values: .idempotencyKey])
    // The consent is judged before the plan is looked up, so a request that never agreed to the writes learns nothing about the plans the service holds.
    guard let consent = body.consent else { throw ServiceControlError.consentRequired }
    guard let planId, SceneMembershipApplyBody.isPlanID(planId) else { throw ServiceControlError.unknownPlan }
    guard let key else { return try Self.response(await perform(scene: scene, planId: planId, consent: consent, requestID: requestID)) }
    let fingerprint = Self.fingerprint(scene: scene, planId: planId, consent: consent)
    let (outcome, replayed) = try await idempotency.perform(scope: .gateway, key: key.value, fingerprint: fingerprint) { await perform(scene: scene, planId: planId, consent: consent, requestID: requestID) }
    var response = try Self.response(outcome, replayed: replayed)
    if replayed { response.headers[.idempotentReplay] = "true" }
    return response
  }

  private func perform(scene: UInt8, planId: String, consent: DatabaseLinkConsent, requestID: String) async -> IdempotentOutcome {
    let start = now()
    do {
      let application = try await service.applySceneMembership(scene: scene, planId: planId, consent: consent)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      let metadata: Logger.Metadata = [
        "scene": "\(scene)", "steps": "\(application.result.steps.count)", "written": "\(application.result.madeSteps.count)", "notWritten": "\(application.result.unmadeSteps.count)",
        "mismatches": "\(application.result.mismatches.count)", "seconds": "\(now().timeIntervalSince(start))"
      ]
      if application.isComplete {
        logger.info("scene membership applied", metadata: metadata)
      } else {
        // It wrote something and did not finish, so a person needs to see it: no address, only the counts.
        logger.warning("scene membership apply incomplete", metadata: metadata.merging(["interruption": "\(Self.name(of: application.interruption))"]) { $1 })
      }
      if !application.isCacheReloaded {
        logger.warning("scene membership apply left the cache stale", metadata: ["scene": "\(scene)"])
      }
      // An apply that stopped partway, or read back differently, is recorded like a success: it wrote, so a repeat must not.
      return .response(application.isComplete ? .ok : .badGateway, try encoder.encode(SceneMembershipApplicationDTO(application, requestID: requestID)))
    } catch {
      // Any failure the service throws came before the first write, so it is classified as a read.
      let failure = HTTPFailure(CommandFailure(action: .status, underlying: error))
      logger.debug("scene membership apply refused", metadata: ["scene": "\(scene)", "code": "\(failure.code.rawValue)", "seconds": "\(now().timeIntervalSince(start))"])
      return .failure(failure)
    }
  }

  /// What stopped an apply, without the description a modem error carries.
  private static func name(of interruption: SceneMembershipApplication.Interruption?) -> String {
    switch interruption {
    case .canceled?: "canceled"
    case .failed?: "failed"
    case nil: "none"
    }
  }

  /// Names an apply by the scene, the plan and the consent it carries, not by how the request spelled it.
  private static func fingerprint(scene: UInt8, planId: String, consent: DatabaseLinkConsent) -> String {
    SecureDigest.of("POST\n/api/v1/scenes/\(scene)/plans/\(planId)/apply\n\(consent.writeLinkRecords)\n\(consent.readFingerprint)").map { String(format: "%02x", $0) }.joined()
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
enum SceneInputError: Error { case invalidScene, invalidMembership, invalidBody }

/// The body of a scene command: an `action` of `on` or `off`, and nothing else.
struct SceneCommandBody {
  let action: SceneCommand.Action

  private struct Raw: Decodable { let action: HTTPSceneAction }

  init(_ data: Data) throws {
    guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], Set(object.keys) == ["action"] else { throw HTTPInputError.invalid }
    action = try JSONDecoder().decode(Raw.self, from: data).action == .on ? .on : .off
  }
}

/// The body of an apply request: `consent`, with `writeLinkRecords` and `readFingerprint`, and nothing else.
/// A consent that is missing, null, or whose fields are missing or of another type has no value, which the
/// route answers as `consentRequired`; a field this body doesn't take is malformed.
struct SceneMembershipApplyBody {
  /// The consent, or `nil` when it doesn't agree to the writes or doesn't name a plan.
  let consent: DatabaseLinkConsent?

  /// The body read once: `consent`, an object of `writeLinkRecords` and `readFingerprint`, and nothing else.
  private struct Raw: Decodable {
    let consent: Consent?

    private struct Key: CodingKey {
      let stringValue: String
      var intValue: Int? { nil }
      init?(stringValue: String) { self.stringValue = stringValue }
      init?(intValue: Int) { nil }
    }

    struct Consent: Decodable {
      let writeLinkRecords: Bool?
      let readFingerprint: String?

      init(from decoder: Decoder) throws {
        let keys = try decoder.container(keyedBy: Key.self)
        guard Set(keys.allKeys.map(\.stringValue)).isSubset(of: ["writeLinkRecords", "readFingerprint"]) else { throw HTTPInputError.invalid }
        writeLinkRecords = try keys.decodeIfPresent(Bool.self, forKey: Key(stringValue: "writeLinkRecords")!)
        readFingerprint = try keys.decodeIfPresent(String.self, forKey: Key(stringValue: "readFingerprint")!)
      }
    }

    init(from decoder: Decoder) throws {
      let keys = try decoder.container(keyedBy: Key.self)
      guard Set(keys.allKeys.map(\.stringValue)).isSubset(of: ["consent"]) else { throw HTTPInputError.invalid }
      consent = try keys.decodeIfPresent(Consent.self, forKey: Key(stringValue: "consent")!)
    }
  }

  /// - Throws: ``HTTPInputError/invalid`` for a body that is not a JSON object of this shape, and
  ///   ``SceneInputError/invalidBody`` for a field of the wrong type.
  init(_ data: Data) throws {
    let raw: Raw
    do {
      raw = try JSONDecoder().decode(Raw.self, from: data)
    } catch let error as DecodingError {
      // A body that isn't a JSON object stops at the top; a field of the wrong type stops below it.
      if case let .typeMismatch(_, context) = error, !context.codingPath.isEmpty { throw SceneInputError.invalidBody }
      throw HTTPInputError.invalid
    }
    if let given = raw.consent, given.writeLinkRecords == true, let fingerprint = given.readFingerprint, !fingerprint.isEmpty {
      consent = DatabaseLinkConsent(writeLinkRecords: true, readFingerprint: fingerprint)
    } else {
      consent = nil
    }
  }

  /// A plan's identifier: `sha256:` and 64 lowercase hexadecimal digits.
  static func isPlanID(_ text: String) -> Bool {
    text.utf8.count == 71 && text.hasPrefix("sha256:") && text.dropFirst(7).utf8.allSatisfy { (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }
  }
}

/// The body of a membership plan request: `add`, a list of `{device, onLevel, rampRate}`, and `remove`,
/// a list of addresses or `{device, group}` objects, each with at most 32 devices, and at least one device in all.
enum SceneMembershipBody {
  static let longestList = 32

  private struct Raw: Decodable {
    let add: [RawAddition]?
    let remove: [RawRemoval]?
  }

  /// A device to remove: an address for all of its records in the scene, or `{device, group}` for one group.
  private struct RawRemoval: Decodable {
    let device: String
    let group: Int?

    private enum Keys: String, CodingKey { case device, group }

    init(from decoder: Decoder) throws {
      if let text = try? decoder.singleValueContainer().decode(String.self) {
        device = text
        group = nil
        return
      }
      let keys = try decoder.container(keyedBy: Keys.self)
      device = try keys.decode(String.self, forKey: .device)
      group = try keys.decodeIfPresent(Int.self, forKey: .group)
    }
  }

  private struct RawAddition: Decodable {
    let device: String
    let onLevel: Int?
    let rampRate: Int?
    let group: Int?
  }

  static func change(scene: UInt8, from data: Data) throws -> SceneMembershipChange {
    guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], Set(object.keys).isSubset(of: ["add", "remove"]) else { throw SceneInputError.invalidMembership }
    if let removed = object["remove"] as? [Any] {
      for element in removed {
        if let fields = element as? [String: Any], !Set(fields.keys).isSubset(of: ["device", "group"]) { throw SceneInputError.invalidMembership }
      }
    }
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
    var removals: [SceneMembershipChange.Removal] = []
    for item in removed {
      guard let address = InsteonAddress(item.device) else { throw HTTPInputError.invalidAddress }
      removals.append(SceneMembershipChange.Removal(device: address, group: try item.group.map(group)))
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
  /// A hash of the steps and the records they were made from, which names the plan until it expires.
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
      engine = device.engine.map { (engine: InsteonEngine) -> String in
        switch engine {
        case .i1: "i1"
        case .i2: "i2"
        case .i2cs: "i2cs"
        }
      }
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


/// A plan applied, as it goes on the wire: each step's outcome, and what reading both databases again found.
/// A plan that stopped partway or read back differently also carries the typed failure of every error body,
/// so a client that branches on `code` finds `outcomeUnknown` and still sees which records were written.
struct SceneMembershipApplicationDTO: Encodable {
  let version = 1
  let scene: Int
  let planId: String
  /// `applied` when every step was made and both databases read back as planned, else `incomplete`.
  let outcome: String
  let isComplete: Bool
  /// How many steps were made, and how many were not (failed or not reached).
  let written: Int
  let notWritten: Int
  let steps: [StepDTO]
  let mismatches: [MismatchDTO]
  /// Whether the modem's database was read again and compared.
  let modemChecked: Bool
  let deviceChecks: [DeviceCheckDTO]
  /// `canceled` or `failed` when the steps stopped for a reason other than a step's own failure.
  let interruption: String?
  let interruptionDetail: String?
  /// `reloaded` when the service read the databases the steps touched into its cache, else `failed`: the listing
  /// holds the records as they were until the scenes are refreshed.
  let cacheReload: String
  /// Devices that reject the modem once their last record of it is removed, as an i2CS device does, so the service
  /// holds no copy of their databases. Expected, and not a failure of `cacheReload`.
  let expectedUnreadable: [String]
  let persistence: String
  let code: String?
  let message: String?
  let sent: Bool?
  let requestId: String?

  struct StepDTO: Encodable {
    let order: Int
    let kind: String
    let target: String
    let effect: String
    let record: SceneMembershipPlanDTO.RecordDTO
    /// `written`, `writtenOnRetry`, `unverifiable`, `notWritten`, `rejected`, `unanswered` or `notReached`.
    let outcome: String

    init(_ result: SceneMembershipResult.StepResult, order: Int) {
      self.order = order
      kind = result.step.kind.rawValue
      target = SceneWire.name(result.step.endpoint)
      effect = result.step.isRemoval ? "delete" : "write"
      record = SceneMembershipPlanDTO.RecordDTO(result.step.record)
      outcome = result.outcome.rawValue
    }
  }

  struct MismatchDTO: Encodable {
    let target: String
    let memoryAddress: String?
    let expected: SceneMembershipPlanDTO.RecordDTO?
    let found: SceneMembershipPlanDTO.RecordDTO?

    init(_ mismatch: SceneMembershipResult.Mismatch) {
      target = mismatch.device?.description ?? "modem"
      memoryAddress = mismatch.mismatch.memoryAddress.map { String(format: "0x%04X", $0) }
      expected = mismatch.mismatch.expected.map(SceneMembershipPlanDTO.RecordDTO.init)
      found = mismatch.mismatch.found.map(SceneMembershipPlanDTO.RecordDTO.init)
    }

    func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(target, forKey: .target)
      try container.encode(memoryAddress, forKey: .memoryAddress)
      try container.encode(expected, forKey: .expected)
      try container.encode(found, forKey: .found)
    }

    private enum CodingKeys: String, CodingKey { case target, memoryAddress, expected, found }
  }

  struct DeviceCheckDTO: Encodable {
    let device: String
    /// `checked`, `rejectsModemAfterUnlinking` or `unanswered`.
    let check: String
  }

  init(_ application: SceneMembershipApplication, requestID: String) {
    let result = application.result
    scene = Int(application.scene)
    planId = application.planId
    isComplete = application.isComplete
    outcome = application.isComplete ? "applied" : "incomplete"
    written = result.madeSteps.count
    notWritten = result.unmadeSteps.count
    steps = result.steps.enumerated().map { StepDTO($1, order: $0 + 1) }
    mismatches = result.mismatches.map(MismatchDTO.init)
    modemChecked = result.isModemChecked
    deviceChecks = result.deviceChecks.map { DeviceCheckDTO(device: $0.key.description, check: $0.value.rawValue) }.sorted { $0.device < $1.device }
    switch application.interruption {
    case .canceled?: interruption = "canceled"; interruptionDetail = nil
    case let .failed(detail)?: interruption = "failed"; interruptionDetail = detail
    case nil: interruption = nil; interruptionDetail = nil
    }
    cacheReload = application.isCacheReloaded ? "reloaded" : "failed"
    expectedUnreadable = application.expectedUnreadable.map(\.description)
    persistence = PersistenceName(application.persistence).rawValue
    if application.isComplete {
      code = nil; message = nil; sent = nil; requestId = nil
    } else {
      code = APIErrorCode.outcomeUnknown.rawValue
      message = "Some of the plan's records may have been written and the rest were not. `steps` says which, and `mismatches` says what reading the databases again found. Nothing was undone and no step was repeated beyond its one retry. Refresh the scenes and plan again."
      sent = true
      requestId = requestID
    }
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(version, forKey: .version)
    try container.encode(scene, forKey: .scene)
    try container.encode(planId, forKey: .planId)
    try container.encode(outcome, forKey: .outcome)
    try container.encode(isComplete, forKey: .isComplete)
    try container.encode(written, forKey: .written)
    try container.encode(notWritten, forKey: .notWritten)
    try container.encode(steps, forKey: .steps)
    try container.encode(mismatches, forKey: .mismatches)
    try container.encode(modemChecked, forKey: .modemChecked)
    try container.encode(deviceChecks, forKey: .deviceChecks)
    try container.encode(interruption, forKey: .interruption)
    try container.encode(interruptionDetail, forKey: .interruptionDetail)
    try container.encode(cacheReload, forKey: .cacheReload)
    try container.encode(expectedUnreadable, forKey: .expectedUnreadable)
    try container.encode(persistence, forKey: .persistence)
    try container.encodeIfPresent(code, forKey: .code)
    try container.encodeIfPresent(message, forKey: .message)
    try container.encodeIfPresent(sent, forKey: .sent)
    try container.encodeIfPresent(requestId, forKey: .requestId)
  }

  private enum CodingKeys: String, CodingKey { case version, scene, planId, outcome, isComplete, written, notWritten, steps, mismatches, modemChecked, deviceChecks, interruption, interruptionDetail, cacheReload, expectedUnreadable, persistence, code, message, sent, requestId }
}
