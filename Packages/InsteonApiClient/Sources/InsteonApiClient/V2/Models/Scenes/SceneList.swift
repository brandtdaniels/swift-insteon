public struct SceneList {

  public var scenes: [Scene]

}

// MARK: - Decodable

extension SceneList: Decodable {

  private enum CodingKeys: String, CodingKey {

    case scenes = "SceneList"

  }

}
