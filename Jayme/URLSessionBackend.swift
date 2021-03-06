// Jayme
// URLSessionBackend.swift
//
// Copyright (c) 2016 Inaka - http://inaka.net/
//
// Licensed to the Apache Software Foundation (ASF) under one
// or more contributor license agreements. See the NOTICE file
// distributed with this work for additional information
// regarding copyright ownership. The ASF licenses this file
// to you under the Apache License, Version 2.0 (the
// "License"); you may not use this file except in compliance
// with the License. You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied. See the License for the
// specific language governing permissions and limitations
// under the License.

import Foundation

/// Provides a `Backend` that connects to a server using HTTP REST requests via `URLSession`.
open class URLSessionBackend: Backend {
    
    public typealias BackendReturnType = (Data?, PageInfo?)
    public typealias BackendErrorType = JaymeError
    
    public init(configuration: URLSessionBackendConfiguration = URLSessionBackendConfiguration.defaultConfiguration,
         session: URLSession = URLSession.shared,
         responseParser: HTTPResponseParser = HTTPResponseParser()) {
        self.configuration = configuration
        self.session = session
        self.responseParser = responseParser
    }
    
    /// Returns a `Future` containing either:
    /// - A tuple with possible `NSData` relevant to the HTTP response and a possible `PageInfo` object if there is pagination-related info associated to it.
    /// - A `JaymeError` holding the error that occurred.
    open func future(path: Path, method: HTTPMethodName, parameters: [String: Any]? = nil) -> Future<(Data?, PageInfo?), JaymeError> {
        return Future() { completion in
            guard let request = try? self.request(path: path, method: method, parameters: parameters) else {
                completion(.failure(JaymeError.badRequest))
                return
            }
            let requestNumber = Logger.sharedLogger.requestCounter
            Logger.sharedLogger.requestCounter += 1
            Logger.sharedLogger.log("Jayme: Request #\(requestNumber) | URL: \(request.url!.absoluteString) | method: \(method.rawValue)")
            let task = self.session.dataTask(with: request) { data, response, error in
                let response: FullHTTPResponse = (data, response, error)
                let result = self.responseParser.parse(response)
                DispatchQueue.main.async {
                    switch result {
                    case .success(let maybeData, let pageInfo):
                        Logger.sharedLogger.log("Jayme: Response #\(requestNumber) | Success")
                        completion(.success(maybeData, pageInfo))
                    case .failure(let error):
                        Logger.sharedLogger.log("Jayme: Response #\(requestNumber) | Failure, error: \(error)")
                        completion(.failure(error))
                    }
                }
            }
            task.resume()
        }
    }
    
    // MARK: - Private
    
    fileprivate let configuration: URLSessionBackendConfiguration
    fileprivate let session: URLSession
    fileprivate let responseParser: HTTPResponseParser
    
    fileprivate var baseURL: URL? {
        return URL(string: self.configuration.basePath)
    }
    
    fileprivate func url(for path: Path) -> URL? {
        return self.baseURL?.appendingPathComponent(path)
    }
    
    fileprivate func request(path: Path, method: HTTPMethodName, parameters: [String: Any]?) throws -> URLRequest {
        guard let url = self.url(for: path) else {
            throw JaymeError.badRequest
        }
        let request = NSMutableURLRequest(url: url)
        request.httpMethod = method.rawValue
        for header in self.configuration.httpHeaders {
            request.addValue(header.value, forHTTPHeaderField: header.field)
        }
        guard let params = parameters else {
            return request as URLRequest
        }
        do {
            let body = try JSONSerialization.data(withJSONObject: params, options: .prettyPrinted)
            request.httpBody = body
        } catch {
            throw JaymeError.badRequest
        }
        return request as URLRequest
    }
    
}
