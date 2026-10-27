import Testing
import InsteonProtocol

struct X10CodeTests {

  @Test func unitAddressPutsHouseInHighNibble() {

    #expect(X10Code.unit(.a, .one).rawX10 == 0x66)
    #expect(X10Code.unit(.p, .thirteen).rawX10 == 0xC0)
    #expect(X10Code.unit(.a, .one).flag == 0x00)

  }

  @Test func commandSetsCommandFlag() {

    #expect(X10Code.command(.m, .allUnitsOff).bytes == [0x00, 0x80])
    #expect(X10Code.command(.b, .off).bytes == [0xE3, 0x80])

  }

  @Test func houseAndUnitCodesAreDistinctNibbles() {

    #expect(Set(X10HouseCode.allCases.map(\.rawValue)) == Set(UInt8(0)...15))
    #expect(Set(X10UnitCode.allCases.map(\.rawValue)) == Set(UInt8(0)...15))
    #expect(Set(X10Command.allCases.map(\.rawValue)) == Set(UInt8(0)...15))

  }

}
