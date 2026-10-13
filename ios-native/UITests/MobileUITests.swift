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
        app.buttons["下一集"].tap()
        XCTAssertTrue(app.staticTexts["第 2 集"].waitForExistence(timeout:30))
        expectation(for:playing,evaluatedWith:time);waitForExpectations(timeout:45)
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
        XCTAssertTrue(app.buttons["detail-episode-0"].waitForExistence(timeout:30))
        app.buttons["detail-episode-0"].tap()
        let time=app.staticTexts["playback-clock"]
        XCTAssertTrue(time.waitForExistence(timeout:45))
        let playing=NSPredicate(format:"label CONTAINS '已播放' AND NOT label CONTAINS '已播放 0 秒'")
        expectation(for:playing,evaluatedWith:time);waitForExpectations(timeout:45)
        let screenshot=XCTAttachment(screenshot:app.screenshot());screenshot.name="04-comic";screenshot.lifetime = .keepAlways;add(screenshot)
        app.buttons["选集"].tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout:10))
        XCTAssertTrue(app.buttons["完成"].exists)
        app.buttons["完成"].tap()
        app.buttons["关闭播放"].tap()
    }
}
