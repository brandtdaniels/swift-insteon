import Testing
@testable import InsteonCore
import InsteonDeviceCatalog
import InsteonProtocol

/// The catalog's and the protocol's values, as InsteonCore's own types give them.
struct FacadeTypesTests {

  @Test func givesACatalogProcedureAsInstructions() {

    let procedure = DeviceLifecycle.Procedure(
      summary: "Unlink from the Hub.",
      steps: [
        DeviceLifecycle.Step(text: "Press the Hub's button.", isOnOtherDevice: true),
        DeviceLifecycle.Step(text: "Hold the SET button until it beeps.", action: .hold, control: "SET button", expectation: "LED blinks red"),
      ],
      notes: ["Some models beep twice."]
    )

    #expect(Instructions(procedure) == Instructions(
      steps: [
        InstructionStep(text: "Press the Hub's button.", isOnOtherDevice: true),
        InstructionStep(text: "Hold the SET button until it beeps.", expectation: "LED blinks red"),
      ],
      notes: ["Some models beep twice."]
    ))

  }

  @Test func givesWhatAResetErasesAsResetErasures() {

    #expect(ResetErasure(DeviceLifecycle.Erasure.links) == .links)
    #expect(ResetErasure(DeviceLifecycle.Erasure.settings) == .settings)

  }

  @Test func givesARecordBackWithItsLinkAndData() {

    let record = LinkRecord(isController: true, isInUse: true, group: 0x03, address: InsteonAddress(0x1A, 0x2B, 0x3C), data: [0x01, 0x02, 0x03])

    #expect(LinkRecord(record.allLinkRecord) == record)
    #expect([record.allLinkRecord.data1, record.allLinkRecord.data2, record.allLinkRecord.data3] == [0x01, 0x02, 0x03])

  }

  @Test func givesALinkReportBackWithItsRole() {

    let completed = AllLinkingCompleted(linkCode: 0xFF, group: 0x02, address: InsteonAddress(0x1A, 0x2B, 0x3C), category: nil, subcategory: nil, firmwareVersion: nil)

    #expect(LinkMade(completed).mode == .delete)
    #expect(LinkMade(completed).allLinkingCompleted == completed)

  }

}
