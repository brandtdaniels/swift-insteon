import Foundation

public struct GetCommandResult: RequestProtocol {

  public typealias Response = CommandResult

  public var urlRequest: URLRequest {

    let url = ApiRoute.endpoint(.command(commandId)).url!

    var request = URLRequest(url: url)
    request.httpMethod = "GET"

    return request

  }

  private let commandId: Int

  public init(commandId: Int) {

    self.commandId = commandId

  }

}
