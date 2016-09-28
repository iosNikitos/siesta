//
//  PerformanceTests.swift
//  Siesta
//
//  Created by Paul on 2016/9/27.
//  Copyright © 2016 Bust Out Solutions. All rights reserved.
//

import Foundation
import XCTest
import Siesta

class SiestaPerformanceTests: XCTestCase
    {
    func testGetExistingResources()
        {
        measure { self.exerciseResourceCache(uniqueResources: 20, iters: 20000) }
        }

    func testResourceCacheGrowth()
        {
        measure { self.exerciseResourceCache(uniqueResources: 10000, iters: 10000) }
        }

    func testResourceCacheChurn()
        {
        measure { self.exerciseResourceCache(uniqueResources: 10000, iters: 10000, countLimit: 100) }
        }

    func exerciseResourceCache(uniqueResources: Int, iters: Int, countLimit: Int = 100000)
        {
        let service = stubbedServce()
        service.cachedResourceCountLimit = countLimit
        for n in 0 ..< iters
            { _ = service.resource("/items/\(n % uniqueResources)") }
        }

    func testObserverChurn()
        {
        let resource = stubbedServce().resource("/observed")
        let observerCount = 5
        let observers = (1...observerCount).map { _ in TestObserver() }
        measure
            {
            for n in 0 ..< 2000
                {
                var x = 0
                resource.addObserver(observers[n % observerCount])
                resource.addObserver(owner: observers[(n * 7) % observerCount])
                    { _ in x += 1 }
                resource.removeObservers(ownedBy: observers[(n * 3) % observerCount])
                }
            }
        }

    func testObserverOwnerChurn()
        {
        let resource = stubbedServce().resource("/observed")
        let observerCount = 5
        var observers = (1...observerCount).map { _ in TestObserver() }

        measure
            {
            for n in 0 ..< 100
                {
                var x = 0
                resource.addObserver(observers[n % observerCount])
                resource.addObserver(owner: observers[(n * 7) % observerCount])
                    { _ in x += 1 }
                observers[(n * 3) % observerCount] = TestObserver()
                }
            }
        }

    func testRequestHooks()
        {
        let resource = stubbedServce().resource("/hooked")
        measure
            {
            for _ in 0 ..< 100
                {
                let req = resource.load()
                var callbacks = 0
                for _ in 0 ..< 100
                    { req.onCompletion { _ in callbacks += 1 } }
                let load = self.expectation(description: "load")
                req.onCompletion { _ in load.fulfill() }
                self.waitForExpectations(timeout: 1)
                }
            }
        }

    func testObserverNotifications()
        {
        let resourceCount = 50
        var responseStubs: [String:ResponseStub] = [:]
        for n in stride(from: 0, to: resourceCount, by: 2)
            { responseStubs["/zlerp\(n)"] = ResponseStub(data: Data()) }

        let service = stubbedServce(responses: responseStubs)
        let resources = (0 ..< resourceCount).map
            {
            service
                .resource("/zlerp\($0)")
                .addObserver(TestObserver())
            }

        measure
            {
            for _ in 0 ..< 10
                {
                for resource in resources
                    {
                    let load = self.expectation(description: "load")
                    resource.load().onCompletion { _ in load.fulfill() }
                    }
                self.waitForExpectations(timeout: 1)
                }
            }
        }
    }

func stubbedServce(responses: [String:ResponseStub] = [:]) -> Service
    {
    return Service(baseURL: "http://test.ing", networking: NetworkStub(responses: responses))
    }

struct NetworkStub: NetworkingProvider
    {
    var responses: [String:ResponseStub]
    let dummyHeaders =
        [
        "A-LITTLE": "madness in the Spring",
        "Is-wholesome": "even for the King",
        "But-God-be": "with the Clown",

        "Who-ponders": "this tremendous scene",
        "This-whole": "experiment of green",
        "As-if-it": "were his own!",

        "X-Author": "Emily Dickinson"
        ]

    init(responses: [String:ResponseStub])
        { self.responses = responses }

    func startRequest(
            _ request: URLRequest,
            completion: @escaping RequestNetworkingCompletionCallback)
        -> RequestNetworking
        {
        let responseStub = responses[request.url!.path]
        let statusCode = (responseStub != nil) ? 200 : 404
        var headers = dummyHeaders
        headers["Content-Type"] = responseStub?.contentType
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers)

        completion(response, responseStub?.data, nil)
        return RequestStub()
        }
    }

struct ResponseStub
    {
    let contentType: String = "application/octet-stream"
    let data: Data
    }

struct RequestStub: RequestNetworking
    {
    func cancel() { }

    /// Returns raw data used for progress calculation.
    var transferMetrics: RequestTransferMetrics
        {
        return RequestTransferMetrics(
                requestBytesSent: 0,
                requestBytesTotal: nil,
                responseBytesReceived: 0,
                responseBytesTotal: nil)
        }
    }

class TestObserver: ResourceObserver
    {
    public var eventCount = 0

    func resourceChanged(_ resource: Resource, event: ResourceEvent)
        { eventCount += 1 }
    }
