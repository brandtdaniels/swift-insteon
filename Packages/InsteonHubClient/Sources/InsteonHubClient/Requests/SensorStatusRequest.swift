//
//  SensorStatusRequest.swift
//  
//
//  Created by Brandt Daniels on 6/19/20.
//

import Foundation

public struct SensorStatusRequest {

  public enum Page: UInt8, CaseIterable {

    case zero, one, two, three, four, five, six, seven, eight, nine, ten, eleven, twelve, thirteen, fourteen, fifteen, sixteen

  }

  private let page: Page

  public init(page: Page) {

    self.page = page

  }

}

// MARK: - HubRequestProtocol

extension SensorStatusRequest: HubRequestProtocol {

  public func urlRequest(baseUrlComponents: URLComponents) -> URLRequest {

    let pageStr = String(format: "%02X", page.rawValue)

    var urlComponents = baseUrlComponents
    urlComponents.path = "/b.xml"
    urlComponents.percentEncodedQueryItems = [
      URLQueryItem(
        name: "01",
        value: "\(pageStr)=F"
      )
    ]

    return URLRequest(url: urlComponents.url!)

  }

}
