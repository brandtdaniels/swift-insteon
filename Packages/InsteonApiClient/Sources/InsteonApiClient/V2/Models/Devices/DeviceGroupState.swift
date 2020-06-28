public enum DeviceGroupState: Int {

  case on = 11

  case off = 13

  public var text: String {

    switch self {

    case .on: return "On"

    case .off: return "Off"

    }

  }

}
