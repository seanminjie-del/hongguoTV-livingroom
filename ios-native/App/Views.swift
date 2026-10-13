import SwiftUI
import HongguoCore
struct RootView:View {
    @StateObject private var store=LibraryStore()
    var body:some View {
        TabView {
            NavigationStack { BrowseView() }.tabItem { Label("发现",systemImage:"rectangle.stack.fill") }
            NavigationStack { SearchView() }.tabItem { Label("搜索",systemImage:"magnifyingglass") }
            NavigationStack { CollectionView() }.tabItem { Label("我的",systemImage:"person.crop.circle") }
        }.environmentObject(store).tint(.coral).preferredColorScheme(.dark)
    }
}
struct Poster:View {
    let series:Series
    @ScaledMetric(relativeTo:.subheadline) private var titleHeight=42
    @ScaledMetric(relativeTo:.caption) private var tagsHeight=18
    var body:some View {
        VStack(alignment:.leading,spacing:9) {
            Color.surface.aspectRatio(0.70,contentMode:.fit)
                .overlay {
                    GeometryReader { bounds in
                        AsyncImage(url:URL(string:series.cover)) { image in image.resizable().scaledToFill() } placeholder:{ Image(systemName:"film.stack").font(.largeTitle).foregroundStyle(.secondary).frame(maxWidth:.infinity,maxHeight:.infinity) }
                            .frame(width:bounds.size.width,height:bounds.size.height).clipped()
                    }
                }
                .overlay(alignment:.bottomLeading) {
                    ZStack(alignment:.bottomLeading) {
                        LinearGradient(colors:[.clear,.black.opacity(0.8)],startPoint:.center,endPoint:.bottom)
                        if !series.badge.isEmpty { Text(series.badge).font(.caption.weight(.medium)).foregroundStyle(.white).padding(10) }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius:14))
            Text(series.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(2).frame(maxWidth:.infinity,alignment:.leading).frame(height:titleHeight,alignment:.topLeading)
            Text(series.tags).font(.caption).foregroundStyle(.secondary).lineLimit(1).frame(height:tagsHeight,alignment:.topLeading)
        }.frame(maxWidth:.infinity,alignment:.topLeading)
    }
}
struct PosterGrid:View {
    let items:[Series]
    var search=false
    var body:some View {
        LazyVGrid(columns:[GridItem(.flexible(),spacing:14,alignment:.top),GridItem(.flexible(),spacing:14,alignment:.top)],alignment:.leading,spacing:24) {
            ForEach(Array(items.enumerated()),id:\.element.id) { index,series in
                NavigationLink { DetailView(series:series) } label:{ Poster(series:series) }.buttonStyle(.plain).accessibilityIdentifier(search ? "search-poster":index==0 ? "poster-first":"poster-\(series.id)")
            }
        }
    }
}
struct Problem:View {
    let text:String
    let retry:()->Void
    var body:some View { VStack(spacing:16) { Image(systemName:"wifi.exclamationmark").font(.largeTitle).foregroundStyle(.secondary);Text(text).multilineTextAlignment(.center);Button("重试",action:retry).buttonStyle(.borderedProminent) }.frame(maxWidth:.infinity).padding(.vertical,40) }
}
struct BrowseView:View {
    @EnvironmentObject private var store:LibraryStore
    @State private var kind:ContentKind = .short
    @State private var channel="全部"
    @State private var items=[Series]()
    @State private var loading=false
    @State private var error:String?
    @State private var page=0
    @State private var more=false
    @State private var indexed=0
    @State private var reload=0
    private let channels=["全部","甜宠","重生","逆袭","古代","悬疑","穿越"]
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                HStack(alignment:.firstTextBaseline) { Text("红果").font(.largeTitle.bold());Text("剧场").font(.largeTitle.weight(.light)).foregroundStyle(.secondary);Spacer();Image(systemName:"play.rectangle.on.rectangle.fill").font(.title2).foregroundStyle(Color.coral) }.padding(.top,8)
                Picker("内容类型",selection:$kind) { ForEach(ContentKind.allCases) { Text($0.label).tag($0) } }.pickerStyle(.segmented).accessibilityIdentifier("kind-picker")
                ScrollView(.horizontal,showsIndicators:false) { HStack(spacing:10) { ForEach(channels,id:\.self) { value in Button { channel=value } label:{ Text(value).font(.subheadline.weight(.semibold)).padding(.horizontal,19).frame(minHeight:44).background(channel==value ? Color.coral:Color.surface,in:Capsule()).foregroundStyle(.white) }.buttonStyle(.plain) } } }.contentMargins(.trailing,8)
                if channel == "全部",let latest=store.history.first {
                    NavigationLink { DetailView(series:latest.series) } label:{ HStack(spacing:14) { AsyncImage(url:URL(string:latest.series.cover)) { $0.resizable().scaledToFill() } placeholder:{ Color.surface }.frame(width:48,height:65).clipped().clipShape(RoundedRectangle(cornerRadius:8));VStack(alignment:.leading,spacing:6) { Text("继续观看").font(.caption).foregroundStyle(Color.coral);Text(latest.series.title).font(.subheadline.bold()).lineLimit(1);Text("第 \(latest.episode+1) 集 · \(Int(latest.seconds)) 秒").font(.caption).foregroundStyle(.secondary) };Spacer();Image(systemName:"play.circle.fill").font(.title).foregroundStyle(Color.coral) }.padding(14).background(Color.surface,in:RoundedRectangle(cornerRadius:16)) }.buttonStyle(.plain)
                }
                HStack { Text(channel == "全部" ? "正在热播":"\(channel)频道").font(.title2.bold());Spacer();if !items.isEmpty { Text("\(items.count) 部").font(.caption).foregroundStyle(.secondary) } }
                if loading,items.isEmpty { ProgressView(indexed>0 ? "正在检索片库 · \(indexed) 部":"正在加载片库").frame(maxWidth:.infinity).padding(.vertical,70) }
                PosterGrid(items:items)
                if let error { Problem(text:error) { reload+=1 } }
                if !loading,error==nil,items.isEmpty { ContentUnavailableView("这个题材暂时没有结果",systemImage:"film.stack",description:Text("试试其他题材或到搜索页输入完整剧名。")) }
                if more,channel=="全部" { Button { Task { await loadMore() } } label:{ HStack { if loading { ProgressView() };Text(loading ? "加载中…":"加载更多").frame(maxWidth:.infinity,minHeight:44) } }.buttonStyle(.bordered).disabled(loading) }
                if indexed>0,!loading { Text("官网片库 · 已检索 \(indexed) 部").font(.caption).foregroundStyle(.secondary) }
            }.padding(.horizontal,20).padding(.bottom,30)
        }.background(Color.canvas).toolbar(.hidden,for:.navigationBar)
        .task(id:"\(kind.rawValue)|\(channel)|\(reload)") { await load() }
        .refreshable { await load() }
    }
    private func load() async {
        loading=true;error=nil;items=[];page=0;indexed=0;more=false
        let selectedKind=kind,selectedChannel=channel
        do {
            if selectedChannel == "全部" {
                let first=try await store.repository.home(kind:selectedKind);try Task.checkCancellation();items=first.items;page=1;more=first.hasMore
                if more { let next=try await store.repository.home(page:2,kind:selectedKind);try Task.checkCancellation();append(next.items);page=2;more=next.hasMore }
            } else {
                let result=try await store.repository.search(query:selectedChannel,kind:selectedKind) { count in await MainActor.run { indexed=count } };try Task.checkCancellation();items=result.items;indexed=result.indexed
            }
        } catch is CancellationError { return } catch { if !Task.isCancelled { self.error=Network.errorText(error) } }
        loading=false
    }
    private func append(_ rows:[Series]) { let ids=Set(items.map(\.id));items+=rows.filter { !ids.contains($0.id) } }
    private func loadMore() async {
        guard !loading,more else { return };loading=true
        let type=kind,oldPage=page
        do { let next=try await store.repository.home(page:oldPage+1,kind:type);try Task.checkCancellation();guard kind==type,channel=="全部",page==oldPage else { return };append(next.items);page+=1;more=next.hasMore;error=nil } catch { guard kind==type,channel=="全部" else { return };self.error=Network.errorText(error) };loading=false
    }
}
struct SearchView:View {
    @EnvironmentObject private var store:LibraryStore
    @State private var query=""
    @State private var kind:ContentKind = .short
    @State private var results=[Series]()
    @State private var indexed=0
    @State private var loading=false
    @State private var searched=false
    @State private var error:String?
    @State private var work:Task<Void,Never>?
    @FocusState private var focused:Bool
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                HStack { Image(systemName:"magnifyingglass").foregroundStyle(.secondary);TextField("输入剧名或题材",text:$query).focused($focused).submitLabel(.search).autocorrectionDisabled().onSubmit(search);if !query.isEmpty { Button { query="";work?.cancel();results=[];searched=false;loading=false } label:{ Image(systemName:"xmark.circle.fill").foregroundStyle(.secondary) }.accessibilityLabel("清空搜索") } }.padding(14).background(Color.surface,in:RoundedRectangle(cornerRadius:14))
                Picker("内容类型",selection:$kind) { ForEach(ContentKind.allCases) { Text($0.label).tag($0) } }.pickerStyle(.segmented).onChange(of:kind) { _,_ in if searched { search() } }
                if loading { VStack(alignment:.leading,spacing:12) { ProgressView("正在建立完整片库索引");Text("已读取 \(indexed) 部，剧名优先匹配。").font(.caption).foregroundStyle(.secondary) }.padding(.vertical,20) }
                if searched,!loading,error==nil {
                    Text("官网片库 · 找到 \(results.count) 部\(kind.label)").font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("search-summary")
                    if results.isEmpty { ContentUnavailableView.search(text:query) }
                }
                if let error { Problem(text:error,retry:search) }
                PosterGrid(items:results,search:true)
                if searched,!loading,error==nil { Text("搜索范围：官网当前公开片库，共 \(indexed) 部。").font(.caption).foregroundStyle(.secondary) }
                if !searched { VStack(alignment:.leading,spacing:16) { Text("想看什么故事？").font(.title2.bold());Text("输入完整剧名更准确，也可以从题材开始。首次搜索会读取当前官网片库，结果不会只来自首页。").font(.subheadline).foregroundStyle(.secondary);HStack { ForEach(["重生","甜宠","穿越"],id:\.self) { word in Button(word) { query=word;search() }.buttonStyle(.bordered) } } }.padding(.top,20) }
            }.padding(20)
        }.background(Color.canvas).navigationTitle("搜索").navigationBarTitleDisplayMode(.inline).onDisappear { focused=false;work?.cancel();loading=false }
    }
    private func search() {
        guard !query.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { return }
        focused=false;work?.cancel();loading=true;searched=true;error=nil;results=[];indexed=0
        let text=query,type=kind
        work=Task {
            do { let result=try await store.repository.search(query:text,kind:type) { count in await MainActor.run { indexed=count } };try Task.checkCancellation();results=result.items;indexed=result.indexed }
            catch is CancellationError { return } catch { if !Task.isCancelled { self.error=Network.errorText(error) } };loading=false
        }
    }
}
struct DetailView:View {
    let series:Series
    @EnvironmentObject private var store:LibraryStore
    @State private var detail:Detail?
    @State private var error:String?
    @State private var showingPlayer=false
    @State private var selection=0
    @State private var showEpisodes=false
    @State private var playAfterSheet=false
    @State private var reload=0
    var body:some View {
        ScrollView { VStack(alignment:.leading,spacing:22) {
            HStack(alignment:.top,spacing:20) { AsyncImage(url:URL(string:series.cover)) { $0.resizable().scaledToFill() } placeholder:{ Color.surface }.frame(width:130,height:184).clipped().clipShape(RoundedRectangle(cornerRadius:16));VStack(alignment:.leading,spacing:14) { Text(series.title).font(.title2.bold()).accessibilityIdentifier("detail-title");Text(series.badge).font(.subheadline).foregroundStyle(.secondary);Text(series.tags).font(.caption).foregroundStyle(Color.coral);Button { store.favorite(series) } label:{ Label(store.favorites.contains(where:{$0.id==series.id}) ? "已收藏":"收藏",systemImage:store.favorites.contains(where:{$0.id==series.id}) ? "heart.fill":"heart") }.buttonStyle(.bordered) } }
            if let detail {
                Button { if let record=store.history.first(where:{$0.id==series.id}),detail.episodes.indices.contains(record.episode) { selection=record.episode };showingPlayer=true } label:{ Label("开始观看",systemImage:"play.fill").font(.headline).frame(maxWidth:.infinity,minHeight:50) }.buttonStyle(.borderedProminent)
                if let record=store.history.first(where:{$0.id==series.id}) { Text("上次看到第 \(record.episode+1) 集 · \(Int(record.seconds)) 秒，将从这里继续。").font(.caption).foregroundStyle(.secondary) }
                HStack { Text("选集").font(.title3.bold());Spacer();Button("共 \(detail.episodes.count) 集 ›") { showEpisodes=true } }
                ScrollView(.horizontal,showsIndicators:false) { HStack(spacing:12) { ForEach(Array(detail.episodes.indices.prefix(12)),id:\.self) { index in Button { selection=index;showingPlayer=true } label:{ Text("\(index+1)").font(.body.monospacedDigit().bold()).frame(width:48,height:48).background(Color.surface,in:RoundedRectangle(cornerRadius:12)) }.accessibilityIdentifier("detail-episode-\(index)") } } }
            } else if let error { Problem(text:error) { reload+=1 } } else { ProgressView("正在加载分集").frame(maxWidth:.infinity).padding() }
            Text("剧情简介").font(.title3.bold());Text((detail?.series.description ?? series.description).isEmpty ? "暂无简介":detail?.series.description ?? series.description).font(.body).foregroundStyle(.secondary).lineSpacing(6)
        }.padding(20) }.background(Color.canvas).navigationTitle("剧集详情").navigationBarTitleDisplayMode(.inline)
        .task(id:reload) { do { detail=try await store.repository.detail(id:series.id) } catch is CancellationError { } catch { self.error=Network.errorText(error) } }
        .fullScreenCover(isPresented:$showingPlayer) { if let detail { PlayerScreen(session:PlaybackSession(detail:detail,index:selection,store:store)) } }
        .sheet(isPresented:$showEpisodes,onDismiss:{ if playAfterSheet { playAfterSheet=false;showingPlayer=true } }) { if let detail { EpisodeSheet(detail:detail,current:selection) { selection=$0;playAfterSheet=true;showEpisodes=false } } }
    }
}
struct CollectionView:View {
    @EnvironmentObject private var store:LibraryStore
    var body:some View {
        ScrollView { VStack(alignment:.leading,spacing:24) {
            Text("最近观看").font(.title2.bold())
            if store.history.isEmpty { Text("看过的故事会保存在这里，方便下次接着看。").foregroundStyle(.secondary) }
            ForEach(store.history) { record in NavigationLink { DetailView(series:record.series) } label:{ HStack(spacing:14) { AsyncImage(url:URL(string:record.series.cover)) { $0.resizable().scaledToFill() } placeholder:{ Color.surface }.frame(width:58,height:80).clipped().clipShape(RoundedRectangle(cornerRadius:8));VStack(alignment:.leading,spacing:8) { Text(record.series.title).font(.headline).lineLimit(2);Text("第 \(record.episode+1) 集 · \(Int(record.seconds)) 秒").font(.caption).foregroundStyle(.secondary) };Spacer();Image(systemName:"play.circle").foregroundStyle(Color.coral).font(.title2) }.padding(12).background(Color.surface,in:RoundedRectangle(cornerRadius:14)) }.buttonStyle(.plain) }
            Text("我的收藏").font(.title2.bold())
            if store.favorites.isEmpty { Text("在剧集详情点收藏，把想看的故事留下来。").foregroundStyle(.secondary) }
            PosterGrid(items:store.favorites)
            Text("红果剧场 iOS 1.1 · 全屏播放器\n内容来自当前官网片库与最新播放接口。搜索范围随官网公开片库更新。").font(.caption).foregroundStyle(.secondary).padding(.top,20)
        }.padding(20) }.background(Color.canvas).navigationTitle("我的")
    }
}
