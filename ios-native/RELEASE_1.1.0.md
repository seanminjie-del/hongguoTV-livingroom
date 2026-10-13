# iOS 1.1.0 播放器升级

2026-10-14，版本 1.1.0 / build 2。实体 iPhone 16 Pro Max，iOS 27.2，Xcode 27.0。最低构建目标仍为 iOS 17。

## 变化与来源

默认进入全屏播放，标题、播放控制、进度与选集改为浮层；轻点画面显示或隐藏控件，正常播放无操作四秒后隐藏。新增明确的横屏 / 竖屏按钮，切换时沿用同一个 AVPlayer，退出恢复竖屏；播放页保持屏幕亮起，退出恢复此前的休眠设置。

采用 MIT 开源 [piemonte/Player](https://github.com/piemonte/Player) 的 `PlayerView`，固定提交 `fb901038bbf9ea2f92a39541e90a2fd6eac1ed9b`，许可原文随应用打包。方案比较见 [PLAYER_SELECTION.md](PLAYER_SELECTION.md)。媒体取址、CENC 解密、AVPlayer 生命周期、续播和预取继续使用现有实现；没有替换成第二个播放引擎。

保留深灰 / 珊瑚色体系，视频按原片比例显示。横屏播放竖向片源时，两侧黑边用于保持画面完整。标题、退出与方向切换放在上方安全区，进度、倍速、选集与下一集放在下方。控制浮层采用 0.2 秒淡入淡出，旋转沿用系统过渡，选集沿用系统 sheet。没有删除需要识别当前剧集与播放状态的文案，也没有引入整套新设计系统。

## 真机验证

最终回归命令，连续三次执行同一个真实交互测试：

```sh
xcodebuild -project ios-native/HongguoMobile.xcodeproj -scheme HongguoMobile \
  -destination 'id=<IPHONE_UDID>' -derivedDataPath /tmp/hongguo-ios-final-build \
  -allowProvisioningUpdates test \
  -only-testing:HongguoMobileUITests/MobileUITests/testFullscreenRotationPreservesPlaybackAndRestoresPortrait \
  -test-iterations 3 -resultBundlePath /tmp/hongguo-ios-fullscreen-releasecheck.xcresult
```

| 轮次 | 结果 | 时长 |
| --- | --- | --- |
| 1 | 通过，0 失败 | 48.892 秒 |
| 2 | 通过，0 失败 | 47.255 秒 |
| 3 | 通过，0 失败 | 47.234 秒 |

直接覆盖：从详情点分集默认全屏、视频画布与屏幕尺寸一致、真实视频播放、暂停、精确后退 15 秒、拖动进度、保持暂停状态与位置切换横屏、恢复播放后时间递增、横屏选择第二集并播放、恢复竖屏、再次横屏后退出回到竖屏详情。Xcode 报告运行期告警为 0。

拖动测试允许总时长 5% 的 XCTest 手势定位误差，另用后退 15 秒检查精确跳转（误差不超过 1 秒）。测试在操作前轻点无控件的画面区域，重新显示控制栏，避免自动隐藏与 XCTest 查找按钮之间的竞争。

此前全屏实现的浏览 / 搜索 / 短剧播放 / 下一集 / 历史重启读回测试，以及漫剧播放 / 选集入口测试，各连续三轮通过。后续仅调整进度同步和控制栏交互计时，并完成上述最终播放器专项回归；不把此前含测试脚本失败的整个结果包称为全部通过。

本次核心包检查：`swift test --package-path ios-native`，11 项通过、1 项实时接口测试按环境开关跳过，0 失败。实际短剧、漫剧接口由真机播放测试覆盖；上一版实时核心接口结果单独保留在 [VALIDATION.md](VALIDATION.md)，不替代本次结果。

## 视觉与安装

已查看本版三轮实际横竖屏截图；一轮 oil-ui-pro 局部独立视觉评审，没有必须处理的裁切、重叠、可读性或安全区问题，不打分。原生截图不适用网页截图工具的 lint。静态评审不能证明动效、音频听感或全部网络环境。

最终测试成功后通过 `devicectl` 覆盖安装，移除 UI 测试 runner，成功启动“红果剧场”首页。应用签名严格验证通过，版本 1.1.0 / build 2，第三方许可资源存在。

本地交付在 `outputs/delivery/ios-1.1.0/`：开发签名 IPA、源码 ZIP、横竖屏截图、测试与安装日志、结果摘要及 SHA256。开发包仅供已登记设备使用，不上传公开 Release；没有发布 App Store / TestFlight。Android 自动更新继续使用既有 TV Release。
