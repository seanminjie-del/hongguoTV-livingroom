// GPL-3.0-only. Port of the verified kotlin-tv/core MediaCrypto implementation.
import Foundation
public enum MediaCrypto {
    public struct Sample: Sendable { public var start:Int64;public var end:Int64;public var iv:Data;public var encryptedOffset:Int64=0 }
    public struct Prepared: Sendable { public var header:Data;public var samples:[Sample] }
    public static func deriveKey(_ value:String) throws -> Data {
        let raw=Array(try Data.base64(value));guard raw.count>=3 else { throw HongguoError.message("内容密钥格式异常") }
        let length=min(raw.count-Int(raw[0]^raw[1]^raw[2])+47,raw.count-1)
        guard length>=33 else { throw HongguoError.message("内容密钥长度异常") }
        var work=Array(raw[1...length]),a:UInt8=85,b:UInt8=246
        for i in work.indices { let old=work[i],previous=i&1 != 0 ? a:b;if i&1 != 0 { a=old } else { b=old };work[i]=UInt8(truncatingIfNeeded:-21-i.nonzeroBitCount+Int(previous^old)) }
        let key=try Data.hex(String(decoding:work[1..<33],as:UTF8.self));guard key.count == 16 else { throw HongguoError.message("内容密钥无效") };return key
    }
    public static func decryptURL(_ value:String,seed:Data) throws -> String {
        let raw=try Data.base64(value);guard raw.count>=20,raw[0]==0xa8,raw[2]==1,raw[3]==0 else { throw HongguoError.message("播放地址格式异常") }
        let constants=try Data.hex("4dd4c2e6b83162090e52b3c7a6733ba41cb2462b829ab58a196b39db57177524f49baf7f08e8d68d26a72e37c1a95a2f1f05a51892aef2949732b62a38aadd58")
        let h=Crypto.hash("sha512",Crypto.hash("sha512",seed)+constants)
        var result=try Crypto.aes(raw.subdata(in:4..<4+(raw.count-4)/16*16),key:h.subdata(in:0..<16),iv:h.subdata(in:16..<32),ctr:false)
        if let padding=result.last,padding>=1,padding<=16,Int(padding)<=result.count { result.removeLast(Int(padding)) };while result.last==0 { result.removeLast() }
        guard let url=String(data:result,encoding:.utf8) else { throw HongguoError.message("播放地址解密失败") };return url
    }
    struct Box { var start:Int;var end:Int;var body:Int;var type:String }
    static func u32(_ b:[UInt8],_ at:Int) throws -> Int64 {
        guard at>=0,at<=b.count-4 else { throw HongguoError.message("视频索引越界") }
        return Int64(b[at])<<24 | Int64(b[at+1])<<16 | Int64(b[at+2])<<8 | Int64(b[at+3])
    }
    static func u64(_ b:[UInt8],_ at:Int) throws -> Int64 {
        let hi=try u32(b,at),lo=try u32(b,at+4);guard hi<=0x7fffffff else { throw HongguoError.message("视频偏移过大") };return hi<<32 | lo
    }
    static func box(_ b:[UInt8],_ at:Int,_ limit:Int) throws -> Box? {
        guard at>=0,at<=limit-8,limit<=b.count else { return nil }
        var size=try u32(b,at),header=8
        if size == 1 { guard at<=limit-16 else { return nil };size=try u64(b,at+8);header=16 }
        if size == 0 { size=Int64(limit-at) }
        guard size>=header,size<=limit-at else { return nil }
        return Box(start:at,end:at+Int(size),body:at+header,type:String(decoding:b[at+4..<at+8],as:UTF8.self))
    }
    static func find(_ b:[UInt8],_ type:String,_ start:Int,_ limit:Int) throws -> Box? {
        guard start<=limit-8 else { return nil }
        let first=type.utf8.first!
        for at in start...limit-8 where b[at+4] == first { if let box=try box(b,at,limit),box.type == type { return box } };return nil
    }
    public static func headerEnd(_ data:Data,total:Int64) throws -> Int {
        let b=Array(data);guard b.count>=16,String(decoding:b[4..<8],as:UTF8.self)=="ftyp" else { throw HongguoError.message("不支持的视频容器") }
        let ftyp=try u32(b,0);guard ftyp>=8,ftyp<=b.count-8,String(decoding:b[Int(ftyp)+4..<Int(ftyp)+8],as:UTF8.self)=="moov" else { throw HongguoError.message("视频索引不在文件开头") }
        let size=try u32(b,Int(ftyp)),end=ftyp+size
        guard size>=8,end<=total,end<=8*1024*1024 else { throw HongguoError.message("视频索引大小异常") };return Int(end)
    }
    public static func prepare(_ data:Data,key:Data?) throws -> Prepared {
        if key == nil { return Prepared(header:data,samples:[]) }
        let b=Array(data);var header=b,samples=[Sample]()
        guard let moov=try box(b,Int(u32(b,0)),b.count),moov.type == "moov" else { throw HongguoError.message("视频索引不完整") }
        func count(_ at:Int,_ limit:Int) throws -> Int { guard at<=limit-4 else { throw HongguoError.message("索引越界") };let n=try u32(b,at);guard n<=200000 else { throw HongguoError.message("索引数量过大") };return Int(n) }
        var cursor=moov.body
        while cursor<moov.end {
            guard let track=try box(b,cursor,moov.end) else { throw HongguoError.message("视频轨道格式异常") };cursor=track.end;if track.type != "trak" { continue }
            guard let stbl=try find(b,"stbl",track.body,track.end),let saiz=try find(b,"saiz",stbl.body,stbl.end) else { continue }
            guard let saio=try find(b,"saio",stbl.body,stbl.end),let stsz=try find(b,"stsz",stbl.body,stbl.end),let stsc=try find(b,"stsc",stbl.body,stbl.end),let chunks=try find(b,"stco",stbl.body,stbl.end) ?? find(b,"co64",stbl.body,stbl.end) else { throw HongguoError.message("视频样本索引缺失") }
            let n=try count(stsz.body+8,stsz.end),defaultSize=try u32(b,stsz.body+4)
            guard defaultSize>0 || stsz.body+12+n*4<=stsz.end else { throw HongguoError.message("样本索引截断") }
            let sizes=try (0..<n).map { defaultSize>0 ? defaultSize:try u32(b,stsz.body+12+$0*4) }
            let chunkCount=try count(chunks.body+4,chunks.end),width=chunks.type == "co64" ? 8:4
            guard chunks.body+8+chunkCount*width<=chunks.end else { throw HongguoError.message("块偏移截断") }
            let offsets=try (0..<chunkCount).map { width == 8 ? try u64(b,chunks.body+8+$0*8):try u32(b,chunks.body+8+$0*4) }
            let entryCount=try count(stsc.body+4,stsc.end)
            guard entryCount>0,stsc.body+8+entryCount*12<=stsc.end else { throw HongguoError.message("块索引截断") }
            let entries=try (0..<entryCount).map { (try u32(b,stsc.body+8+$0*12),try u32(b,stsc.body+12+$0*12)) }
            let sizeBase=saiz.body+4+(try u32(b,saiz.body)&1 != 0 ? 8:0)
            guard sizeBase+5<=saiz.end else { throw HongguoError.message("辅助索引截断") }
            let auxDefault=Int(b[sizeBase]),auxCount=try count(sizeBase+1,saiz.end)
            guard auxCount == n,auxDefault>0 || sizeBase+5+n<=saiz.end else { throw HongguoError.message("辅助索引数量不一致") }
            let auxSizes=(0..<n).map { auxDefault>0 ? auxDefault:Int(b[sizeBase+5+$0]) }
            let offsetBase=saio.body+4+(try u32(b,saio.body)&1 != 0 ? 8:0),offsetWidth=b[saio.body] == 1 ? 8:4
            guard try count(offsetBase,saio.end)==1,offsetBase+4+offsetWidth<=saio.end else { throw HongguoError.message("不支持的辅助索引布局") }
            var aux=Int(try offsetWidth == 8 ? u64(b,offsetBase+4):u32(b,offsetBase+4))
            guard aux<=b.count,auxSizes.reduce(0,+)<=b.count-aux else { throw HongguoError.message("辅助数据超出索引范围") }
            var sampleIndex=0,entry=0
            for chunk in offsets.indices {
                while entry+1<entries.count,entries[entry+1].0<=chunk+1 { entry+=1 }
                let amount=entries[entry].1
                guard amount<=n-sampleIndex,entries[entry].0<=chunk+1 else { throw HongguoError.message("样本与块数量不一致") }
                var position=offsets[chunk]
                for _ in 0..<Int(amount) {
                    let length=sizes[sampleIndex],auxSize=auxSizes[sampleIndex]
                    guard length>0,position<=Int64.max-length,auxSize>=8 else { throw HongguoError.message("样本索引异常") }
                    let iv=Data(b[aux..<aux+8])+Data(repeating:0,count:8)
                    if auxSize == 8 { samples.append(Sample(start:position,end:position+length,iv:iv)) }
                    else {
                        guard auxSize>=10 else { throw HongguoError.message("不支持的加密样本格式") }
                        let subs=Int(b[aux+8])<<8 | Int(b[aux+9]);guard auxSize == 10+subs*6 else { throw HongguoError.message("加密子样本索引异常") }
                        var offset=position,encrypted:Int64=0
                        for sub in 0..<subs {
                            let at=aux+10+sub*6,clear=Int64(b[at])<<8 | Int64(b[at+1]),size=try u32(b,at+2)
                            guard clear<=position+length-offset else { throw HongguoError.message("加密子样本越界") };offset+=clear
                            guard size<=position+length-offset else { throw HongguoError.message("加密子样本越界") }
                            if size>0 { samples.append(Sample(start:offset,end:offset+size,iv:iv,encryptedOffset:encrypted)) };encrypted+=size;offset+=size
                        }
                        guard offset == position+length else { throw HongguoError.message("加密子样本长度异常") }
                    }
                    position+=length;aux+=auxSize;sampleIndex+=1
                }
            }
            guard sampleIndex==n else { throw HongguoError.message("视频样本不完整") }
            var at=stbl.body
            while let sinf=try find(b,"sinf",at,stbl.end) {
                guard let frma=try find(b,"frma",sinf.body,sinf.end),frma.body+4<=frma.end else { throw HongguoError.message("原始编码格式缺失") }
                if sinf.start>stbl.body { for entryAt in stride(from:sinf.start-1,through:stbl.body,by:-1) {
                    let type=String(decoding:b[entryAt..<entryAt+4],as:UTF8.self)
                    if type == "encv" || type == "enca" { header.replaceSubrange(entryAt..<entryAt+4,with:b[frma.body..<frma.body+4]);break }
                } }
                header.replaceSubrange(sinf.start+4..<sinf.start+8,with:Array("free".utf8));for index in sinf.body..<sinf.end { header[index]=0 };at=sinf.end
            }
        }
        guard !samples.isEmpty else { throw HongguoError.message("视频加密索引不可用") }
        samples.sort { $0.start<$1.start };for i in 1..<max(1,samples.count) where samples[i-1].end>samples[i].start { throw HongguoError.message("视频样本重叠") }
        return Prepared(header:Data(header),samples:samples)
    }
    public static func decrypt(_ data:Data,start:Int64,key:Data?,prepared:Prepared) throws -> Data {
        guard start>=0,start<=Int64.max-Int64(data.count) else { throw HongguoError.message("视频读取范围异常") }
        var result=data;let end=start+Int64(data.count)
        if start<prepared.header.count { let stop=min(Int64(prepared.header.count),end);result.replaceSubrange(0..<Int(stop-start),with:prepared.header.subdata(in:Int(start)..<Int(stop))) }
        guard let key else { return result }
        var low=0,high=prepared.samples.count
        while low<high { let mid=(low+high)/2;if prepared.samples[mid].end<=start { low=mid+1 } else { high=mid } }
        for sample in prepared.samples[low...] {
            if sample.start>=end { break };let begin=max(start,sample.start),stop=min(end,sample.end);if begin>=stop { continue }
            let relative=begin-sample.start+sample.encryptedOffset,skip=Int(relative%16)
            var iv=Array(sample.iv),carry=UInt64(relative/16)
            guard iv.count == 16 else { throw HongguoError.message("样本计数器无效") }
            for i in stride(from:15,through:0,by:-1) { let sum=UInt64(iv[i])+(carry&255);iv[i]=UInt8(truncatingIfNeeded:sum);carry=(carry>>8)+(sum>>8) }
            let range=Int(begin-start)..<Int(stop-start)
            let decrypted=try Crypto.aes(Data(repeating:0,count:skip)+result.subdata(in:range),key:key,iv:Data(iv),ctr:true)
            result.replaceSubrange(range,with:decrypted.dropFirst(skip))
        }
        return result
    }
}
