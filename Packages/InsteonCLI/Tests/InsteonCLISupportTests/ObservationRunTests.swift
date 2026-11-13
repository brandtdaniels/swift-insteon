import Foundation
import Testing
import InsteonCLISupport
import InsteonCore
import InsteonProtocol

/// What `insteon observe` asks a device, in what order, and how each answer is recorded.
@Suite(.timeLimit(.minutes(1)))
struct ObservationRunTests {

  /// A device that answers from a script, and records what it was asked.
  final class ScriptedDevice: ObservationSource {

    var calls: [String] = []

    var identity: ObservationReply<ObservedIdentity> = .answered(
      ObservedIdentity(engine: .i2cs, acceptsModem: true, category: 0x7E, subcategory: 0x7F, firmwareVersion: 0x41)
    )

    var productData: ObservationReply<DeviceProductData> = .answered(
      DeviceProductData(category: 0x7E, subcategory: 0x7F, productKey: ProductKey(0x00, 0x00, 0x1A))
    )

    var status: ObservationReply<Void>? = .answered(())

    var operatingFlags: ObservationReply<[UInt8]>? = .answered([0x2A, 0x00])

    var names: [String] = []

    func identify() async throws -> ObservationReply<ObservedIdentity> {

      calls.append("identify")

      return identity

    }

    func productData() async throws -> ObservationReply<DeviceProductData> {

      calls.append("productData")

      return productData

    }

    func productName(category: DeviceCategory, subcategory: DeviceSubcategory, firmwareVersion: FirmwareVersion?) -> String? {

      names.append("\(category) \(subcategory)")

      return "Example Invented Product"

    }

    func readStatus() async throws -> ObservationReply<Void>? {

      calls.append("status")

      return status

    }

    func readOperatingFlags() async throws -> ObservationReply<[UInt8]>? {

      calls.append("operatingFlags")

      return operatingFlags

    }

  }

  private func names(_ findings: ObservationFindings) -> [String] {

    findings.checks.map(\.name)

  }

  private func outcomes(_ findings: ObservationFindings) -> [ObservationOutcome] {

    findings.checks.map(\.outcome)

  }

  // MARK: - A device that answers

  @Test func asksTheReadOnlyRequestsInOrderAndRecordsWhatTheDeviceReported() async throws {

    let device = ScriptedDevice()

    let findings = try await ObservationRun.observe(device)

    #expect(device.calls == ["identify", "productData", "status", "operatingFlags"])
    #expect(names(findings) == ["Get Insteon Engine Version", "ID Request", "Product Data Request", "Status Request", "Get Operating Flags"])
    #expect(outcomes(findings) == [.answered, .answered, .answered, .answered, .answered])
    #expect(findings.engine == "i2CS")
    #expect(findings.category == "0x7E")
    #expect(findings.subcategory == "0x7F")
    #expect(findings.firmware == "0x41")
    #expect(findings.model == "Example Invented Product")
    #expect(findings.productKey == "0x00001A")
    #expect(findings.operatingFlags == [0x2A, 0x00])

  }

  @Test func leavesTheModelOutWhenTheCatalogDoesntIdentifyTheDevice() async throws {

    let device = ScriptedDevice()

    let named = try await ObservationRun.observe(device)

    #expect(named.model == "Example Invented Product")

    let unnamed = try await ObservationRun.observe(Unnamed(device))

    #expect(unnamed.model == nil)

  }

  @Test func recordsAProductKeyTheDeviceAnsweredWithoutAsNone() async throws {

    let device = ScriptedDevice()
    device.productData = .answered(DeviceProductData(category: 0x7E, subcategory: 0x7F, productKey: nil))

    let findings = try await ObservationRun.observe(device)

    #expect(findings.productKey == "none")
    #expect(findings.checks[2].outcome == .answered)

  }

  @Test func takesTheIdentityFromProductDataWhenIdRequestBroughtNone() async throws {

    let device = ScriptedDevice()
    device.identity = .answered(ObservedIdentity(engine: .i2, acceptsModem: true))

    let findings = try await ObservationRun.observe(device)

    #expect(findings.checks[1].outcome == .silent)
    #expect(findings.category == "0x7E")
    #expect(findings.subcategory == "0x7F")
    #expect(findings.firmware == nil)
    #expect(device.names == ["0x7E 0x7F"])

  }

