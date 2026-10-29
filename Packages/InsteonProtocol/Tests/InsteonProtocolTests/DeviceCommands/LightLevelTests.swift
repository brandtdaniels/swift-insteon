import Testing
import InsteonProtocol

struct LightLevelTests {

  @Test func convertsPercentagesToLevels() {

    #expect(LightLevel.level(percent: 0) == 0x00)
    #expect(LightLevel.level(percent: 50) == 0x80)
    #expect(LightLevel.level(percent: 100) == 0xFF)
    #expect(LightLevel.level(percent: 150) == 0xFF)
    #expect(LightLevel.level(percent: -5) == 0x00)

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
