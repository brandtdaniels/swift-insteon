public struct CameraList {

  public var cameras: [Camera]

}

// MARK: - Decodable

extension CameraList: Decodable {

  private enum CodingKeys: String, CodingKey {

    case cameras = "CameraList"

  }

}
