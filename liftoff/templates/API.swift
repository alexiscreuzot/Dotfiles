//
//  APIProvider.swift
//
//  Created by Alexis Creuzot on 17/12/2015.
//  Copyright © 2015 alexiscreuzot. All rights reserved.
//

import Foundation
import Alamofire
import SwiftyJSON

open class API {

    open static let baseURL: String = "https://api.example.com/"
    open static let version: String = "v1"
    open static let apiKey: String = ""

    public enum Endpoints {

        case search(String)

        public var method: Alamofire.HTTPMethod {
            switch self {
            case .search:
                return .get
            }
        }

        public var path: String {

            switch self {
            case .search:
                return baseURL + version + "/search"
            }
        }

        public var parameters: [String: String] {
            var parameters = Dictionary<String, String>()
            parameters["key"] = apiKey

            switch self {
            case .search(let searchString):
                parameters["q"] = searchString
                break
            }
            return parameters
        }

        public var headers: [String: String] {
            return [:]
        }
    }

    open static func request(
        _ endpoint: API.Endpoints,
        completionHandler: @escaping (URLRequest, HTTPURLResponse?, SwiftyJSON.JSON, NSError?) -> Void)
        -> DataRequest {

            let request  = Alamofire.request(endpoint.path,
                                             method: endpoint.method,
                                             parameters: endpoint.parameters,
                                             encoding: URLEncoding.default,
                                             headers: endpoint.headers)
                .validate(statusCode: 200 ..< 300)
                //                .responseString { response in
                //                    print("\n <----\nResponse String: \(response.result.value) ")
                //                }
                .validate(contentType: ["application/json"])
                .responseSwiftyJSON { (request, response, json, error) in

                    if let err = error {
                        log.error("\n <----\n\(err)")
                        completionHandler(request, response, json, error)
                    } else {
                        log.info("\n <----\n\(request)")
                        log.verbose(json)
                        completionHandler(request, response, json, error)
                    }
            }

            log.info("\n---- > \n" + request.description + "\n" + "Headers: " + endpoint.headers.description + "\nParameters: " + endpoint.parameters.description)
            return request
    }
}
