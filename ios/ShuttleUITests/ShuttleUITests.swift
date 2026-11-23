import XCTest

final class ShuttleUITests: XCTestCase {
    func testGuideAndSinglePlayerMatch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        // A SwiftUI button can combine its text and its SF Symbol label.
        let enterCourt = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "进入球场")).firstMatch
        XCTAssertTrue(enterCourt.waitForExistence(timeout: 10))
        attachScreenshot("大厅", app: app)

        app.buttons["操作指南"].tap()
        let closeGuide = app.buttons["关闭指南"]
        XCTAssertTrue(closeGuide.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["高远"].exists)
        closeGuide.tap()
        XCTAssertFalse(closeGuide.exists)

        enterCourt.tap()
        let serve = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "发球")).firstMatch
        XCTAssertTrue(serve.waitForExistence(timeout: 12))
        attachScreenshot("开球", app: app)
        serve.tap()

        // An unattended rally ends after one point. This verifies the serve
        // without trying to tap during a short, frame-dependent hit window.
        XCTAssertTrue(app.staticTexts["01"].firstMatch.waitForExistence(timeout: 25))
        let pause = app.buttons["暂停"]
        pause.tap()
        let resume = app.buttons["继续比赛"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["比赛暂停"].exists)
        resume.tap()
        XCTAssertFalse(resume.exists)
        pause.tap()
        app.buttons["返回主场"].tap()
        XCTAssertTrue(enterCourt.waitForExistence(timeout: 5))
    }

    private func attachScreenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
