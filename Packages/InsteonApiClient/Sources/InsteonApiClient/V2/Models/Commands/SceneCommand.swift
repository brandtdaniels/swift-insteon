public enum SceneCommand: String, Codable {

  case on = "on"
  case off = "off"
  case startBright = "start_dim_up"
  case stopBrightDim = "stop_dim"
  case startDim = "start_dim_down"

}
