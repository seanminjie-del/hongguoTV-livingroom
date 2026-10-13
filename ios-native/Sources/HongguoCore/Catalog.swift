// SPDX-License-Identifier: GPL-3.0-only
import Foundation
public enum Catalog {
    public static func router(_ html: String) throws -> [String:Any] {
        guard let marker=html.range(of:"_ROUTER_DATA"),let first=html[marker.upperBound...].firstIndex(of:"{") else { throw HongguoError.message("页面没有内容数据") }
        var depth=0, quoted=false,escaped=false
        for index in html[first...].indices {
            let c=html[index]
            if quoted { if escaped { escaped=false } else if c == "\\" { escaped=true } else if c == "\"" { quoted=false };continue }
            switch c {
            case "\"":quoted=true
            case "{","[":depth+=1
            case "}","]":depth-=1; if depth == 0 {
                guard let object=try JSONSerialization.jsonObject(with:Data(html[first...index].utf8)) as? [String:Any] else { throw HongguoError.message("页面数据格式错误") }; return object
            }
            default:break
            }
        }
        throw HongguoError.message("页面数据不完整")
    }
    public static func normalized(_ s:String) -> String {
        s.precomposedStringWithCompatibilityMapping.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }
    public static func search(_ rows:[Series],query:String) -> [Series] {
        let q=normalized(query);guard !q.isEmpty else { return [] }
        func score(_ row:Series)->Int { let title=normalized(row.title); if title == q { return 0 };if title.hasPrefix(q) { return 1 };if title.contains(q) { return 2 };return normalized(row.tags+row.description).contains(q) ? 3:4 }
        var ids=Set<String>()
        return rows.filter { ids.insert($0.id).inserted && score($0)<4 }.enumerated().sorted { let a=score($0.element), b=score($1.element);return a == b ? $0.offset<$1.offset:a<b }.map(\.element)
    }
    static func validID(_ value:String) -> Bool { !value.isEmpty && value.count<=30 && value.utf8.allSatisfy { $0>=48 && $0<=57 } }
    static func card(_ item:[String:Any]) -> Series? {
        let row=item["video_data"] as? [String:Any] ?? item
        let id=row.text("series_id"),title=row.text("series_name",fallback:row.text("series_title",fallback:item.text("name")))
        guard validID(id),!title.isEmpty else { return nil }
        let count=row["episode_cnt"] as? Int ?? (row["series_episode_info"] as? [String:Any])?["episode_cnt"] as? Int ?? 0
        let tags=(row["tags"] as? [Any] ?? row["category_list"] as? [Any] ?? []).prefix(5).compactMap { ($0 as? [String:Any])?.text("name") ?? $0 as? String }.joined(separator:" · ")
        return Series(id:id,title:title,cover:row.text("series_cover"),description:row.text("series_intro"),badge:row.text("episode_right_text",fallback:count>0 ? "全 \(count) 集":""),tags:tags)
    }
}
extension Dictionary where Key == String, Value == Any {
    func text(_ key:String,fallback:String="")->String { let v=self[key];if v == nil || v is NSNull { return fallback };let s=String(describing:v!).trimmingCharacters(in:.whitespacesAndNewlines);return s.isEmpty ? fallback:s }
}
