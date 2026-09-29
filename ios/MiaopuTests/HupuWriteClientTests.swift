import XCTest
@testable import Miaopu

final class HupuWriteClientTests: XCTestCase {
    override func tearDown() {
        WriteMockURLProtocol.handler = nil
        super.tearDown()
    }

    func testScoreSendsAuthenticatedJSONToTrustedEndpoint() async throws {
        var observed: URLRequest?
        WriteMockURLProtocol.handler = { request in
            observed = request
            return (200, Data(#"{"code":1,"success":true}"#.utf8))
        }
        let client = HupuWriteClient(configuration: mockConfiguration())
        _ = try await client.score(outBizKey: HupuOutBizKey(outBizType: "fictional", outBizNo: "fixture-7"), score: 8, cookies: [cookie(name: "ua", value: "fictional-session"), cookie(name: "unrelated", value: "do-not-send", domain: ".example.test")])
        XCTAssertEqual(observed?.url?.absoluteString, "https://games.mobileapi.hupu.com/1/8.2.99/bplcommentapi/bpl/score/save")
        XCTAssertEqual(observed?.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(observed?.value(forHTTPHeaderField: "Cookie"), "ua=fictional-session")
        let body = try XCTUnwrap(observed?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["score"] as? Int, 8)
        XCTAssertEqual(json["source"] as? String, "")
        XCTAssertEqual((json["outBizKey"] as? [String: String])?["outBizNo"], "fixture-7")
    }

    func testCommentAndReplyUseExpectedPathsAndFields() async throws {
        var requests: [URLRequest] = []
        WriteMockURLProtocol.handler = { request in
            requests.append(request)
            return (200, Data(#"{"success":true}"#.utf8))
        }
        let client = HupuWriteClient(configuration: mockConfiguration())
        let auth = [cookie(name: "ua", value: "session")]
        let key = HupuOutBizKey(outBizType: "type", outBizNo: "number")
        _ = try await client.comment(content: "fictional text", outBizKey: key, cookies: auth)
        _ = try await client.reply(content: "fictional reply", outBizKey: key, parentCommentId: "comment-9", cookies: auth)
        XCTAssertTrue(requests[0].url!.path.hasSuffix("/1/8.2.99/bplcommentapi/bpl/comment/m/publish"))
        let firstBody = try XCTUnwrap(requests[0].httpBody)
        let first = try XCTUnwrap(JSONSerialization.jsonObject(with: firstBody) as? [String: Any])
        XCTAssertEqual(first["source"] as? String, "m")
        XCTAssertEqual(first["subjectId"] as? String, "")
        XCTAssertTrue(requests[1].url!.path.hasSuffix("/1/8.2.58/bplcommentapi/bpl/comment/publish"))
        let secondBody = try XCTUnwrap(requests[1].httpBody)
        let second = try XCTUnwrap(JSONSerialization.jsonObject(with: secondBody) as? [String: Any])
        XCTAssertEqual(second["parentCommentId"] as? String, "comment-9")
        XCTAssertEqual((second["images"] as? [Any])?.count, 0)
        XCTAssertEqual((second["ancillaryContents"] as? [Any])?.count, 0)
    }

    func testRejectsMissingLoginCookieAndInvalidScore() async {
        let client = HupuWriteClient(configuration: mockConfiguration())
        do {
            _ = try await client.score(outBizKey: HupuOutBizKey(outBizType: "x", outBizNo: "y"), score: 2, cookies: [cookie(name: "other", value: "x")])
            XCTFail("Expected authentication rejection")
        } catch { XCTAssertEqual(error as? HupuWriteClientError, .unauthenticated) }
        do {
            _ = try await client.score(outBizKey: HupuOutBizKey(outBizType: "x", outBizNo: "y"), score: 3, cookies: [cookie(name: "ua", value: "session")])
            XCTFail("Expected invalid score rejection")
        } catch { XCTAssertEqual(error as? HupuWriteClientError, .invalidInput) }
    }

    func testMapsAPIAndHTTPFailures() async throws {
        let client = HupuWriteClient(configuration: mockConfiguration())
        let auth = [cookie(name: "ua", value: "session")]
        WriteMockURLProtocol.handler = { _ in (200, Data(#"{"code":42,"success":false}"#.utf8)) }
        do {
            _ = try await client.light(commentId: "c1", subjectId: "s1", cookies: auth)
            XCTFail("Expected API failure")
        } catch { XCTAssertEqual(error as? HupuWriteClientError, .apiFailure(42)) }
        WriteMockURLProtocol.handler = { _ in (503, Data()) }
        do {
            _ = try await client.light(commentId: "c1", subjectId: "s1", cookies: auth)
            XCTFail("Expected HTTP failure")
        } catch { XCTAssertEqual(error as? HupuWriteClientError, .httpStatus(503)) }
    }

    private func mockConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WriteMockURLProtocol.self]
        return configuration
    }

    private func cookie(name: String, value: String, domain: String = "games.mobileapi.hupu.com") -> HTTPCookie {
        HTTPCookie(properties: [.domain: domain, .path: "/", .name: name, .value: value, .secure: "TRUE"])!
    }
}

private final class WriteMockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == HupuWriteClient.host
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var observed = request
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var body = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                body.append(contentsOf: buffer[..<count])
            }
            observed.httpBodyStream = nil
            observed.httpBody = body
        }
        guard let (status, data) = Self.handler?(observed), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
