public enum DeviceCategory: Int, Decodable {

  case generalizedControllers = 0
  case dimmableLightingControl = 1
  case switchedLightingControl = 2
  case networkBridges = 3
  case irrigationControl = 4
  case climateControl = 5
  case poolSpaControl = 6
  case sensorsActuators = 7
  case homeEntertainment = 8
  case energyManagement = 9
  case applianceControl = 10
  case plumbing = 11
  case communication = 12
  case computerControl = 13
  case windowCoverings = 14
  case accessControl = 15
  case securityHealthSafety = 16
  case surveilliance = 17
  case automotive = 18
  case petCare = 19
  case toys = 20
  case timeKeeping = 21
  case holiday = 22

  case unassigned = 255

}

extension DeviceCategory {

  public var description: String {

    switch self {

    case .generalizedControllers: return "Generalized Controllers"
    case .dimmableLightingControl: return "Dimmable Lighting Control"
    case .switchedLightingControl: return "Switched Lighting Control"
    case .networkBridges: return "Network Bridges"
    case .irrigationControl: return "Irrigation Control"
    case .climateControl: return "Climate Control"
    case .poolSpaControl: return "Pool and Spa Control"
    case .sensorsActuators: return "Sensors and Actuators"
    case .homeEntertainment: return "Home Entertainment"
    case .energyManagement: return "Energy Management"
    case .applianceControl: return "Built-In Appliance Control"
    case .plumbing: return "Plumbing"
    case .communication: return "Communication"
    case .computerControl: return "Computer Control"
    case .windowCoverings: return "Window Coverings"
    case .accessControl: return "Access Control"
    case .securityHealthSafety: return "Security, Health, Safety"
    case .surveilliance: return "Surveillance"
    case .automotive: return "Automotive"
    case .petCare: return "Pet Care"
    case .toys: return "Toys"
    case .timeKeeping: return "Timekeeping"
    case .holiday: return "Holiday"
    case .unassigned: return "Unassigned"
      
    }

  }

}
