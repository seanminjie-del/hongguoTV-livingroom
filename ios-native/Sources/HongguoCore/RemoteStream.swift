// SPDX-License-Identifier: GPL-3.0-only
import Foundation
public actor RemoteStream {
    private let info:StreamInfo
    private var total:Int64=0
    private var prepared:MediaCrypto.Prepared?
    private var prefix=Data()
    private var cache:(Int64,Data)?
    public init(info:StreamInfo) { self.info=info }
    private func fetch(start:Int64,end:Int64) async throws -> (Data,Int64) {
        var request=Network.request(info.url);request.setValue("bytes=\(start)-\(end)",forHTTPHeaderField:"Range");request.setValue("identity",forHTTPHeaderField:"Accept-Encoding");request.setValue("https://novel.snssdk.com/",forHTTPHeaderField:"Referer")
        let (data,response)=try await Network.data(request,limit:8*1024*1024)
        let size=try Network.validateRange(response,data:data,start:start,end:end);return (data,size)
    }
    public func prepare() async throws -> Int64 {
        if prepared != nil { return total }
        let (initial,size)=try await fetch(start:0,end:262143)
        let end=try MediaCrypto.headerEnd(initial,total:size)
        let full:Data
        if end>initial.count { let (data,newTotal)=try await fetch(start:0,end:Int64(end-1));guard size==newTotal else { throw HongguoError.message("片源大小发生变化") };full=data } else { full=initial }
        let parsed=try MediaCrypto.prepare(full,key:info.key)
        total=size;prefix=full;prepared=parsed;return total
    }
    public func read(start:Int64,length:Int) async throws -> Data {
        guard start>=0,length>0,length<=512*1024 else { throw HongguoError.message("读取范围无效") }
        if prepared == nil { _=try await prepare() }
        guard let prepared,start<total else { return Data() }
        let stop=min(total,start+Int64(length))
        let raw:Data
        if stop<=prefix.count { raw=prefix.subdata(in:Int(start)..<Int(stop)) }
        else if let (offset,data)=cache,start>=offset,stop<=offset+Int64(data.count) { raw=data.subdata(in:Int(start-offset)..<Int(stop-offset)) }
        else {
            let (data,size)=try await fetch(start:start,end:stop-1);guard size==total else { throw HongguoError.message("片源大小发生变化") };cache=(start,data);raw=data
        }
        try Task.checkCancellation();return try MediaCrypto.decrypt(raw,start:start,key:info.key,prepared:prepared)
    }
}
