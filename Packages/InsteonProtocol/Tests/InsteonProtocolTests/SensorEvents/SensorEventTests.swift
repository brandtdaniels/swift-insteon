import Testing
import InsteonProtocol

struct SensorEventTests {

  let sensor = InsteonAddress(0x2A, 0x3B, 0x4C)

  func command(_ command1: UInt8, toGroup group: AllLinkGroupNumber) -> GroupCommand {

    GroupCommand(controller: sensor, group: group, command1: command1, command2: 0x00, source: .broadcast)

  }

  // The PIR III sheet: 1101/1301 or 1101/1105 for motion, 1102/1302 or 1102/1106 for sunset
  // and sunrise, 1103 for a low battery, and group 4 for the heartbeat.
  @Test func readsAMotionSensorsEvents() {

    #expect(MotionSensorEvent(command(0x11, toGroup: 0x01)) == .motion)
    #expect(MotionSensorEvent(command(0x13, toGroup: 0x01)) == .motionStopped)
    #expect(MotionSensorEvent(command(0x11, toGroup: 0x05)) == .motionStopped)
    #expect(MotionSensorEvent(command(0x11, toGroup: 0x02)) == .dark)
    #expect(MotionSensorEvent(command(0x13, toGroup: 0x02)) == .light)
    #expect(MotionSensorEvent(command(0x11, toGroup: 0x06)) == .light)
    #expect(MotionSensorEvent(command(0x11, toGroup: 0x03)) == .lowBattery)
    #expect(MotionSensorEvent(command(0x12, toGroup: 0x04)) == .heartbeat)
    #expect(MotionSensorEvent(command(0x11, toGroup: 0x07)) == nil)

  }

  // The Smoke sheet: groups 1 through 7, and 0A for the heartbeat.
  @Test func readsASmokeBridgesEvents() {

    let events: [AllLinkGroupNumber: SmokeBridgeEvent] = [
      0x01: .smoke, 0x02: .carbonMonoxide, 0x03: .test, 0x04: .unknownAlarm,
      0x05: .clear, 0x06: .lowBattery, 0x07: .malfunction, 0x0A: .heartbeat,
    ]

    for (group, event) in events {

      #expect(SmokeBridgeEvent(command(0x11, toGroup: group)) == event)

    }

    #expect(SmokeBridgeEvent(command(0x13, toGroup: 0x01)) == nil)
    #expect(SmokeBridgeEvent(command(0x11, toGroup: 0x08)) == nil)

  }

  // The heartbeat status sheet: 1101 dry and 1102 wet.
  @Test func readsALeakSensorsEvents() {

    #expect(LeakSensorEvent(command(0x11, toGroup: 0x01)) == .dry)
    #expect(LeakSensorEvent(command(0x11, toGroup: 0x02)) == .wet)
    #expect(LeakSensorEvent(command(0x11, toGroup: 0x04)) == .heartbeat)
    #expect(LeakSensorEvent(command(0x13, toGroup: 0x02)) == nil)

  }

  // The heartbeat status sheet: 1101 open and 1301 close.
  @Test func readsAnOpenCloseSensorsEvents() {

    #expect(OpenCloseSensorEvent(command(0x11, toGroup: 0x01)) == .opened)
    #expect(OpenCloseSensorEvent(command(0x13, toGroup: 0x01)) == .closed)
    #expect(OpenCloseSensorEvent(command(0x13, toGroup: 0x04)) == .heartbeat)
    #expect(OpenCloseSensorEvent(command(0x11, toGroup: 0x02)) == nil)

  }

}
