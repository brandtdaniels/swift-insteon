public struct DeviceState {

  public var state: DeviceGroupState?

  public var group: Int?

  public let rawValue: String

  init(rawValue: String) {

    self.rawValue = rawValue

    guard rawValue.count == 4,
      let stateInt = Int(rawValue.prefix(2)),
      let groupState = DeviceGroupState(rawValue: stateInt),
      let groupInt = Int(String(rawValue.suffix(2))) else {

        return

    }

    state = groupState

    group = groupInt

  }

}

// MARK: -

extension DeviceState: Equatable {}
