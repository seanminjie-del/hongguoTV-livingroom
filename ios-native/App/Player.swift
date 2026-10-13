import SwiftUI
import AVKit
import UniformTypeIdentifiers
import HongguoCore
// All mutable loader state is confined to its serial delegate queue.
final class VideoLoader:NSObject,AVAssetResourceLoaderDelegate,@unchecked Sendable {
    private let remote:RemoteStream
    private let total:Int64
    private let queue=DispatchQueue(label:"com.hongguo.resource")
    private var tasks:[ObjectIdentifier:Task<Void,Never>]=[:]
    init(remote:RemoteStream,total:Int64) { self.remote=remote;self.total=total }
    func asset(_ episode:String)->AVURLAsset {
        let asset=AVURLAsset(url:URL(string:"hongguo://episode/\(episode).mp4")!)
        asset.resourceLoader.setDelegate(self,queue:queue);return asset
    }
    func resourceLoader(_ resourceLoader:AVAssetResourceLoader,shouldWaitForLoadingOfRequestedResource request:AVAssetResourceLoadingRequest)->Bool {
        let id=ObjectIdentifier(request),remote=self.remote,total=self.total
        request.contentInformationRequest?.contentType=UTType.mpeg4Movie.identifier
        request.contentInformationRequest?.contentLength=total
        request.contentInformationRequest?.isByteRangeAccessSupported=true
        guard let range=request.dataRequest else { request.finishLoading();return true }
        let start=max(range.requestedOffset,range.currentOffset),requestedEnd=range.requestsAllDataToEndOfResource ? total:min(total,range.requestedOffset+Int64(range.requestedLength))
        guard start>=0,start<=requestedEnd else { request.finishLoading(with:HongguoError.message("播放器读取范围无效"));return true }
        tasks[id]=Task { [weak self] in
            do {
                var offset=start
                while offset<requestedEnd {
                    try Task.checkCancellation()
                    let data=try await remote.read(start:offset,length:Int(min(512*1024,requestedEnd-offset)))
                    guard !data.isEmpty else { throw HongguoError.message("视频数据提前结束") }
                    try Task.checkCancellation()
                    await self?.respond(request,data:data)
                    offset+=Int64(data.count)
                }
                self?.queue.async { [weak self] in if !request.isCancelled { request.finishLoading() };self?.tasks.removeValue(forKey:id) }
            } catch {
                self?.queue.async { [weak self] in if !request.isCancelled { request.finishLoading(with:error) };self?.tasks.removeValue(forKey:id) }
            }
        };return true
    }
    private func respond(_ request:AVAssetResourceLoadingRequest,data:Data) async {
        await withCheckedContinuation { continuation in queue.async { if !request.isCancelled { request.dataRequest?.respond(with:data) };continuation.resume() } }
    }
    func resourceLoader(_ resourceLoader:AVAssetResourceLoader,didCancel request:AVAssetResourceLoadingRequest) { tasks.removeValue(forKey:ObjectIdentifier(request))?.cancel() }
    deinit { tasks.values.forEach { $0.cancel() } }
}
// Audio session calls may block; serialize them away from the UI actor.
actor PlaybackAudio {
    static let shared=PlaybackAudio()
    func activate() throws { let audio=AVAudioSession.sharedInstance();try audio.setCategory(.playback,mode:.moviePlayback);try audio.setActive(true) }
    func deactivate() throws { try AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation) }
}
struct NativePlayer:UIViewControllerRepresentable {
    let player:AVPlayer
    func makeUIViewController(context:Context)->AVPlayerViewController { let vc=AVPlayerViewController();vc.player=player;vc.videoGravity = .resizeAspect;return vc }
    func updateUIViewController(_ vc:AVPlayerViewController,context:Context) { vc.player=player }
}
@MainActor final class PlaybackSession:ObservableObject {
    let detail:Detail
    let player=AVPlayer()
    let store:LibraryStore
    @Published var index:Int
    @Published var loading=true
    @Published var error:String?
    @Published var quality=""
    @Published var seconds=0
    @Published var speed:Float=1
    @Published var autoNext=true
    private var loader:VideoLoader?
    private var loadTask:Task<Void,Never>?
    private var nextTask:Task<Void,Never>?
    private var preload:(Int,StreamInfo,RemoteStream,Int64,Date)?
    private var observer:NSKeyValueObservation?
    private var clock:Any?
    private var endToken:NSObjectProtocol?
    private var generation=0
    init(detail:Detail,index:Int,store:LibraryStore) {
        self.detail=detail;self.index=index;self.store=store
        player.automaticallyWaitsToMinimizeStalling=true
        clock=player.addPeriodicTimeObserver(forInterval:CMTime(seconds:1,preferredTimescale:600),queue:.main) { [weak self] time in
            Task { @MainActor in guard let self,time.seconds.isFinite else { return };self.seconds=max(0,Int(time.seconds));if self.seconds>0,self.seconds%5==0 { self.persist() } }
        }
        endToken=NotificationCenter.default.addObserver(forName:.AVPlayerItemDidPlayToEndTime,object:nil,queue:.main) { [weak self] note in
            Task { @MainActor in guard let self,let item=note.object as? AVPlayerItem,item === self.player.currentItem else { return };self.store.save(self.detail.series,episode:self.index,seconds:0);if self.autoNext,self.index+1<self.detail.episodes.count { self.open(self.index+1,resume:false) } }
        }
    }
    func open(_ index:Int,resume:Bool=true) {
        guard detail.episodes.indices.contains(index) else { return }
        persist();loadTask?.cancel();nextTask?.cancel();player.pause();player.replaceCurrentItem(with:nil);observer=nil;loader=nil
        self.index=index;seconds=0;loading=true;error=nil;generation+=1;let token=generation
        loadTask=Task { [weak self] in
            guard let self else { return }
            do {
                let info:StreamInfo,remote:RemoteStream,total:Int64
                if let cached=preload,cached.0 == index,Date().timeIntervalSince(cached.4)<120 { (info,remote,total)=(cached.1,cached.2,cached.3) }
                else { info=try await store.repository.stream(id:self.detail.episodes[index]);remote=RemoteStream(info:info);total=try await remote.prepare() }
                try Task.checkCancellation();guard self.generation==token else { return };preload=nil
                try await PlaybackAudio.shared.activate();try Task.checkCancellation();guard self.generation==token else { return }
                let loader=VideoLoader(remote:remote,total:total);self.loader=loader;quality=info.quality
                let item=AVPlayerItem(asset:loader.asset(self.detail.episodes[index]));item.preferredForwardBufferDuration=8
                observer=item.observe(\.status,options:[.new,.initial]) { [weak self] item,_ in
                    Task { @MainActor in guard let self,self.self.generation==token else { return };if item.status == .readyToPlay { self.loading=false };if item.status == .failed { self.loading=false;self.error=item.error?.localizedDescription ?? "视频暂不可播放" } }
                }
                player.replaceCurrentItem(with:item)
                if resume,let record=store.history.first(where:{$0.id==self.detail.series.id}),record.episode==index,record.seconds>1 {
                    await player.seek(to:CMTime(seconds:record.seconds,preferredTimescale:600),toleranceBefore:.zero,toleranceAfter:.zero)
                    try Task.checkCancellation();guard self.generation==token else { return }
                }
                player.playImmediately(atRate:speed)
                prepareNext(index+1)
            } catch is CancellationError { } catch { guard self.generation==token else { return };loading=false;self.error=Network.errorText(error) }
        }
    }
    private func prepareNext(_ index:Int) {
        guard detail.episodes.indices.contains(index) else { return }
        nextTask=Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for:.seconds(3));let info=try await store.repository.stream(id:detail.episodes[index]);let remote=RemoteStream(info:info),total=try await remote.prepare()
                try Task.checkCancellation();preload=(index,info,remote,total,Date())
            } catch { /* Optional preloading never interrupts the current episode. */ }
        }
    }
    func setSpeed(_ speed:Float) { self.speed=speed;if player.rate>0 { player.rate=speed } }
    func persist() { if seconds>0 { store.save(detail.series,episode:index,seconds:Double(seconds)) } }
    func suspend() { persist();player.pause();nextTask?.cancel();preload=nil }
    func close() { persist();loadTask?.cancel();nextTask?.cancel();player.pause();player.replaceCurrentItem(with:nil);observer=nil;loader=nil;preload=nil;if let clock { player.removeTimeObserver(clock);self.clock=nil };if let endToken { NotificationCenter.default.removeObserver(endToken);self.endToken=nil };Task { try? await PlaybackAudio.shared.deactivate() } }
}
struct PlayerScreen:View {
    @StateObject var session:PlaybackSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var showEpisodes=false
    var body:some View {
        VStack(spacing:0) {
            HStack { Button { session.close();dismiss() } label:{ Image(systemName:"chevron.down").font(.title3).frame(width:44,height:44) }.accessibilityLabel("关闭播放")
                VStack(alignment:.leading,spacing:4) { Text(session.detail.series.title).font(.headline).lineLimit(1);Text("第 \(session.index+1) 集").font(.subheadline).foregroundStyle(.secondary) };Spacer()
                Menu { ForEach([0.75,1.0,1.25,1.5,2.0],id:\.self) { rate in Button("\(rate.formatted())×") { session.setSpeed(Float(rate)) } } } label:{ Text("\(Double(session.speed).formatted())×").font(.subheadline.bold()).frame(minWidth:44,minHeight:44) }.accessibilityLabel("播放速度")
            }.padding(.horizontal,8)
            ZStack {
                NativePlayer(player:session.player)
                if session.loading { ProgressView("正在准备 \(session.quality)").padding(20).background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:16)) }
                if let error=session.error { VStack(spacing:16) { Image(systemName:"exclamationmark.triangle").font(.largeTitle);Text(error).multilineTextAlignment(.center);Button("重新加载") { session.open(session.index) }.buttonStyle(.borderedProminent) }.padding(24).background(Color.surface,in:RoundedRectangle(cornerRadius:20)) }
            }.frame(maxWidth:.infinity,maxHeight:.infinity).background(.black)
            HStack { Text(session.quality).foregroundStyle(.secondary);Spacer();Text("已播放 \(session.seconds) 秒").accessibilityIdentifier("playback-clock").foregroundStyle(.secondary) }.font(.caption.monospacedDigit()).padding(.horizontal,20).padding(.top,12)
            HStack(spacing:14) {
                Button { showEpisodes=true } label:{ Label("选集",systemImage:"square.grid.3x3").frame(maxWidth:.infinity,minHeight:48) }.buttonStyle(.bordered)
                Button { session.open(session.index+1,resume:false) } label:{ Label("下一集",systemImage:"forward.end.fill").frame(maxWidth:.infinity,minHeight:48) }.buttonStyle(.borderedProminent).disabled(session.index+1>=session.detail.episodes.count)
            }.padding(.horizontal,20).padding(.top,12)
            Toggle("自动连播",isOn:$session.autoNext).font(.subheadline).padding(.horizontal,24).padding(.vertical,12)
        }.background(Color.canvas).preferredColorScheme(.dark).tint(.coral)
        .task { session.open(session.index) }
        .onDisappear { session.close() }
        .onChange(of:phase) { _,value in if value != .active { session.suspend() } }
        .sheet(isPresented:$showEpisodes) { EpisodeSheet(detail:session.detail,current:session.index) { session.open($0,resume:false);showEpisodes=false } }
    }
}
struct EpisodeSheet:View {
    let detail:Detail
    let current:Int
    let select:(Int)->Void
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        NavigationStack { ScrollViewReader { reader in ScrollView { LazyVGrid(columns:Array(repeating:GridItem(.flexible()),count:5),spacing:12) {
            ForEach(detail.episodes.indices,id:\.self) { index in Button { select(index) } label:{ Text("\(index+1)").font(.body.monospacedDigit().bold()).frame(maxWidth:.infinity,minHeight:48).background(index==current ? Color.coral:Color.surface,in:RoundedRectangle(cornerRadius:12)).foregroundStyle(.white) }.id(index) }
        }.padding(20) }.onAppear { reader.scrollTo(current,anchor:.center) } }.background(Color.canvas).navigationTitle("共 \(detail.episodes.count) 集").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement:.topBarTrailing) { Button("完成") { dismiss() } } } }.preferredColorScheme(.dark).tint(.coral)
    }
}
