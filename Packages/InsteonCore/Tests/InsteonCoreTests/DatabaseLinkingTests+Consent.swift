import Testing
@testable import InsteonCore
import InsteonLinking
import InsteonLinkingTestSupport
import InsteonModem
import InsteonProtocol

/// Consent to apply a plan, which a front end that has no terminal gives as a field.
extension DatabaseLinkingTests {

  // MARK: - Fingerprint

  @Test func aFingerprintIsAShaOfTheReadAndStaysTheSameForTheSameRead() async throws {

    let modem: InMemoryModem = await partlyLinked()
    let linking: DeviceLinkingCoordinator = network(modem).linking
    let first: DatabaseLinkPlan = try await linking.planDatabaseLink(device)
    let second: DatabaseLinkPlan = try await linking.planDatabaseLink(device)

    #expect(first.fingerprint.hasPrefix("sha256:"))
    #expect(first.fingerprint.count == "sha256:".count + 64)
    #expect(first.fingerprint == second.fingerprint)

  }

  @Test func aFingerprintChangesWithTheStepsAndWithTheRecordsRead() async throws {

    let modem: InMemoryModem = await partlyLinked()
    let linking: DeviceLinkingCoordinator = network(modem).linking
    let linked: DatabaseLinkPlan = try await linking.planDatabaseLink(device)
    let unlinked: DatabaseLinkPlan = try await linking.planDatabaseUnlink(device)

    await modem.setModemRecords([controller(0x07, naming: DatabaseLinkingExample.lamp)])

    let reread: DatabaseLinkPlan = try await linking.planDatabaseLink(device)

    #expect(linked.fingerprint != unlinked.fingerprint)
    #expect(linked.fingerprint != reread.fingerprint)

    var changed: DatabaseLinkPlan = linked
    changed.steps[0].written.data1 = 0x80

    #expect(linked.fingerprint != changed.fingerprint)

  }

  // MARK: - Consent

  @Test func appliesAPlanWithConsentThatNamesItsFingerprint() async throws {

    let modem: InMemoryModem = await partlyLinked()
    let linking: DeviceLinkingCoordinator = network(modem).linking
    let plan: DatabaseLinkPlan = try await linking.planDatabaseLink(device)
    let consent = DatabaseLinkConsent(writeLinkRecords: true, readFingerprint: plan.fingerprint)

    let result: DatabaseLinkResult = try await linking.apply(plan, consent: consent)

    #expect(result.isComplete)
    #expect(await modem.record(of: device, at: 0x0FF7) == responder(0x00, naming: modemAddress, data: [0xFF, 0x1C, 0x01]))

  }

  @Test func writesNothingWithoutConsent() async throws {

    let modem: InMemoryModem = await partlyLinked()
    let log: OperationLog = await OperationLog.logging(modem)
    let linking: DeviceLinkingCoordinator = network(modem).linking
    let plan: DatabaseLinkPlan = try await linking.planDatabaseLink(device)
    let before: Int = log.writesAndExtendedMessages
    let withheld = DatabaseLinkConsent(writeLinkRecords: false, readFingerprint: plan.fingerprint)

    let error: DatabaseLinkConsentRefusal? = await #expect(throws: DatabaseLinkConsentRefusal.self) {

      try await linking.apply(plan, consent: withheld)

    }

    #expect(error == .consentRequired)
    #expect(await modem.writes.isEmpty)
    #expect(await modem.modemRecords.isEmpty)
    #expect(log.writesAndExtendedMessages == before)

  }

  @Test func writesNothingWhenConsentNamesAnotherPlan() async throws {

    let modem: InMemoryModem = await partlyLinked()
    let linking: DeviceLinkingCoordinator = network(modem).linking
    let plan: DatabaseLinkPlan = try await linking.planDatabaseLink(device)
    let other: DatabaseLinkPlan = try await linking.planDatabaseUnlink(device)

    for fingerprint in [other.fingerprint, "", "sha256:"] {

      let consent = DatabaseLinkConsent(writeLinkRecords: true, readFingerprint: fingerprint)

      let error: DatabaseLinkConsentRefusal? = await #expect(throws: DatabaseLinkConsentRefusal.self) {

        try await linking.apply(plan, consent: consent)

      }

      #expect(error == .consentRequired)

    }

    #expect(await modem.writes.isEmpty)
    #expect(await modem.modemRecords.isEmpty)

  }

  @Test func refusesConsentBeforeReadingAnything() async throws {

    let modem: InMemoryModem = await partlyLinked()
    let linking: DeviceLinkingCoordinator = network(modem).linking
    let plan: DatabaseLinkPlan = try await linking.planDatabaseLink(device)
    let log: OperationLog = await OperationLog.logging(modem)

    _ = await #expect(throws: DatabaseLinkConsentRefusal.self) {

      try await linking.apply(plan, consent: DatabaseLinkConsent(writeLinkRecords: false, readFingerprint: plan.fingerprint))

    }

    #expect(log.standardCommands.isEmpty)
    #expect(log.writesAndExtendedMessages == 0)

  }

  @Test func stillRefusesADatabaseThatChangedWhenConsentIsGiven() async throws {

    let modem: InMemoryModem = await partlyLinked()
    let linking: DeviceLinkingCoordinator = network(modem).linking
    let plan: DatabaseLinkPlan = try await linking.planDatabaseLink(device)

    await modem.setModemRecords([controller(0x00, naming: device)])

    let error: DatabaseLinkRefusal? = await #expect(throws: DatabaseLinkRefusal.self) {

      try await linking.apply(plan, consent: DatabaseLinkConsent(writeLinkRecords: true, readFingerprint: plan.fingerprint))

    }

    #expect(error == .changedSincePlanned(device))
    #expect(await modem.writes.isEmpty)

  }

}