  @Test func skipsTheRequestsTheCatalogGivesNoWayToMake() async throws {

    let device = ScriptedDevice()
    device.status = nil
    device.operatingFlags = nil

    let findings = try await ObservationRun.observe(device)

    #expect(names(findings) == ["Get Insteon Engine Version", "ID Request", "Product Data Request"])
    #expect(findings.operatingFlags == nil)

  }

  // MARK: - A device that doesn't answer

  @Test func recordsEachRequestAsSilentForADeviceThatAnswersNothing() async throws {

    let device = ScriptedDevice()
    device.identity = .silent

    let findings = try await ObservationRun.observe(device)

    #expect(device.calls == ["identify"])
    #expect(names(findings) == ["Get Insteon Engine Version", "ID Request"])
    #expect(outcomes(findings) == [.silent, .silent])
    #expect(findings.engine == nil)
    #expect(findings.category == nil)
    #expect(findings.productKey == nil)

  }

  @Test func neverWordsASilenceAsAFactAboutTheDevice() async throws {

    let device = ScriptedDevice()
    device.identity = .silent

    let findings = try await ObservationRun.observe(device)
    let observation = try Observation(findings, tool: ObservationTool(name: "insteon", version: "1"), catalogVersion: "1", note: nil, observedOn: .now)
    let details = observation.findings.checks.map(\.detail)

    for detail in details {

      #expect(detail.contains("may need to be awake"))
      #expect(!detail.lowercased().contains("is asleep"))
      #expect(!detail.lowercased().contains("does not support"))

    }

  }

  @Test func keepsAskingAfterOneLaterRequestGetsNoAnswer() async throws {

    let device = ScriptedDevice()
    device.productData = .silent
    device.status = .silent
    device.operatingFlags = .refused

    let findings = try await ObservationRun.observe(device)

    #expect(device.calls == ["identify", "productData", "status", "operatingFlags"])
    #expect(outcomes(findings) == [.answered, .answered, .silent, .silent, .refused])
    #expect(findings.productKey == nil)
    #expect(findings.operatingFlags == nil)

  }

  @Test func leavesTheProductKeyOutWhenProductDataWasRefused() async throws {

    let device = ScriptedDevice()
    device.productData = .refused

    #expect(try await ObservationRun.observe(device).productKey == nil)

  }

  @Test func recordsARefusalAsRefused() async throws {

    let device = ScriptedDevice()
    device.identity = .refused

    let findings = try await ObservationRun.observe(device)

    #expect(outcomes(findings) == [.refused, .refused])

  }

  // MARK: - A device the modem isn't linked to

  @Test func failsForADeviceThatRejectsTheModem() async {

    let device = ScriptedDevice()
    device.identity = .answered(ObservedIdentity(engine: .i2cs, acceptsModem: false))

    await #expect(throws: DeviceControlError.notLinked) {

      try await ObservationRun.observe(device)

    }

    #expect(device.calls == ["identify"])

  }

  // MARK: - Reading errors

  struct ModemFailed: Error, Equatable {}

  @Test func readsADeviceThatDoesntAnswerOrRejectsAsTheOutcomeAndRethrowsTheRest() throws {

    let device = InsteonAddress(0x1A, 0x2B, 0x3C)

    #expect(try ObservationReply<Int>.classify(.deviceUnanswered(device), error: ModemFailed()) == .silent)
    #expect(try ObservationReply<Int>.classify(.deviceRejected(device, .notLinked), error: ModemFailed()) == .refused)

    for failure: SendFailure? in [.modemRejected, .modemUnanswered, nil] {

      #expect(throws: ModemFailed()) {

        try ObservationReply<Int>.classify(failure, error: ModemFailed())

      }

    }

  }

  /// A device that the catalog doesn't identify.
  struct Unnamed: ObservationSource {

    let wrapped: ScriptedDevice

    init(_ wrapped: ScriptedDevice) {

      self.wrapped = wrapped

    }

    func identify() async throws -> ObservationReply<ObservedIdentity> { try await wrapped.identify() }

    func productData() async throws -> ObservationReply<DeviceProductData> { try await wrapped.productData() }

    func productName(category: DeviceCategory, subcategory: DeviceSubcategory, firmwareVersion: FirmwareVersion?) -> String? { nil }

    func readStatus() async throws -> ObservationReply<Void>? { try await wrapped.readStatus() }

    func readOperatingFlags() async throws -> ObservationReply<[UInt8]>? { try await wrapped.readOperatingFlags() }

  }

}
