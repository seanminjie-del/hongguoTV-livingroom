# 红果剧场 iOS

独立的 iPhone 原生客户端，最低 iOS 17。沿用红果 TV 的深灰与珊瑚色、题材频道和真实海报，使用 SwiftUI 与 AVFoundation，手机无需运行电脑端桥接服务。

## 功能

- 短剧 / 漫剧片库、题材频道、分页、下拉刷新。
- 剧名和题材搜索：读取当前官网公开片库全部分页，去重，按完整剧名、剧名开头、剧名包含、题材 / 简介排序；显示实际索引数量。这里的“完整”指官网当前公开片库，不能代表平台全部内容。
- 剧集详情、分集选择、收藏、观看记录、断点续播。
- 开源 Player 视频视图 + 系统 AVPlayer：默认全屏、横竖屏按钮、自动隐藏控制浮层、暂停、拖动进度、前后 15 秒、倍速、下一集、自动连播。预备当前集及前后相邻集的播放器与首帧，缓存范围限制为三集；超过两分钟重新取址。退到后台暂停，退出时释放资源。
- 播放画面上滑下一集、下滑上一集，画面跟手移动、松手吸附，首尾集带阻尼回弹，横竖屏均可用。未就绪的页面保留真实封面，视频图层首帧可显示后再揭开封面，切集保持静默。从进度条开始的拖动、横向拖动和短距离拖动不会切集；VoiceOver 提供上一集 / 下一集操作，开启减少动态效果时取消松手动画。
- 内容与媒体 GET 遇到临时 HTTP / 传输故障时短退避恢复，最多三次请求，可取消；签名 POST、明确证书拒绝和数据校验失败不在请求层反复尝试。
- 使用与 Android 当前版本相同的**最新访客签名播放接口**；当前接口来源与已知边界见 [上级说明](../README.md)。上游接口拒绝、网络异常与不可用片源会明确报错，预加载失败不会中断当前播放。

## 工程

`HongguoMobile.xcodeproj` 是新增 iPhone 工程。原仓库 `../ios/` 是 React Native tvOS 工程，保留原样。

播放器方案与第三方来源见 [选择记录](PLAYER_SELECTION.md)。
1.1.0 全屏与横竖屏的实际验证及安装记录见 [升级记录](RELEASE_1.1.0.md)。
1.1.1 自动连播采用静默切集：不主动显示控制栏、加载窗口或错误弹层；需要查看加载状态或重试时，轻点画面打开控制栏。构建、旧版失败对照与已通过的真机自然连播回归见 [静默连播记录](RELEASE_1.1.1.md)。
1.1.2 增加上下滑动切集，验证及安装记录见 [滑动切集记录](RELEASE_1.1.2.md)。
1.1.3 对照上游 v1.73 补充请求恢复，修正控制栏可见时滑动中断；本地测试及开发 IPA 说明见 [本轮记录](RELEASE_1.1.3.md)。

`Sources/HongguoCore` 是本地 Swift Package，可在 macOS 跑测试。仅使用系统 Foundation、CommonCrypto、JavaScriptCore；签名 JavaScript 是本地打包的固定代码，不下载或执行远端代码。视频分段读取有响应大小、Content-Range 与索引边界校验，并按 MP4 样本 / 子样本进行 AES-CTR 解密，保留 AVC / HEVC 原始编码。

## 构建和安装

用 Xcode 打开工程，选择自己的开发团队、连接并解锁 iPhone，然后运行 `HongguoMobile` scheme。也可以用命令行：

```sh
swift test --package-path ios-native
HONGGUO_LIVE=1 swift test --package-path ios-native
xcodebuild -project ios-native/HongguoMobile.xcodeproj -scheme HongguoMobile \
  -destination 'id=<IPHONE_UDID>' -derivedDataPath /tmp/hongguo-ios \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM=<YOUR_TEAM> build
xcrun devicectl device install app --device '<IPHONE_UDID>' \
  /tmp/hongguo-ios/Build/Products/Debug-iphoneos/HongguoMobile.app
```

真机 UI 测试（需要解锁并保持亮屏）：

```sh
xcodebuild -project ios-native/HongguoMobile.xcodeproj -scheme HongguoMobile \
  -destination 'id=<IPHONE_UDID>' -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=<YOUR_TEAM> test
```

开发签名安装受所用证书与 provisioning profile 的有效期约束。开发 IPA 仅给已登记设备使用，包含设备信息，不放到公开 Releases。本版未发布到 App Store / TestFlight；iOS 不使用 Android APK 自动更新渠道。

## 许可

沿用仓库 GPL-3.0-only。`Resources/signing.js` 改编自 `server/vendor/hongguo.cjs`；访客标识、会话 nonce 与启动时间对齐当前 Kotlin 实现。独立签名 oracle fixture、SM3 标准向量、NIST CTR 向量与 MP4 边界测试随源码提供。
