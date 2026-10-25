//
//  ApiClientProtocol.swift
//  
//
//  Created by Brandt Daniels on 6/28/20.
//

public typealias ResultCallback<Value> = (Result<Value?, ApiClientError>) -> Void

public protocol ApiClientProtocol {

  func request<T: RequestProtocol>(_ request: T, completion: @escaping ResultCallback<T.Response>)

  func request<T: ResponselessRequestProtocol>(_ request: T, completion: @escaping ResultCallback<Void>)

}
