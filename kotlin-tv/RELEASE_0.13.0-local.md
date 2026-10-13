# 红果 TV 0.13.0-local · Media3 官方预加载

2026-10-14。采用当前已安装的 Media3 1.8.0 `DefaultPreloadManager`，保留原生 View、现有解密 DataSource、播放器控件、观看进度、自动连播与定时停止。没有增加依赖或切换播放器内核。

## 本版变化

- 继续在本集最后30秒的实际播放时间内、当前缓冲充足且非计费网络时准备下一集地址和媒体头；再通过官方预加载器解析轨道、加载下一集开头3秒的音视频样本。
- 同一个官方Builder创建预加载器与ExoPlayer，共享分配器、加载控制和播放线程；只管理下一集，不预加载全部片单。
- 换集读取预加载的MediaSource，保留其样本缓冲；达到READY后移除预加载器持有的引用，播放继续使用该源。常规换集复用ExoPlayer和PlayerView。
- 准备失败或缓存失效时走原有取址/准备流程。预加载异常不向当前集显示播放错误；正常播放异常仍保留原有重试与观看位置。
- 切换内容、后台、计费/断网回调与低内存取消时清理预加载；离开播放器时释放预加载器。异步完成仍须匹配页面代次、播放器、下一集和清晰度，防止旧结果进入新播放。
- 沿用0.12更新渠道与本地Debug测试签名，versionCode13；可覆盖0.12并由应用内更新获取。旧0.10/0.11仍需先手动接入新渠道。

官方API参考：[DefaultPreloadManager](https://developer.android.com/media/media3/exoplayer/preloading-media/preloadmanager)、[1.8.0实现](https://github.com/androidx/media/blob/1.8.0/libraries/exoplayer/src/main/java/androidx/media3/exoplayer/source/preload/DefaultPreloadManager.java)。已有Media3依赖为Apache-2.0，来源声明见[NOTICE](NOTICE.md)。

## 实际验证

| 检查 | 结果 |
| --- | --- |
| 回归先失败后通过 | 原0.12可正常播放，但没有官方样本预加载，新增验收失败；接入后通过 |
| 核心与构建 | 105项核心测试0 failures / 0 errors；Debug APK与验收APK构建通过 |
| Lint | 0 errors、33 warnings，包含已有依赖、弃用API及国际化提醒 |
| 真正Android TV | API36、1920×1080模拟器；真实漫剧、真人短剧各两次自动换集 |
| 预加载真实性 | 官方onCompleted确认达到样本加载目标；预加载器仅持有一个源；确认Media3实际将同一源交给播放器，未丢弃后重新构造 |
| 播放与资源 | 复用同一ExoPlayer，当前视频不中断；暂停恢复通过，低内存取消后当前集继续播放，后台释放预加载器，返回恢复原位置并保持暂停 |
| 签名与升级条件 | 本地Android Debug签名，与0.12一致；包名com.hongguotv.nativeapp，minSdk26、targetSdk36 |

本轮从本集真实ENDED回调到下一集真实onRenderedFirstFrame的样本：

| 类型 | 第一次 | 第二次 |
| --- | --- | --- |
| 漫剧 | 273 ms | 248 ms |
| 真人短剧 | 338 ms | 227 ms |

这是当前模拟器、网络和所选片源的4次样本，不是旧版与新版的同条件对照，也不承诺实体电视达到相同时延。3秒是预加载样本时长目标，不是总内存硬上限；仍需实体电视测量内存与解码压力。

## 验收命令

```sh
HONGGUOTV_TEST_RUNNER=com.hongguotv.nativeapp.PreloadAcceptance \
  ./kotlin-tv/gradlew -p kotlin-tv :app:assembleDebug :app:assembleDebugAndroidTest :app:lintDebug
adb -s YOUR_TEST_TV install -r kotlin-tv/app/build/outputs/apk/debug/app-debug.apk
adb -s YOUR_TEST_TV install -r kotlin-tv/app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk
adb -s YOUR_TEST_TV shell am instrument -w com.hongguotv.nativeapp.test/com.hongguotv.nativeapp.PreloadAcceptance
```

需要JDK17与Android SDK36。验收会实际播放、快进、自动换集并推进测试设备观看记录，只在测试设备运行。报告和真实截图位于应用external files/preload-acceptance；不能只看Instrumentation退出码，须确认报告无FAIL。

APK SHA-256：`1dfb9464a942caecfc1446aeaf6c5b85e1ddf4b5d7db8f09d2b2bb4cec7a8837`。公开Release同时提供对应源码ZIP、update.json、SHA256SUMS与验证证据ZIP。源码提交以该Release清单为准。

实体电视、Android8本轮运行、网络故障注入与长时间内存压力尚未验收。本版不宣称零间隙播放；源编码变化、电视解码器重建和上游取址仍可能增加换集等待。
