import SwiftUI
import HongguoCore
struct WatchRecord:Codable,Identifiable { var series:Series;var episode:Int;var seconds:Double;var date:Date;var id:String { series.id } }
@MainActor final class LibraryStore:ObservableObject {
    let repository=Repository()
    @Published var favorites:[Series]
    @Published var history:[WatchRecord]
    private let defaults=UserDefaults.standard
    init() {
        favorites=(try? JSONDecoder().decode([Series].self,from:UserDefaults.standard.data(forKey:"hongguo.favorites") ?? Data())) ?? []
        history=(try? JSONDecoder().decode([WatchRecord].self,from:UserDefaults.standard.data(forKey:"hongguo.history") ?? Data())) ?? []
    }
    func favorite(_ series:Series) {
        if favorites.contains(where:{$0.id==series.id}) { favorites.removeAll { $0.id==series.id } } else { favorites.insert(series,at:0) }
        defaults.set(try? JSONEncoder().encode(favorites),forKey:"hongguo.favorites")
    }
    func save(_ series:Series,episode:Int,seconds:Double) {
        guard seconds.isFinite,seconds>=0 else { return }
        history.removeAll { $0.id == series.id };history.insert(WatchRecord(series:series,episode:episode,seconds:seconds,date:Date()),at:0)
        history=Array(history.prefix(100));defaults.set(try? JSONEncoder().encode(history),forKey:"hongguo.history")
    }
}
extension Color {
    static let coral=Color(red:1,green:0.39,blue:0.34)
    static let canvas=Color(red:0.055,green:0.063,blue:0.078)
    static let surface=Color(red:0.105,green:0.118,blue:0.137)
}
