import SwiftUI
import AVKit
import UniformTypeIdentifiers
import HongguoCore
import Player
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
struct NativePlayer:UIViewRepresentable {
    let player:AVPlayer
    var onReady:(Bool)->Void = { _ in }
    final class Coordinator {
        var observation:NSKeyValueObservation?
        var onReady:(Bool)->Void = { _ in }
    }
    func makeCoordinator()->Coordinator { Coordinator() }
    func makeUIView(context:Context)->PlayerView {
        let view=PlayerView(frame:.zero);view.player=player;view.playerFillMode = .resizeAspect;view.backgroundColor = .black
        context.coordinator.onReady=onReady
        if let layer=view.layer as? AVPlayerLayer {
            context.coordinator.observation=layer.observe(\.isReadyForDisplay,options:[.initial,.new]) { [weak coordinator=context.coordinator] layer,_ in
                let ready=layer.isReadyForDisplay
                Task { @MainActor in coordinator?.onReady(ready) }
            }
        }
        return view
    }
    func updateUIView(_ view:PlayerView,context:Context) { context.coordinator.onReady=onReady;if view.player !== player { view.player=player } }
    static func dismantleUIView(_ view:PlayerView,coordinator:Coordinator) { coordinator.observation=nil;view.player=nil }
}
@MainActor final class EpisodeBuffer {
    let player=AVPlayer()
    let loader:VideoLoader
    let quality:String
    let created=Date()
    init(remote:RemoteStream,total:Int64,episode:String,quality:String) {
        self.quality=quality;loader=VideoLoader(remote:remote,total:total)
        let item=AVPlayerItem(asset:loader.asset(episode));item.preferredForwardBufferDuration=2
        player.isMuted=true;player.automaticallyWaitsToMinimizeStalling=true;player.replaceCurrentItem(with:item)
        player.seek(to:.zero,toleranceBefore:.zero,toleranceAfter:.zero)
    }
}
@MainActor final class PlaybackSession:ObservableObject {
    let detail:Detail
    @Published private(set) var player=AVPlayer()
    @Published private(set) var buffers:[Int:EpisodeBuffer]=[:]
    let store:LibraryStore
    @Published var index:Int
    @Published var loading=true
    @Published var error:String?
    @Published var quality=""
    @Published var seconds=0
    @Published var position:Double=0
    @Published var duration:Double=0
    @Published var playing=false
    @Published var speed:Float=1
    @Published var autoNext=true
    @Published private(set) var silentContinuation=false
    private var loadTask:Task<Void,Never>?
    private var nextTask:Task<Void,Never>?
    private var preparations:[Int:(UUID,Task<EpisodeBuffer,Error>)]=[:]
    private var observer:NSKeyValueObservation?
    private var playbackObserver:NSKeyValueObservation?
    private var clock:Any?
    private var endToken:NSObjectProtocol?
    private var generation=0
    init(detail:Detail,index:Int,store:LibraryStore) {
        self.detail=detail;self.index=index;self.store=store
        endToken=NotificationCenter.default.addObserver(forName:.AVPlayerItemDidPlayToEndTime,object:nil,queue:.main) { [weak self] note in
            Task { @MainActor in guard let self,!self.loading,let item=note.object as? AVPlayerItem,item === self.player.currentItem else { return };self.store.save(self.detail.series,episode:self.index,seconds:0);if self.autoNext,self.index+1<self.detail.episodes.count { self.open(self.index+1,resume:false,silently:true) } }
        }
    }
    private func stopObserving() {
        if let clock { player.removeTimeObserver(clock);self.clock=nil };observer=nil;playbackObserver=nil
    }
    private func attach(_ buffer:EpisodeBuffer,token:Int) {
        stopObserving();player=buffer.player;quality=buffer.quality
        player.currentItem?.preferredForwardBufferDuration=8
        clock=player.addPeriodicTimeObserver(forInterval:CMTime(seconds:1,preferredTimescale:600),queue:.main) { [weak self] time in
            Task { @MainActor in guard let self,self.generation==token,time.seconds.isFinite else { return };self.position=max(0,time.seconds);self.seconds=Int(self.position);let duration=self.player.currentItem?.duration.seconds ?? 0;self.duration=duration.isFinite ? max(0,duration):0;if self.seconds>0,self.seconds%5==0 { self.persist() } }
        }
        playbackObserver=player.observe(\.timeControlStatus,options:[.new,.initial]) { [weak self] player,_ in
            Task { @MainActor in guard let self,self.generation==token else { return };self.playing=player.timeControlStatus == .playing }
        }
        observer=player.currentItem?.observe(\.status,options:[.new,.initial]) { [weak self] item,_ in
            Task { @MainActor in guard let self,self.generation==token else { return };if item.status == .failed { self.loading=false;self.error=item.error?.localizedDescription ?? "视频暂不可播放" } }
        }
    }
    func open(_ index:Int,resume:Bool=true,silently:Bool=false) {
        guard detail.episodes.indices.contains(index) else { return }
        persist();generation+=1;let token=generation
        loadTask?.cancel();nextTask?.cancel();stopObserving();player.pause();player.isMuted=true
        if error != nil { buffers.removeValue(forKey:index) }
        silentContinuation=silently;self.index=index;seconds=0;position=0;duration=0;playing=false;loading=true;error=nil
        trimBuffers()
        loadTask=Task { [weak self] in
            guard let self else { return }
            do {
                let buffer=try await prepare(index)
                try Task.checkCancellation();guard self.generation==token else { return }
                buffers[index]=buffer
                try await PlaybackAudio.shared.activate();try Task.checkCancellation();guard self.generation==token else { return }
                attach(buffer,token:token)
                let record=resume ? store.history.first(where:{$0.id==self.detail.series.id && $0.episode==index}):nil
                let start=record?.seconds ?? 0
                await player.seek(to:CMTime(seconds:start,preferredTimescale:600),toleranceBefore:.zero,toleranceAfter:.zero)
                try Task.checkCancellation();guard self.generation==token else { return }
                if let item=player.currentItem,item.status == .failed { throw item.error ?? HongguoError.message("视频暂不可播放") }
                loading=false;player.isMuted=false;player.playImmediately(atRate:speed)
                prepareNeighbors()
            } catch is CancellationError { } catch { guard self.generation==token else { return };loading=false;self.error=Network.errorText(error) }
        }
    }
    private func prepare(_ index:Int) async throws -> EpisodeBuffer {
        if let buffer=buffers[index],Date().timeIntervalSince(buffer.created)<120,buffer.player.currentItem?.status != .failed { return buffer }
        if let pending=preparations[index] { return try await pending.1.value }
        let id=UUID(),repository=store.repository,episode=detail.episodes[index]
        let task=Task { @MainActor in
            let info=try await repository.stream(id:episode),remote=RemoteStream(info:info),total=try await remote.prepare()
            try Task.checkCancellation()
            return EpisodeBuffer(remote:remote,total:total,episode:episode,quality:info.quality)
        }
        preparations[index]=(id,task)
        defer { if preparations[index]?.0==id { preparations.removeValue(forKey:index) } }
        let buffer=try await task.value
        try Task.checkCancellation()
        if abs(index-self.index)<=1 { buffers[index]=buffer }
        return buffer
    }
    private func trimBuffers() {
        for index in Array(buffers.keys) where abs(index-self.index)>1 {
            let buffer=buffers.removeValue(forKey:index);buffer?.player.pause();buffer?.player.replaceCurrentItem(with:nil)
        }
        for index in Array(preparations.keys) where abs(index-self.index)>1 { preparations.removeValue(forKey:index)?.1.cancel() }
    }
    private func prepareNeighbors() {
        nextTask=Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for:.milliseconds(500))
                for neighbor in [index+1,index-1] where detail.episodes.indices.contains(neighbor) {
                    try Task.checkCancellation()
                    _ = try? await prepare(neighbor)
                }
            } catch { /* Optional preloading never interrupts the current episode. */ }
        }
    }
    func setSpeed(_ speed:Float) { self.speed=speed;if player.rate>0 { player.rate=speed } }
    func togglePlayback() { if player.rate>0 { player.pause() } else { player.playImmediately(atRate:speed) } }
    func seek(to seconds:Double) {
        guard duration>0,!loading else { return }
        let target=max(0,min(seconds,duration)),token=generation
        Task { [weak self] in
            guard let self else { return }
            await player.seek(to:CMTime(seconds:target,preferredTimescale:600),toleranceBefore:.zero,toleranceAfter:.zero)
            guard self.generation==token else { return };let actual=player.currentTime().seconds;if actual.isFinite { position=max(0,actual);self.seconds=Int(position) }
        }
    }
    func persist() { if seconds>0 { store.save(detail.series,episode:index,seconds:Double(seconds)) } }
    func suspend() { persist();player.pause();nextTask?.cancel();preparations.values.forEach { $0.1.cancel() };preparations.removeAll() }
    func close() { persist();generation+=1;loadTask?.cancel();nextTask?.cancel();preparations.values.forEach { $0.1.cancel() };preparations.removeAll();stopObserving();player.pause();player.replaceCurrentItem(with:nil);buffers.values.forEach { $0.player.pause();$0.player.replaceCurrentItem(with:nil) };buffers.removeAll();if let endToken { NotificationCenter.default.removeObserver(endToken);self.endToken=nil };Task { try? await PlaybackAudio.shared.deactivate() } }
}
private struct BufferedVideo:View {
    let buffer:EpisodeBuffer
    @State private var frameReady=false
    var body:some View { NativePlayer(player:buffer.player,onReady:{ frameReady=$0 }).opacity(frameReady ? 1:0) }
}
struct PlayerScreen:View {
    @StateObject var session:PlaybackSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showEpisodes=false
    @State private var showOptions=false
    @State private var controlsVisible=true
    @State private var interaction=0
    @State private var scrubbing=false
    @State private var scrubPosition:Double=0
    @State private var orientationError:String?
    @State private var previousIdleTimer=false
    @State private var progressFrame=CGRect.zero
    @State private var dragOffset:CGFloat=0
    @State private var dragOrigin:Int?
    var body:some View {
        GeometryReader { geometry in
            let landscape=geometry.size.width>geometry.size.height
            let insets=ScreenOrientation.windowScene?.keyWindow?.safeAreaInsets ?? .zero
            ZStack {
                Color.black.ignoresSafeArea()
                ZStack {
                    ForEach(max(0,session.index-1)...min(session.detail.episodes.count-1,session.index+1),id:\.self) { index in
                        ZStack {
                            AsyncImage(url:URL(string:session.detail.series.cover)) { image in
                                image.resizable().scaledToFit()
                            } placeholder:{ Color.surface }
                            if let buffer=session.buffers[index] { BufferedVideo(buffer:buffer).id(ObjectIdentifier(buffer)) }
                        }.frame(width:geometry.size.width,height:geometry.size.height).clipped()
                            .offset(y:CGFloat(index-session.index)*geometry.size.height+dragOffset)
                    }
                }.frame(width:geometry.size.width,height:geometry.size.height).clipped()
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.easeOut(duration:0.2)) { controlsVisible.toggle() } }
                    .accessibilityElement(children:.ignore).accessibilityLabel("全屏播放器，轻点显示或隐藏控制")
                    .accessibilityHint("上滑下一集，下滑上一集")
                    .accessibilityAction(named:Text("下一集")) { changeEpisode(1) }
                    .accessibilityAction(named:Text("上一集")) { changeEpisode(-1) }
                    .accessibilityValue("\(landscape ? "横屏":"竖屏") · 第 \(session.index+1) 集 · 已播放 \(session.seconds) 秒")
                    .accessibilityAddTraits(.isButton).accessibilityIdentifier("video-surface")
                if controlsVisible {
                    VStack {
                        topControls(landscape:landscape)
                        Spacer(minLength:12)
                        HStack(spacing:40) {
                            Button { interaction+=1;session.seek(to:session.position-15) } label:{ Image(systemName:"gobackward.15").font(.title).frame(width:52,height:52) }.accessibilityLabel("后退15秒")
                            Button { session.togglePlayback() } label:{ Image(systemName:session.playing ? "pause.fill":"play.fill").font(.largeTitle).frame(width:64,height:64) }.accessibilityLabel(session.playing ? "暂停":"播放")
                            Button { interaction+=1;session.seek(to:session.position+15) } label:{ Image(systemName:"goforward.15").font(.title).frame(width:52,height:52) }.accessibilityLabel("快进15秒")
                        }.foregroundStyle(.white).shadow(radius:4)
                        Spacer(minLength:12)
                        bottomControls(landscape:landscape)
                    }.padding(.horizontal,landscape ? 20:12).padding(.leading,insets.left).padding(.trailing,insets.right).padding(.top,insets.top+8).padding(.bottom,insets.bottom+8)
                        .background(LinearGradient(colors:[.black.opacity(0.7),.clear,.black.opacity(0.8)],startPoint:.top,endPoint:.bottom))
                        .opacity(dragOrigin==nil ? 1:0)
                        .transition(.opacity)
                }
                if session.loading,!session.silentContinuation { ProgressView("正在准备 \(session.quality)").padding(20).background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:16)) }
                if let error=session.error,!session.silentContinuation { VStack(spacing:16) { Image(systemName:"exclamationmark.triangle").font(.largeTitle);Text(error).multilineTextAlignment(.center);Button("重新加载") { session.open(session.index) }.buttonStyle(.borderedProminent) }.padding(24).background(Color.surface,in:RoundedRectangle(cornerRadius:20)) }
            }.frame(maxWidth:.infinity,maxHeight:.infinity).coordinateSpace(name:"player")
                .simultaneousGesture(DragGesture(minimumDistance:30,coordinateSpace:.named("player")).onChanged { value in
                    let vertical=value.translation.height,horizontal=value.translation.width
                    guard acceptsSwipe(from:value.startLocation),abs(vertical)>abs(horizontal)*1.5 else { return }
                    if dragOrigin==nil { dragOrigin=session.index }
                    let target=session.index+(vertical<0 ? 1:-1)
                    dragOffset=session.detail.episodes.indices.contains(target) ? max(-geometry.size.height,min(geometry.size.height,vertical)):vertical*0.18
                }.onEnded { value in
                    let vertical=value.translation.height,horizontal=value.translation.width
                    let commit=dragOrigin==session.index && abs(vertical)>=80 && abs(vertical)>abs(horizontal)*1.5
                    dragOrigin=nil
                    withAnimation(reduceMotion ? nil:.spring(response:0.32,dampingFraction:0.9)) {
                        dragOffset=0
                        if commit { changeEpisode(vertical<0 ? 1:-1) }
                    }
                })
                .onChange(of:geometry.size) { _,_ in dragOffset=0;dragOrigin=nil;controlsVisible=true;interaction+=1 }
        }.ignoresSafeArea().background(.black).preferredColorScheme(.dark).tint(.coral)
        .statusBarHidden(true).persistentSystemOverlays(.hidden)
        .onAppear { previousIdleTimer=UIApplication.shared.isIdleTimerDisabled;UIApplication.shared.isIdleTimerDisabled=true;ScreenOrientation.select(.portrait) { orientationError=$0 } }
        .task { session.open(session.index) }
        .task(id:"\(controlsVisible)|\(session.playing)|\(session.loading)|\(scrubbing)|\(showEpisodes)|\(showOptions)|\(interaction)|\(dragOrigin != nil)") {
            guard controlsVisible,session.playing,!session.loading,session.error==nil,!scrubbing,!showEpisodes,!showOptions,!voiceOver,dragOrigin==nil else { return }
            do { try await Task.sleep(for:.seconds(4));try Task.checkCancellation();withAnimation(.easeOut(duration:0.2)) { controlsVisible=false } } catch { }
        }
        .onChange(of:session.index) { _,_ in controlsVisible = !session.silentContinuation;scrubbing=false }
        .onDisappear { session.close();UIApplication.shared.isIdleTimerDisabled=previousIdleTimer;ScreenOrientation.select(.portrait) { _ in } }
        .onChange(of:phase) { _,value in if value != .active { dragOffset=0;dragOrigin=nil;session.suspend();controlsVisible=true } }
        .sheet(isPresented:$showEpisodes) { EpisodeSheet(detail:session.detail,current:session.index) { session.open($0,resume:false);showEpisodes=false } }
        .confirmationDialog("播放设置",isPresented:$showOptions,titleVisibility:.visible) {
            ForEach([0.75,1.0,1.25,1.5,2.0],id:\.self) { rate in Button("\(rate.formatted())×") { session.setSpeed(Float(rate)) } }
            Button(session.autoNext ? "关闭自动连播":"开启自动连播") { session.autoNext.toggle() }
        }
        .alert("无法切换屏幕方向",isPresented:Binding(get:{ orientationError != nil },set:{ if !$0 { orientationError=nil } })) { Button("确定") { orientationError=nil } } message:{ Text(orientationError ?? "") }
    }
    private func changeEpisode(_ offset:Int) {
        guard !scrubbing,!showEpisodes,!showOptions else { return }
        session.open(session.index+offset,resume:false,silently:true)
    }
    private func acceptsSwipe(from point:CGPoint)->Bool {
        !scrubbing && !showEpisodes && !showOptions && !(controlsVisible && progressFrame.insetBy(dx:-12,dy:-12).contains(point))
    }
    private func topControls(landscape:Bool)->some View {
        HStack(spacing:12) {
            Button { ScreenOrientation.select(.portrait) { _ in };session.close();dismiss() } label:{ Image(systemName:"chevron.down").font(.title3).frame(width:44,height:44) }.accessibilityLabel("关闭播放")
            VStack(alignment:.leading,spacing:4) { Text(session.detail.series.title).font(.headline).lineLimit(1);Text("第 \(session.index+1) 集").font(.subheadline).foregroundStyle(.white.opacity(0.8)) }
            Spacer(minLength:0)
            Button { interaction+=1;ScreenOrientation.select(landscape ? .portrait:.landscape) { orientationError=$0 } } label:{ Label(landscape ? "竖屏":"横屏",systemImage:"rotate.right").font(.subheadline.bold()).frame(minWidth:60,minHeight:44) }.accessibilityLabel(landscape ? "竖屏":"横屏")
        }.foregroundStyle(.white)
    }
    private func bottomControls(landscape:Bool)->some View {
        VStack(spacing:10) {
            if session.silentContinuation,session.loading || session.error != nil {
                HStack {
                    Text(session.loading ? "正在加载剧集":session.error ?? "").lineLimit(2)
                    if session.error != nil { Button("重试") { session.open(session.index,resume:false,silently:true) } }
                }.font(.caption).foregroundStyle(.white.opacity(0.8))
            }
            HStack { Text(session.quality);Spacer();Text("已播放 \(session.seconds) 秒").accessibilityIdentifier("playback-clock") }.font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.8))
            HStack(spacing:10) {
                Text(time(scrubbing ? scrubPosition:session.position))
                Slider(value:Binding(get:{ scrubbing ? scrubPosition:session.position },set:{ scrubPosition=$0;if !scrubbing { session.seek(to:$0) } }),in:0...max(session.duration,1)) { editing in
                    scrubbing=editing;if !editing { session.seek(to:scrubPosition) }
                }.disabled(session.duration<=0 || session.loading).accessibilityLabel("播放进度")
                    .onGeometryChange(for:CGRect.self) { $0.frame(in:.named("player")) } action:{ progressFrame=$0 }
                Text(time(session.duration)).accessibilityIdentifier("playback-duration")
            }.font(.caption.monospacedDigit()).foregroundStyle(.white)
            HStack(spacing:14) {
                Button { showEpisodes=true } label:{ Label("选集",systemImage:"square.grid.3x3").frame(minWidth:70,minHeight:44) }
                Spacer()
                Button { showOptions=true } label:{ Text("\(Double(session.speed).formatted())×").frame(minWidth:50,minHeight:44) }.accessibilityLabel("播放设置")
                Button { session.open(session.index+1,resume:false) } label:{ Label("下一集",systemImage:"forward.end.fill").frame(minWidth:80,minHeight:44) }.disabled(session.index+1>=session.detail.episodes.count)
            }.font(.subheadline.bold()).foregroundStyle(.white)
        }
    }
    private func time(_ seconds:Double)->String { let value=seconds.isFinite ? max(0,Int(seconds)):0;return String(format:"%02d:%02d",value/60,value%60) }
}
struct EpisodeSheet:View {
    let detail:Detail
    let current:Int
    let select:(Int)->Void
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        NavigationStack { ScrollViewReader { reader in ScrollView { LazyVGrid(columns:Array(repeating:GridItem(.flexible()),count:5),spacing:12) {
            ForEach(detail.episodes.indices,id:\.self) { index in Button { select(index) } label:{ Text("\(index+1)").font(.body.monospacedDigit().bold()).frame(maxWidth:.infinity,minHeight:48).background(index==current ? Color.coral:Color.surface,in:RoundedRectangle(cornerRadius:12)).foregroundStyle(.white) }.id(index).accessibilityIdentifier("episode-option-\(index)") }
        }.padding(20) }.onAppear { reader.scrollTo(current,anchor:.center) } }.background(Color.canvas).navigationTitle("共 \(detail.episodes.count) 集").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement:.topBarTrailing) { Button("完成") { dismiss() } } } }.preferredColorScheme(.dark).tint(.coral)
    }
}
