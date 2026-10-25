import Foundation

public struct PostCommand: RequestProtocol {

  public typealias Response = StatusResponse

  public var urlRequest: URLRequest {

    let url = ApiRoute.endpoint(.commands).url!

//    var json: [String : Any] = ["command": command]
//
//    if let deviceId = deviceId {
//
//      json["device_id"] = deviceId
//
//    }
//
//    if let sceneId = sceneId {
//
//      json["scene_id"] = sceneId
//
//    }
//
//    if let level = level {
//
//      json["level"] = level
//
//    }
//
//    guard let jsonData = try?  JSONSerialization.data(withJSONObject: json) else {
//
//      return nil
//
//    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = jsonData

    return request

  }

//  private let command: String
//
//  private let deviceId: Int?
//
//  private let sceneId: Int?
//
//  private let level: Int?
//
//  public init(deviceId: Int, command: DeviceCommand, level: Int? = nil) {
//
//    self.deviceId = deviceId
//
//    self.command = command.rawValue
//
//    self.level = level
//
//    self.sceneId = nil
//
//  }
//
//  public init(sceneId: Int, command: SceneCommand) {
//
//    self.sceneId = sceneId
//
//    self.command = command.rawValue
//
//    self.deviceId = nil
//
//    self.level = nil
//
//  }

  private let jsonData: Data

  public init(jsonData: Data) {

    self.jsonData = jsonData

  }

}
