# iOS 播放器选择与接入

2026-10-14 对比上游源码和构建清单，选择 [piemonte/Player](https://github.com/piemonte/Player)，固定提交 `fb901038bbf9ea2f92a39541e90a2fd6eac1ed9b`。

| 方案 | 观察到的实现 | 本项目适配判断 |
| --- | --- | --- |
| piemonte/Player | MIT，纯 Swift，SPM，无额外依赖；公开 `PlayerView.player` 可接现有 AVPlayer | 采用其实际视频显示视图，兼容当前自定义 AVAssetResourceLoader、解密和预取资源 |
| ZFPlayer | MIT，Objective-C；AVPlayer 管理器的 player / asset 只读，控制层可定制 | 完整接入需要额外桥接与播放管理适配，本次不采用 |
| KSPlayer | 当前清单含二进制 KSPlayer.xcframework；UI 依赖 FFmpegKit，提供多解码方案 | 功能更广，本项目当前的 AVC / HEVC 解密资源可由系统解码，暂不引入其二进制链 |

采用的是 Player 的开源视频视图；媒体取址、CENC 解密、AVPlayer 实例、续播和下一集仍由已验证的 `PlaybackSession` / `RemoteStream` 管理。没有创建第二个播放实例，也没有绕过现有网络、解密和错误校验。

## 1.1.0 播放体验

- 点击分集默认进入占满整个屏幕的视频画布，保持原片比例。
- 标题、暂停、进度、选集和下一集都是浮层；播放中无操作四秒后隐藏，轻点画面再次显示。
- 明确的“横屏 / 竖屏”按钮通过 iOS 公共 UIWindowScene 几何接口切换，退出播放器恢复竖屏。
- 进度拖动、前后 15 秒、倍速和自动连播设置保留在浮层。
- 播放页面保持屏幕亮起，退出恢复之前的自动休眠行为。VoiceOver 启用时不自动隐藏控件。
- MIT 许可原文随应用打包为 `App/Resources/Player-LICENSE.txt`；整个客户端继续采用仓库 GPL-3.0-only。
