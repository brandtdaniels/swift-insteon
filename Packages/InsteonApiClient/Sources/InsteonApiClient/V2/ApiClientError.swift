//
//  ApiClientError.swift
//  
//
//  Created by Brandt Daniels on 6/28/20.
//

import Foundation

public enum ApiClientError: Error {

  case decoding(message: String)

  case encoding(message: String)

  case request(message: String)

  case server(code: Int, message: String)

  case unknown(message: String)

}

// MARK: - LocalizedError

extension ApiClientError: LocalizedError {
  
  public var errorDescription: String? {
    
    switch self {
      
    case let .decoding(message): return message
    case let .encoding(message): return message
    case let .request(message): return message
    case let .server(code, message): return "Code: \(code), Message: \(message)"
    case let .unknown(message): return message
      
    }
    
  }
  
}
