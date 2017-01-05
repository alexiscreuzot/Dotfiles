//
//  AlamofireSwiftyJSON.swift
//  AlamofireSwiftyJSON
//
//  Created by Pinglin Tang on 14-9-22.
//  Copyright (c) 2014 SwiftyJSON. All rights reserved.
//
import Foundation

import Alamofire
import SwiftyJSON

// MARK: - Request for Swift JSON
extension DataRequest {

    fileprivate func responseSwiftyJSON(_ completionHandler: @escaping (URLRequest, HTTPURLResponse?, SwiftyJSON.JSON, NSError?) -> Void) -> Self {
        return responseSwiftyJSON(nil, options:JSONSerialization.ReadingOptions.allowFragments, completionHandler:completionHandler)
    }

    public func responseSwiftyJSON(
        _ queue: DispatchQueue? = nil,
        options: JSONSerialization.ReadingOptions = .allowFragments,
        completionHandler:@escaping (URLRequest, HTTPURLResponse?, SwiftyJSON.JSON, NSError?) -> Void)
        -> Self {

            return response(queue: queue, responseSerializer: DataRequest.jsonResponseSerializer(options: options), completionHandler: { (response) in

                DispatchQueue.global(qos: .default).async(execute: {

                    var responseJSON: JSON
                    if response.result.isFailure {
                        responseJSON = JSON.null
                    } else {
                        responseJSON = SwiftyJSON.JSON(response.result.value!)
                    }
                    (queue ?? DispatchQueue.main).async(execute: {
                        completionHandler(response.request!, response.response, responseJSON, response.result.error as NSError?)
                    })
                })
            })
    }
}
