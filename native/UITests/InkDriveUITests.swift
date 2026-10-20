import XCTest

final class InkDriveUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }
    func testLibraryAndEditorWorkWithoutDevelopmentServer() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-smoke"]; app.launch()
        XCTAssertTrue(app.buttons["통계학"].waitForExistence(timeout: 12))
        XCTAssertFalse(app.buttons["새 수업 녹음"].exists)
        XCTAssertFalse(app.buttons["수업 연결"].exists)
        attach("Swift library", app)
        app.buttons["통계학"].tap()
        XCTAssertTrue(app.buttons["강의 1.pdf"].waitForExistence(timeout: 5))
        app.buttons["상위 폴더"].tap()
        XCTAssertTrue(app.buttons["작업설계"].exists)
        app.buttons["통계학"].tap(); app.buttons["강의 1.pdf"].tap()
        XCTAssertTrue(app.buttons["녹음 목록"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.buttons["녹음 시작"].exists)
        XCTAssertTrue(app.buttons["펜"].exists)
        attach("Swift editor", app)
        app.buttons["녹음 목록"].tap()
        XCTAssertTrue(app.staticTexts["저장된 녹음 없음"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["재생"].isEnabled)
        attach("Recording browser", app)
        app.buttons["필기로"].tap()
        app.buttons["페이지"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["목차"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.segmentedControls.buttons["북마크"].exists)
        XCTAssertTrue(app.segmentedControls.buttons["검색"].exists)
        attach("Page navigator", app)
        app.buttons["필기로"].tap()
        app.buttons["다른 문서 열기"].tap()
        XCTAssertTrue(app.cells.containing(.staticText, identifier: "강의 2").firstMatch.waitForExistence(timeout: 5))
        app.cells.containing(.staticText, identifier: "강의 2").firstMatch.tap()
        XCTAssertTrue(app.buttons["문서 탭 통계학/강의 2.pdf"].waitForExistence(timeout: 8))
        attach("Document tabs", app)
        app.buttons["서재로"].tap()
        XCTAssertTrue(app.buttons["강의 1.pdf"].waitForExistence(timeout: 10))
    }
    private func attach(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
