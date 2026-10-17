import XCTest
@testable import HongguoCore

private final class RecoveryProtocol:URLProtocol {
    struct Step {
        var status=200
        var body=Data("ok".utf8)
        var headers:[String:String]=[:]
        var failure:URLError.Code?
    }
    final class Fixture {
        let steps:[Step]
        var requests:[URLRequest]=[]
        var firstRequest:(()->Void)?
        init(_ steps:[Step]) { self.steps=steps }
    }
    static let lock=NSLock()
    static var fixtures:[String:Fixture]=[:]
    override class func canInit(with request:URLRequest)->Bool { request.url?.host=="recovery.invalid" }
    override class func canonicalRequest(for request:URLRequest)->URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        guard let fixture=Self.fixtures[request.url!.path] else { Self.lock.unlock();client?.urlProtocol(self,didFailWithError:URLError(.badURL));return }
        let step=fixture.steps[min(fixture.requests.count,fixture.steps.count-1)]
        fixture.requests.append(request);let first=fixture.requests.count==1 ? fixture.firstRequest:nil
        Self.lock.unlock()
        first?()
        if let failure=step.failure { client?.urlProtocol(self,didFailWithError:URLError(failure));return }
        let response=HTTPURLResponse(url:request.url!,statusCode:step.status,httpVersion:"HTTP/1.1",headerFields:step.headers)!
        client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:step.body);client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class NetworkRecoveryTests:XCTestCase {
    private func run(_ steps:[RecoveryProtocol.Step],method:String="GET",limit:Int=1024,first:(()->Void)?=nil) async throws -> (Data,HTTPURLResponse,[URLRequest]) {
        let fixture=RecoveryProtocol.Fixture(steps);fixture.firstRequest=first
        let url=URL(string:"https://recovery.invalid/\(UUID().uuidString)")!
        RecoveryProtocol.lock.withLock { RecoveryProtocol.fixtures[url.path]=fixture }
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[RecoveryProtocol.self]
        let session=URLSession(configuration:config)
        defer { session.invalidateAndCancel();_ = RecoveryProtocol.lock.withLock { RecoveryProtocol.fixtures.removeValue(forKey:url.path) } }
        var request=URLRequest(url:url);request.httpMethod=method;request.setValue("bytes=10-11",forHTTPHeaderField:"Range")
        do {
            let (data,response)=try await Network.data(request,limit:limit,session:session)
            let requests=RecoveryProtocol.lock.withLock { fixture.requests }
            return (data,response,requests)
        } catch {
            let count=RecoveryProtocol.lock.withLock { fixture.requests.count }
            throw ObservedFailure(cause:error,attempts:count)
        }
    }
    private struct ObservedFailure:Error { let cause:Error;let attempts:Int }
    func testRangeGETRecoversFromTwoTransientResponsesWithoutChangingTheRequest() async throws {
        let (data,response,requests)=try await run([.init(status:503),.init(status:502),.init(status:206,headers:["Content-Range":"bytes 10-11/100"])])
        XCTAssertEqual(data,Data("ok".utf8));XCTAssertEqual(try Network.validateRange(response,data:data,start:10,end:11),100)
        XCTAssertEqual(requests.count,3);XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField:"Range")=="bytes=10-11" && $0.url==requests.first?.url })
    }
    func testTransportFailuresRecoverWithinTheSameBoundedBudget() async throws {
        let (data,_,requests)=try await run([.init(failure:.networkConnectionLost),.init(failure:.timedOut),.init()])
        XCTAssertEqual(data,Data("ok".utf8));XCTAssertEqual(requests.count,3)
    }
    func testPersistentTemporaryFailureStopsAfterThreeAttempts() async throws {
        do { _=try await run([.init(status:503)]);XCTFail("must stop") }
        catch let failure as ObservedFailure { XCTAssertEqual(failure.attempts,3);XCTAssertTrue(failure.cause.localizedDescription.contains("503")) }
    }
    func testPermanentResponsesSignedPOSTAndOversizedDataAreNotRetried() async throws {
        for code in [400,401,403,404,410,416,429] {
            do { _=try await run([.init(status:code)]);XCTFail("must fail") }
            catch let failure as ObservedFailure { XCTAssertEqual(failure.attempts,1) }
        }
        do { _=try await run([.init(status:503)],method:"POST");XCTFail("must not replay signed POST") }
        catch let failure as ObservedFailure { XCTAssertEqual(failure.attempts,1) }
        do { _=try await run([.init(body:Data("oversized".utf8))],limit:2);XCTFail("must reject oversize") }
        catch let failure as ObservedFailure { XCTAssertEqual(failure.attempts,1) }
        do { _=try await run([.init(failure:.serverCertificateUntrusted)]);XCTFail("must reject certificate") }
        catch let failure as ObservedFailure { XCTAssertEqual(failure.attempts,1) }
        do { _=try await run([.init(status:503,headers:["Retry-After":"120"])]);XCTFail("must respect server backoff") }
        catch let failure as ObservedFailure { XCTAssertEqual(failure.attempts,1) }
    }
    func testCancellationDuringRecoveryDoesNotSendAnotherRequest() async throws {
        let first=expectation(description:"first request")
        let task=Task { try await run([.init(status:503)],first:{ first.fulfill() }) }
        await fulfillment(of:[first],timeout:2);task.cancel()
        do { _=try await task.value;XCTFail("must cancel") }
        catch let failure as ObservedFailure { XCTAssertEqual(failure.attempts,1);XCTAssertTrue(failure.cause is CancellationError || (failure.cause as? URLError)?.code == .cancelled) }
    }
}
