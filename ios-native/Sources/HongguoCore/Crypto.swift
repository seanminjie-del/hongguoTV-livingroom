// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CommonCrypto
public enum Crypto {
    public static func hash(_ algorithm: String, _ data: Data) -> Data {
        if algorithm == "sm3" { return sm3(data) }
        var result=[UInt8](repeating:0,count:algorithm == "md5" ? 16:64)
        data.withUnsafeBytes { bytes in
            if algorithm == "md5" { _ = CC_MD5(bytes.baseAddress,CC_LONG(data.count),&result) }
            else { _ = CC_SHA512(bytes.baseAddress,CC_LONG(data.count),&result) }
        }
        return Data(result)
    }
    public static func aes(_ data: Data, key: Data, iv: Data, ctr: Bool) throws -> Data {
        guard key.count == 16, iv.count == 16 else { throw HongguoError.message("视频密钥无效") }
        var cryptor: CCCryptorRef?
        let status=key.withUnsafeBytes { k in iv.withUnsafeBytes { v in
            CCCryptorCreateWithMode(CCOperation(kCCDecrypt),CCMode(ctr ? kCCModeCTR:kCCModeCBC),CCAlgorithm(kCCAlgorithmAES),CCPadding(ccNoPadding),v.baseAddress,k.baseAddress,key.count,nil,0,0,CCModeOptions(ctr ? kCCModeOptionCTR_BE:0),&cryptor)
        } }
        guard status == kCCSuccess, let cryptor else { throw HongguoError.message("无法创建解密器") }
        defer { CCCryptorRelease(cryptor) }
        var result=[UInt8](repeating:0,count:data.count+16), written=0
        let update=data.withUnsafeBytes { bytes in CCCryptorUpdate(cryptor,bytes.baseAddress,data.count,&result,result.count,&written) }
        guard update == kCCSuccess else { throw HongguoError.message("视频解密失败") }
        return Data(result.prefix(written))
    }
    static func sm3(_ data: Data) -> Data {
        func rol(_ v:UInt32,_ n:Int)->UInt32 { let r=n&31; return r == 0 ? v : (v << r) | (v >> (32-r)) }
        func p0(_ v:UInt32)->UInt32 { v ^ rol(v,9) ^ rol(v,17) }
        func p1(_ v:UInt32)->UInt32 { v ^ rol(v,15) ^ rol(v,23) }
        var bytes=Array(data); let bits=UInt64(bytes.count)*8
        bytes.append(0x80); while bytes.count%64 != 56 { bytes.append(0) }
        for shift in stride(from:56,through:0,by:-8) { bytes.append(UInt8(truncatingIfNeeded:bits >> shift)) }
        var state:[UInt32]=[0x7380166f,0x4914b2b9,0x172442d7,0xda8a0600,0xa96f30bc,0x163138aa,0xe38dee4d,0xb0fb0e4e]
        for offset in stride(from:0,to:bytes.count,by:64) {
            var w=[UInt32](repeating:0,count:68)
            for i in 0..<16 { let a=offset+i*4; w[i]=UInt32(bytes[a])<<24 | UInt32(bytes[a+1])<<16 | UInt32(bytes[a+2])<<8 | UInt32(bytes[a+3]) }
            for i in 16..<68 { w[i]=p1(w[i-16]^w[i-9]^rol(w[i-3],15)) ^ rol(w[i-13],7) ^ w[i-6] }
            var a=state[0], b=state[1], c=state[2], d=state[3], e=state[4], f=state[5], g=state[6], h=state[7]
            for j in 0..<64 {
                let ss1=rol(rol(a,12) &+ e &+ rol(j<16 ? 0x79cc4519:0x7a879d8a,j),7), ss2=ss1 ^ rol(a,12)
                let ff=j<16 ? a^b^c : (a&b)|(a&c)|(b&c), gg=j<16 ? e^f^g : (e&f)|((~e)&g)
                let tt1=ff &+ d &+ ss2 &+ (w[j]^w[j+4]), tt2=gg &+ h &+ ss1 &+ w[j]
                d=c; c=rol(b,9); b=a; a=tt1; h=g; g=rol(f,19); f=e; e=p0(tt2)
            }
            for (i,value) in [a,b,c,d,e,f,g,h].enumerated() { state[i] ^= value }
        }
        return Data(state.flatMap { v in [UInt8(truncatingIfNeeded:v>>24),UInt8(truncatingIfNeeded:v>>16),UInt8(truncatingIfNeeded:v>>8),UInt8(truncatingIfNeeded:v)] })
    }
}
extension Data {
    static func hex(_ value:String) throws -> Data {
        guard value.count%2 == 0 else { throw HongguoError.message("十六进制格式错误") }
        var out=Data(); var i=value.startIndex
        while i<value.endIndex { let end=value.index(i,offsetBy:2); guard let n=UInt8(value[i..<end],radix:16) else { throw HongguoError.message("十六进制格式错误") }; out.append(n); i=end }
        return out
    }
    static func base64(_ value:String) throws -> Data {
        let cleaned=value.replacingOccurrences(of:"-",with:"+").replacingOccurrences(of:"_",with:"/")
        guard let out=Data(base64Encoded:cleaned+String(repeating:"=",count:(4-cleaned.count%4)%4)) else { throw HongguoError.message("密钥编码错误") }; return out
    }
}
