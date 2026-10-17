// SPDX-License-Identifier: GPL-3.0-only
import Foundation
public enum ContentKind:String,CaseIterable,Identifiable,Sendable { case short,comic;public var id:String { rawValue };public var label:String { self == .short ? "短剧":"漫剧" } }
public struct Detail: Sendable { public let series:Series;public let episodes:[String] }
public struct CatalogPage: Sendable { public let items:[Series];public let hasMore:Bool;public let totalPages:Int }
public struct StreamInfo: Sendable { public let url:URL;public let key:Data?;public let quality:String }
public enum Playback {
    static func object(_ value:Any?) throws -> [String:Any] {
        if let value=value as? [String:Any] { return value }
        if let value=value as? String,let data=value.data(using:.utf8),let result=try JSONSerialization.jsonObject(with:data) as? [String:Any] { return result }
        throw HongguoError.message("播放数据格式异常")
    }
    static func entry(_ object:[String:Any],id:String) throws -> [String:Any] {
        let code=object["Code"] as? Int ?? object["code"] as? Int ?? 0
        guard code == 0 else { throw HongguoError.message("片源暂不可播放（错误 \(code)）") }
        guard let row=(object["data"] as? [String:Any])?[id] as? [String:Any] else { throw HongguoError.message("片源未返回所选分集") }
        return try self.object(row["video_model"])
    }
    static func quality(_ row:[String:Any])->Int {
        let text=row.text("quality_desc",fallback:row.text("height",fallback:row.text("vheight",fallback:row.text("quality"))))
        for n in [2160,1440,1080,720,576,540,480,360] where text.contains(String(n)) { return n };return Int(text) ?? 0
    }
    static func selected(_ rows:[String:Any],maxQuality:Int) throws -> [String:Any] {
        let compatible=rows.values.compactMap { $0 as? [String:Any] }.filter { !$0.text("main_url").isEmpty && !["bytevc2","bvc2"].contains($0.text("codec_type").lowercased()) }.sorted { quality($0)>quality($1) }
        guard let selected=compatible.first(where:{ quality($0)<=maxQuality }) ?? compatible.last else { throw HongguoError.message("没有兼容的播放资源") };return selected
    }
}
public enum Network {
    private struct HTTPFailure:LocalizedError {
        let status:Int
        let retryAfter:String?
        var errorDescription:String? { "内容请求失败（HTTP \(status)）" }
    }
    public static let videoUA="com.phoenix.read/71332 (Linux; U; Android 16; zh_CN; 25053RT47C; Build/BP2A.250605.031.A3; Cronet/TTNetVersion:04657795 2026-01-23 QuicVersion:c67e9834 2025-09-08)"
    static func validateRange(_ response:HTTPURLResponse,data:Data,start:Int64,end:Int64) throws -> Int64 {
        guard response.statusCode == 206,let text=response.value(forHTTPHeaderField:"Content-Range"),text.hasPrefix("bytes ") else { throw HongguoError.message("片源不支持分段读取") }
        let parts=text.dropFirst(6).split(separator:"/"),range=parts.first?.split(separator:"-") ?? []
        guard parts.count==2,range.count==2,let first=Int64(range[0]),let last=Int64(range[1]),let total=Int64(parts[1]),first==start,last==min(end,total-1),total>last,last>=first,Int64(data.count)==last-first+1 else { throw HongguoError.message("视频响应范围不一致") };return total
    }
    static func data(_ request:URLRequest,limit:Int=16*1024*1024,session:URLSession = .shared) async throws -> (Data,HTTPURLResponse) {
        var retries=0
        while true {
            try Task.checkCancellation()
            do { return try await read(request,limit:limit,session:session) }
            catch {
                try Task.checkCancellation()
                let reason=error as NSError
                let transientHTTP=(error as? HTTPFailure).map { [408,500,502,503,504].contains($0.status) && $0.retryAfter==nil } ?? false
                let transientConnection=reason.domain==NSURLErrorDomain && [URLError.secureConnectionFailed,.networkConnectionLost,.timedOut,.cannotConnectToHost,.cannotFindHost,.dnsLookupFailed,.notConnectedToInternet].map(\.rawValue).contains(reason.code)
                guard (request.httpMethod ?? "GET")=="GET",retries<2,transientHTTP || transientConnection else { throw error }
                let delay=retries==0 ? 300:900;retries+=1
                try await Task.sleep(for:.milliseconds(delay))
            }
        }
    }
    private static func read(_ request:URLRequest,limit:Int,session:URLSession) async throws -> (Data,HTTPURLResponse) {
        let (bytes,response)=try await session.bytes(for:request)
        guard let response=response as? HTTPURLResponse else { throw HongguoError.message("内容响应格式异常") }
        guard (200...299).contains(response.statusCode) else { throw HTTPFailure(status:response.statusCode,retryAfter:response.value(forHTTPHeaderField:"Retry-After")) }
        guard response.expectedContentLength<=limit else { throw HongguoError.message("内容响应过大") }
        var data=Data();data.reserveCapacity(Int(max(0,min(response.expectedContentLength,Int64(limit)))))
        for try await byte in bytes { if data.count>=limit { throw HongguoError.message("内容响应过大") };data.append(byte);if data.count&65535 == 0 { try Task.checkCancellation() } }
        try Task.checkCancellation();return (data,response)
    }
    public static func errorText(_ error:Error)->String {
        let reason=error as NSError
        guard reason.domain==NSURLErrorDomain else { return error.localizedDescription }
        if reason.code==URLError.notConnectedToInternet.rawValue { return "网络未连接，请检查 Wi-Fi 或移动数据" }
        if reason.code==URLError.timedOut.rawValue { return "连接超时，请稍后重试" }
        return "连接片源失败，请检查网络或稍后重试"
    }
    static func request(_ url:URL)->URLRequest { var request=URLRequest(url:url);request.timeoutInterval=30;request.setValue(videoUA,forHTTPHeaderField:"User-Agent");request.setValue("zh-CN,zh;q=0.9",forHTTPHeaderField:"Accept-Language");return request }
    static func json(_ request:URLRequest) async throws -> [String:Any] {
        let (data,_)=try await self.data(request);guard let json=try JSONSerialization.jsonObject(with:data) as? [String:Any] else { throw HongguoError.message("响应格式异常") };return json
    }
}
public actor Repository {
    private var indexes:[ContentKind:(Date,[Series])]=[:]
    private var signer:Signer?
    public init() {}
    private func router(_ path:String) async throws -> [String:Any] {
        let (data,_)=try await Network.data(Network.request(URL(string:"https://hongguoduanju.com"+path)!))
        guard let text=String(data:data,encoding:.utf8),let loader=try Catalog.router(text)["loaderData"] as? [String:Any] else { throw HongguoError.message("页面数据不可用") };return loader
    }
    public func home(page:Int=1,kind:ContentKind) async throws -> CatalogPage {
        guard (1...100).contains(page) else { throw HongguoError.message("分页参数无效") }
        let path=kind == .short ? "/category?tab=1&sort_type=1&page=\(page)":"/category/comic-drama?page=\(page)"
        let loader=try await router(path)
        guard let section=loader["category_page"] as? [String:Any] ?? loader["category_$"] as? [String:Any],let rows=section["recommendList"] as? [[String:Any]] ?? (section["categoryData"] as? [String:Any])?["recommendList"] as? [[String:Any]] else { throw HongguoError.message("片库数据暂不可用") }
        let pagination=section["pagination"] as? [String:Any] ?? [:],total=min(100,pagination["totalPages"] as? Int ?? 100)
        guard (pagination["pageNum"] as? Int ?? page) == page else { throw HongguoError.message("片库分页不一致") }
        var ids=Set<String>();let items=rows.compactMap(Catalog.card).filter { ids.insert($0.id).inserted }
        return CatalogPage(items:items,hasMore:!items.isEmpty && page<total,totalPages:total)
    }
    public func search(query:String,kind:ContentKind,progress:@Sendable (Int) async -> Void) async throws -> (items:[Series],indexed:Int) {
        guard !Catalog.normalized(query).isEmpty,query.count<=80 else { throw HongguoError.message("请输入剧名，最多 80 字") }
        if let (date,rows)=indexes[kind],Date().timeIntervalSince(date)<600 { return (Catalog.search(rows,query:query),rows.count) }
        let first=try await home(kind:kind);var rows=first.items
        await progress(rows.count)
        if first.totalPages>1 { for start in stride(from:2,through:first.totalPages,by:4) {
            try Task.checkCancellation()
            let pages=try await withThrowingTaskGroup(of:(Int,CatalogPage).self) { group in
                for page in start...min(start+3,first.totalPages) { group.addTask { (page,try await self.home(page:page,kind:kind)) } }
                var results=[(Int,CatalogPage)]();for try await result in group { results.append(result) };return results.sorted { $0.0<$1.0 }
            }
            for (_,page) in pages { guard !page.items.isEmpty else { throw HongguoError.message("片库索引不完整，请重试") };rows+=page.items };await progress(rows.count)
        } }
        var ids=Set<String>();rows=rows.filter { ids.insert($0.id).inserted };try Task.checkCancellation();indexes[kind]=(Date(),rows)
        return (Catalog.search(rows,query:query),rows.count)
    }
    public func detail(id:String) async throws -> Detail {
        guard Catalog.validID(id) else { throw HongguoError.message("剧集编号无效") }
        let loader=try await router("/detail?series_id=\(id)")
        guard let row=(loader["detail_page"] as? [String:Any])?["seriesDetail"] as? [String:Any],let series=Catalog.card(row),let raw=row["vid_list"] as? [Any] else { throw HongguoError.message("剧集详情不可用") }
        let episodes=raw.map { String(describing:$0) }
        guard !episodes.isEmpty,episodes.allSatisfy(Catalog.validID),Set(episodes).count==episodes.count else { throw HongguoError.message("分集数据异常") };return Detail(series:series,episodes:episodes)
    }
    public func stream(id:String) async throws -> StreamInfo {
        guard Catalog.validID(id) else { throw HongguoError.message("分集编号无效") }
        let payload="{\"biz_param\":{\"detail_page_version\":0,\"device_level\":3,\"disable_digg_stat\":false,\"need_all_video_definition\":true,\"need_mp4_align\":false,\"use_os_player\":false,\"use_server_dns\":false,\"video_platform\":1024},\"mixed_video_id_map\":{\"1004\":[\"\(id)\"]}}"
        if signer == nil { signer=try Signer() }
        let model=try Playback.entry(await Network.json(signer!.request(payload:payload)),id:id)
        var fallback=model["fallback_api"] as? String ?? ""
        if let object=try? Playback.object(model["fallback_api"]) { fallback=object.text("fallback_api") }
        if let array=model["fallback_api"] as? [String] { fallback=array.first ?? "" }
        guard let fallbackURL=URL(string:fallback),fallbackURL.scheme == "https" else { throw HongguoError.message("播放地址格式异常") }
        let response=try await Network.json(Network.request(fallbackURL))
        guard let info=(response["video_info"] as? [String:Any])?["data"] as? [String:Any],let list=info["video_list"] as? [String:Any] else { throw HongguoError.message("没有播放资源") }
        let selected=try Playback.selected(list,maxQuality:1080);var address=selected.text("main_url")
        if !info.text("key_seed").isEmpty { address=try MediaCrypto.decryptURL(address,seed:Data.base64(info.text("key_seed"))) }
        guard let url=URL(string:address),["https","http"].contains(url.scheme ?? "") else { throw HongguoError.message("播放地址无效") }
        let key=selected.text("spade_a").isEmpty ? nil:try MediaCrypto.deriveKey(selected.text("spade_a"))
        return StreamInfo(url:url,key:key,quality:"\(Playback.quality(selected))P")
    }
}
