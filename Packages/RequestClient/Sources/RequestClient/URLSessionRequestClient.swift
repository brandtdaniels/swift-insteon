//
//  URLSessionRequestClient.swift
//
//
//  Created by Brandt Daniels on 4/30/20.
//

import Foundation

public class URLSessionRequestClient {
  
  private var session: URLSession
  
  public init(session: URLSession) {
    
    self.session = session
    
  }
  
}

// MARK: - RequestClientProtocol

extension URLSessionRequestClient: RequestClientProtocol {

  public func send(
    _ request: URLRequest,
    completion: @escaping (
    _ data: Data?,
    _ response: URLResponse?,
    _ error: Error?
    ) -> Void
  ) {
    
    let task = session.dataTask(with: request) { data, response, error in
      
      completion(data, response, error)
      
    }
    
    task.resume()
    
  }

  public func send(
    _ request: URLRequest
  ) -> URLSession.DataTaskPublisher {

    session.dataTaskPublisher(for: request)

  }
  
}
