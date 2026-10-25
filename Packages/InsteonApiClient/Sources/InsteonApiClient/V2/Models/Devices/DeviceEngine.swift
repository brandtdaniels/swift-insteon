public enum DeviceEngine: Int, Decodable {

  case i1 = 0
  case i2 = 1
  case i2cs = 2

}

extension DeviceEngine {

  public var description: String {

    switch self {

    case .i1: return "i1"
    case .i2: return "i2"
    case .i2cs: return "i2cs"

    }

  }

}
