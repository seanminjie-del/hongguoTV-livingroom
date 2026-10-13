import XCTest
@testable import HongguoCore
final class CoreTests: XCTestCase {
    func testSM3StandardVector() {
        XCTAssertEqual(Crypto.hash("sm3", Data("abc".utf8)).map { String(format: "%02x", $0) }.joined(), "66c7f0f462eeedd9d1f2d46bdc10e4e24167c4875cf2f7a2297da02b8f4ba8e0")
    }
}
extension Data {
    init(hex: String) { self.init(stride(from: 0, to: hex.count, by: 2).map { i in let a=hex.index(hex.startIndex, offsetBy: i); return UInt8(hex[a..<hex.index(a, offsetBy: 2)], radix: 16)! }) }
}
extension CoreTests {
    func testRealtimeSigningUsesIntegerMilliseconds() throws {
        let request=try Signer().request(payload:"{}")
        XCTAssertEqual(request.httpMethod,"POST")
        XCTAssertFalse(request.value(forHTTPHeaderField:"x-medusa")?.isEmpty ?? true)
    }
    func testVisitorSignatureMatchesIndependentOracle() throws {
        let rows = try JSONSerialization.jsonObject(with: Data(contentsOf: Bundle.module.url(forResource: "visitor-signing", withExtension: "json")!)) as! [[String: Any]]
        let oracle=try String(contentsOf:Bundle.module.url(forResource:"oracle",withExtension:"js")!)
        for row in rows {
            let signer=try Signer();signer.context.evaluateScript(oracle)
            let actual=signer.context.objectForKeyedSubscript("oracle")?.call(withArguments:[row])?.toString()
            XCTAssertNil(signer.exception);XCTAssertEqual(actual,row["medusa"] as? String)
        }
    }
    func testRouterPreservesEscapedQuotesAndRejectsTruncation() throws {
        let parsed = try Catalog.router(#"<script>window._ROUTER_DATA = {"loaderData":{"x":"a}\"b","list":[1,2]}};</script>"#)
        XCTAssertEqual((parsed["loaderData"] as? [String: Any])?["x"] as? String, "a}\"b")
        XCTAssertThrowsError(try Catalog.router("_ROUTER_DATA={\"a\":"))
    }
    func testSearchNormalizesAndPrioritizesTitleThenDeduplicates() {
        let rows = [Series(id:"1", title:"别的", tags:"甜宠"), Series(id:"2", title:"甜宠！"), Series(id:"3", title:"甜宠归来"), Series(id:"2",title:"重复"), Series(id:"4",title:"无关")]
        XCTAssertEqual(Catalog.search(rows,query:"甜 宠").map(\.id), ["2","3","1"])
    }
    func testNISTCTRAtEveryUnalignedOffsetAndSubsamples() throws {
        let key=Data(hex:"2b7e151628aed2a6abf7158809cf4f3c"), iv=Data(hex:"f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff")
        let plain=Data(hex:"6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e5130c81c46a35ce411e5fbc1191a0a52eff69f2445df4f9b17ad2b417be66c3710")
        let cipher=Data(hex:"874d6191b620e3261bef6864990db6ce9806f66b7970fdff8617187bb9fffdff5ae4df3edbd5d35e5b4f09020db03eab1e031dda2fbe03d1792170a0f3009cee")
        let source=Data(repeating:0x66,count:23)+cipher+Data(repeating:0x77,count:12)
        let expected=Data(repeating:0x66,count:23)+plain+Data(repeating:0x77,count:12)
        let prepared=MediaCrypto.Prepared(header:Data(), samples:[.init(start:23,end:87,iv:iv)])
        for start in 0..<source.count { for length in 1...min(29,source.count-start) {
            XCTAssertEqual(try MediaCrypto.decrypt(source.subdata(in:start..<start+length),start:Int64(start),key:key,prepared:prepared),expected.subdata(in:start..<start+length))
        } }
        let split=Data([1,2,3])+cipher.prefix(21)+Data([4,5])+cipher.dropFirst(21)
        let splitExpected=Data([1,2,3])+plain.prefix(21)+Data([4,5])+plain.dropFirst(21)
        XCTAssertEqual(try MediaCrypto.decrypt(split,start:0,key:key,prepared:.init(header:Data(),samples:[.init(start:3,end:24,iv:iv),.init(start:26,end:69,iv:iv,encryptedOffset:21)])),splitExpected)
    }
    func testMP4RestoresAVCAndRejectsTruncatedAuxiliaryIndex() throws {
        func be(_ value: Int) -> Data { Data([UInt8(truncatingIfNeeded:value>>24),UInt8(truncatingIfNeeded:value>>16),UInt8(truncatingIfNeeded:value>>8),UInt8(truncatingIfNeeded:value)]) }
        func box(_ type: String,_ body: Data) -> Data { be(body.count+8)+Data(type.utf8)+body }
        func fixture(_ auxSize: UInt8) -> Data {
            let ftyp=box("ftyp",Data("isom0000".utf8))
            func moov(_ offset:Int) -> Data {
                let entry=box("encv",Data(repeating:0,count:78)+box("sinf",box("frma",Data("avc1".utf8))))
                let stsd=box("stsd",Data(repeating:0,count:4)+be(1)+entry)
                let stsz=box("stsz",Data(repeating:0,count:4)+be(16)+be(1))
                let stsc=box("stsc",Data(repeating:0,count:4)+be(1)+be(1)+be(1)+be(1))
                let stco=box("stco",Data(repeating:0,count:4)+be(1)+be(4096))
                let saiz=box("saiz",Data(repeating:0,count:4)+Data([auxSize])+be(1))
                let saio=box("saio",Data(repeating:0,count:4)+be(1)+be(offset))
                return box("moov",box("trak",box("mdia",box("minf",box("stbl",stsd+stsz+stsc+stco+saiz+saio))))+box("free",Data(repeating:0,count:8)))
            }
            return ftyp+moov((ftyp+moov(0)).count-8)
        }
        let data=fixture(8), key=Data(repeating:0,count:16)
        let prepared=try MediaCrypto.prepare(data,key:key)
        XCTAssertTrue(String(decoding:prepared.header,as:UTF8.self).contains("avc1"))
        XCTAssertFalse(String(decoding:prepared.header,as:UTF8.self).contains("sinf"))
        XCTAssertEqual(prepared.samples.first?.start,4096)
        XCTAssertEqual(try MediaCrypto.headerEnd(data,total:5000),data.count)
        XCTAssertThrowsError(try MediaCrypto.prepare(fixture(16),key:key))
        XCTAssertThrowsError(try MediaCrypto.headerEnd(box("ftyp",Data("isom0000".utf8))+be(9_000_000)+Data("moov".utf8),total:10_000_000))
    }
}
extension CoreTests {
    func testPlaybackRejectsWrongEpisodeAndIncompatibleCodec() throws {
        XCTAssertThrowsError(try Playback.entry(["code":0,"data":["456":["video_model":[:]]]],id:"123"))
        XCTAssertThrowsError(try Playback.entry(["Code":110001],id:"123"))
        let selected=try Playback.selected(["hd":["main_url":"https://example.com/a","height":1080,"codec_type":"bytevc2"],"sd":["main_url":"https://example.com/b","height":720,"codec_type":"h264"]],maxQuality:1080)
        XCTAssertEqual(selected["main_url"] as? String,"https://example.com/b")
    }
    func testRangeRequiresMatchingPartialResponse() throws {
        func response(_ code:Int,_ range:String) -> HTTPURLResponse { HTTPURLResponse(url:URL(string:"https://example.com/a")!,statusCode:code,httpVersion:"HTTP/1.1",headerFields:["Content-Range":range])! }
        XCTAssertEqual(try Network.validateRange(response(206,"bytes 10-13/50"),data:Data([1,2,3,4]),start:10,end:13),50)
        XCTAssertThrowsError(try Network.validateRange(response(200,"bytes 10-13/50"),data:Data([1,2,3,4]),start:10,end:13))
        XCTAssertThrowsError(try Network.validateRange(response(206,"bytes 0-3/50"),data:Data([1,2,3,4]),start:10,end:13))
        XCTAssertThrowsError(try Network.validateRange(response(206,"bytes 10-13/50"),data:Data([1,2,3]),start:10,end:13))
    }
    func testLiveShortAndComicResources() async throws {
        guard ProcessInfo.processInfo.environment["HONGGUO_LIVE"] == "1" else { throw XCTSkip("Explicit live provider check") }
        let repository=Repository()
        for kind in ContentKind.allCases {
            let page=try await repository.home(kind:kind)
            XCTAssertGreaterThan(page.items.count,10)
            let series=try XCTUnwrap(page.items.first)
            let detail=try await repository.detail(id:series.id)
            XCTAssertFalse(detail.episodes.isEmpty)
            let stream=try await repository.stream(id:try XCTUnwrap(detail.episodes.first))
            XCTAssertEqual(stream.url.scheme,"https")
            let remote=RemoteStream(info:stream)
            let count=try await remote.prepare()
            XCTAssertGreaterThan(count,10000)
            let prefix=try await remote.read(start:0,length:4096)
            XCTAssertEqual(String(decoding:prefix[4..<8],as:UTF8.self),"ftyp")
            print("Live \(kind.label): \(series.title), \(detail.episodes.count) episodes, \(stream.quality), \(count) bytes")
        }
    }
}
