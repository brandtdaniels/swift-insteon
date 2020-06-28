public enum SceneDeviceGroupRole: Int, Decodable {

  case unknown

  case controller

  case responder

  case both

}

extension SceneDeviceGroupRole {

  public var description: String {

    switch self {

    case .unknown: return "Unknown"
    case .controller: return "Controller"
    case .responder: return "Responder"
    case .both: return "Controller & Responder"
      
    }

  }

}
