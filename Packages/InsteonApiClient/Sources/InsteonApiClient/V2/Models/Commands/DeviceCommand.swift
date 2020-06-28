public enum DeviceCommand: String, Codable { // Dimmable Device

  case on = "on"
  case fastOn = "fast_on"
  case off = "off"
  case fastOff = "fast_off"
  case startBright = "start_dim_up"
  case stopBrightDim = "stop_dim"
  case startDim = "start_dim_down"
  case getStatus = "get_status"
  case beep = "beep"
  case instantOn = "instant_on"

}

public enum RelayDeviceCommand: String, Codable {

  case on = "on"
  case group2On = "on2" // Dual Outlet only
  case group2Off = "off2" // Dual Outlet only
  case fastOn = "fast_on"
  case off = "off"
  case fastOff = "fast_off"
  case getStatus = "get_status"
  case beep = "beep"
  case instantOn = "instant_on"

}

public enum IoModuleCommand: String, Codable {

  case on = "on"
  case off = "off"
  case getRelayStatus = "get_relay_status"
  case getSensorStatus = "get_sensor_status"

}

public enum FanControllerCommand: String, Codable {

  case on = "on"
  case off = "off"
  case startBright = "start_dim_up"
  case stopBrightDim = "stop_dim"
  case startDim = "start_dim_down"
  case getStatus = "get_status"
  case beep = "beep"
  case fan = "fan"
  case getFanSpeed = "get_fan_speed"

}

public enum ThermostatCommand: String, Codable {

  case getStatus = "get_status"
  case getMode = "mode"
  case getAmbientTemperature = "temp"
  case getSetpoints = "setpoints"
  case getHumidity = "humidity"
  case setCoolMode = "cool"
  case setHeatMode = "heat"
  case setAutoMode = "auto"
  case setOff = "all_off"
  case setCoolTemperature = "set_cool_to"
  case setHeatTemperature = "set_heat_to"
  case setTemperatureUp = "temp_up"
  case setTemperatureDown = "temp_down"
  case setFanOn = "fan_on"
  case setFanAuto = "fan_auto"

}

