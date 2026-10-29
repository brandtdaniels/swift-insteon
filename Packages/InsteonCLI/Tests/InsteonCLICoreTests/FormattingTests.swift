import Testing
import InsteonCLICore

struct FormattingTests {

  @Test func writesBytesAndAddressesInHexadecimal() {

    #expect(Hex.byte(0x0F) == "0x0F")
    #expect(Hex.byte(0xAB) == "0xAB")
    #expect(Hex.address(0x0FFF) == "0x0FFF")
    #expect(Hex.address(0x0007) == "0x0007")

  }

  @Test func convertsPercentagesToLevels() {

    #expect(LightLevel.level(percent: 0) == 0x00)
    #expect(LightLevel.level(percent: 50) == 0x80)
    #expect(LightLevel.level(percent: 100) == 0xFF)
    #expect(LightLevel.level(percent: 150) == 0xFF)

  }

  @Test func convertsLevelsToPercentages() {

    #expect(LightLevel.percent(level: 0x00) == 0)
    #expect(LightLevel.percent(level: 0x7F) == 50)
    #expect(LightLevel.percent(level: 0xFF) == 100)

  }

  @Test func roundTripsEveryPercentage() {

    for percent in 0...100 {

      #expect(LightLevel.percent(level: LightLevel.level(percent: percent)) == percent)

    }

  }

}
