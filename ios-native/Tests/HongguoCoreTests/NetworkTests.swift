import XCTest
@testable import HongguoCore
final class TransientProtocol:URLProtocol {
    static let lock=NSLock()
    static var attempts=0
    override class func canInit(with request:URLRequest)->Bool { request.url?.host == "probe.invalid" }
    override class func canonicalRequest(for request:URLRequest)->URLRequest { request }
    override func startLoading() {
        Self.lock.lock();Self.attempts+=1;let attempt=Self.attempts;Self.lock.unlock()
        if attempt == 1 { client?.urlProtocol(self,didFailWithError:URLError(.secureConnectionFailed));return }
        let response=HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:"HTTP/1.1",headerFields:["Content-Length":"2"])!
        client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed);client?.urlProtocol(self,didLoad:Data("ok".utf8));client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
final class NetworkTests:XCTestCase {
    func testGETRecoversFromOneTransientTLSFailure() async throws {
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[TransientProtocol.self]
        let session=URLSession(configuration:config);defer { session.invalidateAndCancel() }
        TransientProtocol.attempts=0
        let (data,response)=try await Network.data(URLRequest(url:URL(string:"https://probe.invalid/")!),session:session)
        XCTAssertEqual(String(data:data,encoding:.utf8),"ok");XCTAssertEqual(response.statusCode,200)
    }
    func testPOSTDoesNotRepeat() async throws {
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[TransientProtocol.self]
        let session=URLSession(configuration:config);defer { session.invalidateAndCancel() }
        TransientProtocol.attempts=0
        var request=URLRequest(url:URL(string:"https://probe.invalid/")!);request.httpMethod="POST"
        do { _=try await Network.data(request,session:session);XCTFail("POST must not be repeated") }
        catch { XCTAssertEqual((error as NSError).code,URLError.secureConnectionFailed.rawValue) }
    }
}
