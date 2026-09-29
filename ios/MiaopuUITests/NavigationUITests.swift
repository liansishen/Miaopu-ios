import XCTest

final class NavigationUITests: XCTestCase {
    func testSubscriptionsAndNavigationStayInSync() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset"]
        app.launch()

        app.tabBars.buttons["我的"].tap()
        app.buttons["赛事订阅"].tap()
        for sport in ["lol", "valorant", "cs2", "basketball", "football"] {
            let row = app.buttons["subscription-\(sport)"]
            XCTAssertTrue(row.waitForExistence(timeout: 10))
            row.tap()
        }
        app.navigationBars.buttons["我的"].tap()
        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(app.staticTexts["还没有订阅赛事"].waitForExistence(timeout: 10))

        app.tabBars.buttons["赛事"].tap()
        XCTAssertTrue(app.navigationBars["赛事"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["赛事项目"].waitForExistence(timeout: 10))
    }
}
