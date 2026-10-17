import XCTest
final class MobileUITests:XCTestCase {
    @MainActor func testBrowseSearchAndPlayOnPhone() throws {
        continueAfterFailure=false
        let app=XCUIApplication();app.terminate();app.launch()
        XCTAssertTrue(app.buttons["poster-first"].waitForExistence(timeout:45))
        let home=XCTAttachment(screenshot:app.screenshot());home.name="01-home";home.lifetime = .keepAlways;add(home)
        app.buttons["poster-first"].tap()
        XCTAssertTrue(app.buttons["开始观看"].waitForExistence(timeout:30))
        let title=app.staticTexts["detail-title"].label
        app.buttons["detail-episode-0"].tap()
        XCTAssertTrue(app.staticTexts["playback-clock"].waitForExistence(timeout:45))
        let time=app.staticTexts["playback-clock"]
        let playing=NSPredicate(format:"label CONTAINS '已播放' AND NOT label CONTAINS '已播放 0 秒'")
        expectation(for:playing,evaluatedWith:time)
        waitForExpectations(timeout:45)
        let player=XCTAttachment(screenshot:app.screenshot());player.name="02-player";player.lifetime = .keepAlways;add(player)
        revealControls(app,button:"下一集")
        app.buttons["下一集"].tap()
        XCTAssertTrue(app.staticTexts["第 2 集"].waitForExistence(timeout:30))
        expectation(for:playing,evaluatedWith:time);waitForExpectations(timeout:45)
        revealControls(app,button:"关闭播放")
        app.buttons["关闭播放"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        app.tabBars.buttons["搜索"].tap()
        let field=app.textFields["输入剧名或题材"];XCTAssertTrue(field.waitForExistence(timeout:10));field.tap();field.typeText("重生\n")
        XCTAssertTrue(app.staticTexts["search-summary"].waitForExistence(timeout:120))
        XCTAssertTrue(app.buttons.matching(identifier:"search-poster").firstMatch.exists)
        let search=XCTAttachment(screenshot:app.screenshot());search.name="03-search";search.lifetime = .keepAlways;add(search)
        app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(app.staticTexts["最近观看"].exists)
        XCTAssertTrue(app.staticTexts[title].exists)
        app.terminate();app.launch();app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout:15))
    }
    @MainActor func testComicPlaybackAndEpisodePicker() throws {
        continueAfterFailure=false
        let app=XCUIApplication();app.terminate();app.launch()
        app.segmentedControls["kind-picker"].buttons["漫剧"].tap()
        XCTAssertTrue(app.buttons["poster-first"].waitForExistence(timeout:45))
        app.buttons["poster-first"].tap()
        if !app.staticTexts["detail-title"].waitForExistence(timeout:5),app.buttons["poster-first"].exists { app.buttons["poster-first"].tap() }
        XCTAssertTrue(app.buttons["detail-episode-0"].waitForExistence(timeout:30))
        app.buttons["detail-episode-0"].tap()
        let time=app.staticTexts["playback-clock"]
        XCTAssertTrue(time.waitForExistence(timeout:45))
        let playing=NSPredicate(format:"label CONTAINS '已播放' AND NOT label CONTAINS '已播放 0 秒'")
        expectation(for:playing,evaluatedWith:time);waitForExpectations(timeout:45)
        let screenshot=XCTAttachment(screenshot:app.screenshot());screenshot.name="04-comic";screenshot.lifetime = .keepAlways;add(screenshot)
        revealControls(app,button:"选集")
        app.buttons["选集"].tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout:10))
        XCTAssertTrue(app.buttons["完成"].exists)
        app.buttons["完成"].tap()
        app.buttons["关闭播放"].tap()
    }
    @MainActor func testFullscreenRotationPreservesPlaybackAndRestoresPortrait() throws {
        continueAfterFailure=false
        XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication();app.terminate();app.launch()
        XCTAssertTrue(app.buttons["poster-first"].waitForExistence(timeout:45))
        app.buttons["poster-first"].tap()
        XCTAssertTrue(app.buttons["detail-episode-0"].waitForExistence(timeout:30))
        app.buttons["detail-episode-0"].tap()
        XCTAssertTrue(app.buttons["横屏"].waitForExistence(timeout:15))
        let surface=app.descendants(matching:.any)["video-surface"]
        XCTAssertTrue(surface.waitForExistence(timeout:10))
        XCTAssertEqual(surface.frame.minX,app.frame.minX,accuracy:2)
        XCTAssertEqual(surface.frame.minY,app.frame.minY,accuracy:2)
        XCTAssertEqual(surface.frame.width,app.frame.width,accuracy:2)
        XCTAssertEqual(surface.frame.height,app.frame.height,accuracy:2)
        func elapsed() -> Int { let value=surface.value as? String ?? "";return Int(value.components(separatedBy:"已播放 ").last?.components(separatedBy:" 秒").first ?? "") ?? 0 }
        let playing=NSPredicate { _,_ in elapsed()>0 }
        expectation(for:playing,evaluatedWith:surface);waitForExpectations(timeout:45)
        revealControls(app,button:"暂停")
        app.buttons["暂停"].tap()
        XCTAssertTrue(app.buttons["播放"].waitForExistence(timeout:10))
        let rewindTarget=max(0,elapsed()-15)
        app.buttons["后退15秒"].tap()
        expectation(for:NSPredicate { _,_ in abs(elapsed()-rewindTarget)<=1 },evaluatedWith:surface);waitForExpectations(timeout:15)
        let durationParts=app.staticTexts["playback-duration"].label.split(separator:":").compactMap { Int($0) }
        XCTAssertEqual(durationParts.count,2)
        let seekTarget=(durationParts[0]*60+durationParts[1])/2
        app.sliders["播放进度"].adjust(toNormalizedSliderPosition:0.5)
        // XCTest's normalized slider gesture is approximate; the button above checks exact seeking.
        let gestureTolerance=max(2,(durationParts[0]*60+durationParts[1])/20)
        expectation(for:NSPredicate { _,_ in abs(elapsed()-seekTarget)<=gestureTolerance },evaluatedWith:surface);waitForExpectations(timeout:15)
        XCTAssertTrue(app.buttons["播放"].exists)
        let before=elapsed()
        revealControls(app,button:"横屏")
        app.buttons["横屏"].tap()
        expectation(for:NSPredicate { _,_ in app.frame.width>app.frame.height },evaluatedWith:app);waitForExpectations(timeout:15)
        XCTAssertEqual(surface.frame.width,app.frame.width,accuracy:2)
        XCTAssertEqual(surface.frame.height,app.frame.height,accuracy:2)
        XCTAssertEqual(elapsed(),before,accuracy:1)
        XCTAssertTrue(app.buttons["播放"].exists)
        let landscape=XCTAttachment(screenshot:XCUIScreen.main.screenshot());landscape.name="05-fullscreen-landscape";landscape.lifetime = .keepAlways;add(landscape)
        app.buttons["播放"].tap()
        expectation(for:NSPredicate { _,_ in elapsed()>before },evaluatedWith:surface);waitForExpectations(timeout:15)
        revealControls(app,button:"选集")
        app.buttons["选集"].tap()
        XCTAssertTrue(app.buttons["episode-option-1"].waitForExistence(timeout:10))
        app.buttons["episode-option-1"].tap()
        expectation(for:NSPredicate { _,_ in (surface.value as? String ?? "").contains("第 2 集") && elapsed()>0 },evaluatedWith:surface);waitForExpectations(timeout:45)
        XCTAssertGreaterThan(app.frame.width,app.frame.height)
        revealControls(app,button:"暂停")
        app.buttons["暂停"].tap()
        XCTAssertTrue(app.buttons["播放"].waitForExistence(timeout:10))
        revealControls(app,button:"竖屏")
        app.buttons["竖屏"].tap()
        expectation(for:NSPredicate { _,_ in app.frame.height>app.frame.width },evaluatedWith:app);waitForExpectations(timeout:15)
        let portrait=XCTAttachment(screenshot:XCUIScreen.main.screenshot());portrait.name="06-fullscreen-portrait";portrait.lifetime = .keepAlways;add(portrait)
        revealControls(app,button:"横屏")
        app.buttons["横屏"].tap()
        expectation(for:NSPredicate { _,_ in app.frame.width>app.frame.height },evaluatedWith:app);waitForExpectations(timeout:15)
        revealControls(app,button:"关闭播放")
        app.buttons["关闭播放"].tap()
        expectation(for:NSPredicate { _,_ in app.frame.height>app.frame.width },evaluatedWith:app);waitForExpectations(timeout:15)
        XCTAssertTrue(app.staticTexts["detail-title"].waitForExistence(timeout:10))
    }

    @MainActor func testVerticalSwipeChangesEpisodesWithoutPresentingOverlays() throws {
        continueAfterFailure=false
        let app=XCUIApplication();app.terminate();app.launch()
        XCTAssertTrue(app.buttons["poster-first"].waitForExistence(timeout:45))
        app.buttons["poster-first"].tap()
        if !app.staticTexts["detail-title"].waitForExistence(timeout:5),app.buttons["poster-first"].exists { app.buttons["poster-first"].tap() }
        XCTAssertTrue(app.buttons["detail-episode-0"].waitForExistence(timeout:30))
        app.buttons["detail-episode-0"].tap()
        let surface=app.descendants(matching:.any)["video-surface"]
        XCTAssertTrue(surface.waitForExistence(timeout:15))
        func waitEpisode(_ number:Int,playing:Bool=true)->Bool {
            let predicate=NSPredicate { _,_ in
                let value=surface.value as? String ?? ""
                let elapsed=Int(value.components(separatedBy:"已播放 ").last?.components(separatedBy:" 秒").first ?? "") ?? 0
                return value.contains("第 \(number) 集") && (!playing || elapsed>0)
            }
            return XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:predicate,object:surface)],timeout:45) == .completed
        }
        func drag(_ x1:Double,_ y1:Double,_ x2:Double,_ y2:Double) {
            surface.coordinate(withNormalizedOffset:CGVector(dx:x1,dy:y1)).press(forDuration:0.1,thenDragTo:surface.coordinate(withNormalizedOffset:CGVector(dx:x2,dy:y2)))
        }
        revealControls(app,button:"播放设置");app.buttons["播放设置"].tap()
        XCTAssertTrue(app.buttons["关闭自动连播"].waitForExistence(timeout:10));app.buttons["关闭自动连播"].tap()
        revealControls(app,button:"选集");app.buttons["选集"].tap()
        XCTAssertTrue(app.buttons["episode-option-0"].waitForExistence(timeout:10))
        let count=try XCTUnwrap(Int(app.navigationBars.matching(NSPredicate(format:"identifier BEGINSWITH %@","共")).firstMatch.identifier.filter(\.isNumber)))
        app.buttons["episode-option-0"].tap()
        XCTAssertTrue(waitEpisode(1))
        expectation(for:NSPredicate { _,_ in !app.buttons["横屏"].exists },evaluatedWith:surface);waitForExpectations(timeout:15)
        drag(0.8,0.3,0.8,0.7)
        XCTAssertTrue(waitEpisode(1),"第一集下滑应保持当前集")
        drag(0.2,0.3,0.8,0.3)
        drag(0.8,0.3,0.8,0.34)
        XCTAssertTrue(waitEpisode(1),"横向和短距离拖动不能切集")
        drag(0.8,0.7,0.8,0.3)
        assertVisibleVideo("上滑切集时不能黑屏")
        XCTAssertTrue(waitEpisode(2),"上滑应进入第二集：\(surface.value as? String ?? "")")
        XCTAssertFalse(app.buttons["横屏"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format:"label BEGINSWITH %@","正在准备")).firstMatch.exists)
        XCTAssertEqual(app.alerts.count,0);XCTAssertEqual(app.sheets.count,0)
        let portrait=XCTAttachment(screenshot:XCUIScreen.main.screenshot());portrait.name="08-swipe-portrait";portrait.lifetime = .keepAlways;add(portrait)
        revealControls(app,button:"选集")
        let progress=app.sliders["播放进度"]
        XCTAssertTrue(progress.isEnabled)
        progress.coordinate(withNormalizedOffset:CGVector(dx:0.15,dy:0.5)).press(forDuration:0.1,thenDragTo:progress.coordinate(withNormalizedOffset:CGVector(dx:0.15,dy:-3)))
        XCTAssertTrue(waitEpisode(2),"进度条区域的上下拖动不能切集")
        revealControls(app,button:"选集")
        drag(0.8,0.3,0.8,0.7)
        assertVisibleVideo("下滑切集时不能黑屏")
        XCTAssertTrue(waitEpisode(1),"控制栏可见时下滑应回到第一集：\(surface.value as? String ?? "")")
        revealControls(app,button:"横屏");app.buttons["横屏"].tap()
        expectation(for:NSPredicate { _,_ in app.frame.width>app.frame.height && !app.buttons["竖屏"].exists },evaluatedWith:surface);waitForExpectations(timeout:15)
        drag(0.8,0.7,0.8,0.3)
        assertVisibleVideo("横屏切集时不能黑屏")
        XCTAssertTrue(waitEpisode(2),"横屏上滑也应进入第二集")
        XCTAssertGreaterThan(app.frame.width,app.frame.height)
        XCTAssertFalse(app.buttons["竖屏"].exists)
        let landscape=XCTAttachment(screenshot:XCUIScreen.main.screenshot());landscape.name="09-swipe-landscape";landscape.lifetime = .keepAlways;add(landscape)
        XCUIDevice.shared.press(.home);app.activate()
        XCTAssertTrue(surface.waitForExistence(timeout:10))
        XCTAssertTrue(app.buttons["播放"].waitForExistence(timeout:10),"回到播放器后应保持暂停且恢复控制栏")
        app.buttons["播放"].tap()
        revealControls(app,button:"选集");app.buttons["选集"].tap()
        let last=app.buttons["episode-option-\(count-1)"]
        let grid=try XCTUnwrap(app.scrollViews.allElementsBoundByIndex.first { $0.isHittable })
        for _ in 0..<6 { if last.exists && last.isHittable { break };grid.swipeUp() }
        XCTAssertTrue(last.waitForExistence(timeout:10));last.tap()
        XCTAssertTrue(waitEpisode(count,playing:false))
        drag(0.8,0.7,0.8,0.3)
        XCTAssertTrue(waitEpisode(count,playing:false),"最后一集上滑不能越界")
        XCTAssertEqual(app.alerts.count,0);XCTAssertEqual(app.sheets.count,0)
        if app.buttons["关闭播放"].exists { surface.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.25)).tap() }
        revealControls(app,button:"关闭播放")
        app.buttons["关闭播放"].tap()
        expectation(for:NSPredicate { _,_ in app.frame.height>app.frame.width },evaluatedWith:app);waitForExpectations(timeout:15)
    }

    @MainActor private func assertVisibleVideo(_ message:String,file:StaticString=#filePath,line:UInt=#line) {
        let capture=XCUIScreen.main.screenshot()
        let attachment=XCTAttachment(screenshot:capture);attachment.name="visible-frame";attachment.lifetime = .keepAlways;add(attachment)
        guard let image=capture.image.cgImage,
              let center=image.cropping(to:CGRect(x:image.width/4,y:image.height/4,width:image.width/2,height:image.height/2)) else { XCTFail("无法读取播放截图",file:file,line:line);return }
        var pixel=[UInt8](repeating:0,count:4)
        pixel.withUnsafeMutableBytes { bytes in
            if let context=CGContext(data:bytes.baseAddress,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) {
                context.draw(center,in:CGRect(x:0,y:0,width:1,height:1))
            }
        }
        XCTAssertGreaterThan(Int(pixel[0])+Int(pixel[1])+Int(pixel[2]),15,message,file:file,line:line)
    }

    @MainActor func testAutomaticContinuationDoesNotPresentOverlays() throws {
        continueAfterFailure=false
        XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication();app.terminate();app.launch()
        XCTAssertTrue(app.buttons["poster-first"].waitForExistence(timeout:45))
        app.buttons["poster-first"].tap()
        if !app.staticTexts["detail-title"].waitForExistence(timeout:5),app.buttons["poster-first"].exists { app.buttons["poster-first"].tap() }
        XCTAssertTrue(app.buttons["detail-episode-0"].waitForExistence(timeout:30))
        app.buttons["detail-episode-0"].tap()
        let surface=app.descendants(matching:.any)["video-surface"]
        XCTAssertTrue(surface.waitForExistence(timeout:15))
        func elapsed() -> Int { Int((surface.value as? String ?? "").components(separatedBy:"已播放 ").last?.components(separatedBy:" 秒").first ?? "") ?? 0 }
        expectation(for:NSPredicate { _,_ in elapsed()>0 },evaluatedWith:surface);waitForExpectations(timeout:45)
        revealControls(app,button:"选集")
        app.buttons["选集"].tap()
        XCTAssertTrue(app.buttons["episode-option-0"].waitForExistence(timeout:10))
        app.buttons["episode-option-0"].tap()
        expectation(for:NSPredicate { _,_ in (surface.value as? String ?? "").contains("第 1 集") && elapsed()>0 },evaluatedWith:surface);waitForExpectations(timeout:45)
        for episode in 2...3 {
            // Let real playback finish without tapping, seeking, or altering playback speed.
            expectation(for:NSPredicate { _,_ in (surface.value as? String ?? "").contains("第 \(episode) 集") },evaluatedWith:surface);waitForExpectations(timeout:300)
            XCTAssertFalse(app.buttons["横屏"].exists,"自动连播不能重新弹出控制栏：\(surface.value as? String ?? "")")
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format:"label BEGINSWITH %@","正在准备")).firstMatch.exists,"自动连播不能弹出加载窗口")
            XCTAssertEqual(app.alerts.count,0)
            XCTAssertEqual(app.sheets.count,0)
            expectation(for:NSPredicate { _,_ in elapsed()>0 },evaluatedWith:surface);waitForExpectations(timeout:45)
            XCTAssertFalse(app.buttons["横屏"].exists)
        }
        let screenshot=XCTAttachment(screenshot:XCUIScreen.main.screenshot());screenshot.name="07-silent-continuation";screenshot.lifetime = .keepAlways;add(screenshot)
        revealControls(app,button:"下一集")
        app.buttons["下一集"].tap()
        XCTAssertTrue(app.buttons["横屏"].waitForExistence(timeout:10),"手动操作应仍然显示控制栏")
        expectation(for:NSPredicate { _,_ in (surface.value as? String ?? "").contains("第 4 集") && elapsed()>0 },evaluatedWith:surface);waitForExpectations(timeout:45)
        revealControls(app,button:"关闭播放")
        app.buttons["关闭播放"].tap()
    }

    @MainActor private func revealControls(_ app:XCUIApplication,button:String) {
        let control=app.buttons[button]
        let background=app.descendants(matching:.any)["video-surface"].coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.25))
        for _ in 0..<2 {
            if control.exists && control.isHittable { return }
            background.tap()
        }
        XCTAssertTrue(control.exists && control.isHittable)
    }

}
