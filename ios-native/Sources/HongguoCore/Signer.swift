// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import JavaScriptCore
public final class Signer {
    let context: JSContext
    private let nonce=UUID().uuidString
    private let started=(Date().timeIntervalSince1970*1000).rounded(.down)
    private(set) var exception: String?
    public init() throws {
        guard let context=JSContext() else { throw HongguoError.message("签名引擎无法初始化") }; self.context=context
        let hash: @convention(block) (String,String)->String = { algorithm,input in
            guard let data=Data(base64Encoded:input) else { return "" }
            return Crypto.hash(algorithm,data).base64EncodedString()
        }
        context.setObject(hash,forKeyedSubscript:"nativeHash" as NSString)
        context.exceptionHandler = { [weak self] _,value in self?.exception=value?.toString() }
        for name in ["buffer","signing"] {
            guard let url=Bundle.module.url(forResource:name,withExtension:"js") else { throw HongguoError.message("签名资源缺失") }
            context.evaluateScript(try String(contentsOf:url),withSourceURL:url)
            if let exception { throw HongguoError.message("签名初始化失败：\(exception)") }
        }
    }
    public func request(payload:String) throws -> URLRequest {
        exception=nil
        let randomId={ String(UInt64.random(in:1_000_000_000_000_000...9_999_999_999_999_999)) }
        guard let result=context.objectForKeyedSubscript("signedRequest")?.call(withArguments:[payload,nonce,started,(Date().timeIntervalSince1970*1000).rounded(.down),randomId(),randomId()])?.toDictionary(),exception == nil, let address=result["url"] as? String,let url=URL(string:address),let headers=result["headers"] as? [String:String] else { throw HongguoError.message(exception ?? "播放签名失败") }
        var request=URLRequest(url:url);request.httpMethod="POST";request.httpBody=Data(payload.utf8);request.allHTTPHeaderFields=headers;request.timeoutInterval=30
        return request
    }
}
