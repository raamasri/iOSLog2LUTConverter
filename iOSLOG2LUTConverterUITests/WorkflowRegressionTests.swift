import XCTest

final class WorkflowRegressionTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    private func attachScreenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication,
                        viewport: String = "controlsScrollView",
                        file: StaticString = #filePath, line: UInt = #line) {
        let scroll = app.scrollViews[viewport].firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 10), "Expected the opened screen's scroll view", file: file, line: line)
        for _ in 0..<15 {
            let visibleFrame = scroll.frame.intersection(app.frame)
            if element.exists && element.frame.width > 0 && element.frame.height > 0 && element.frame.minY >= visibleFrame.minY + 12 && element.frame.maxY <= visibleFrame.maxY - 12 && element.isHittable { return }
            let moveDown = element.exists && element.frame.minY < visibleFrame.minY + 12
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: moveDown ? 0.4 : 0.7))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: moveDown ? 0.7 : 0.4))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        if !element.exists || !element.isHittable {
            attachScreenshot("Unreachable control: \(element.identifier)", app: app)
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "UI hierarchy at reachability failure"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        let visible = scroll.frame.intersection(app.frame)
        XCTAssertTrue(element.exists && element.frame.width > 0 && element.frame.height > 0 && element.frame.minY >= visible.minY + 12 && element.frame.maxY <= visible.maxY - 12 && element.isHittable,
                      "The requested control must be fully visible and reachable by scrolling.", file: file, line: line)
    }

    @MainActor
    func testBatchAddVideosPresentsPhotoPicker() throws {
        let app = XCUIApplication()
        app.launch()
        attachScreenshot("Initial app", app: app)
        let batch = app.segmentedControls.buttons["Batch Processing"]
        XCTAssertTrue(batch.waitForExistence(timeout: 10))
        batch.tap()
        let add = app.buttons["batchAddVideos"]
        reveal(add, in: app)
        add.tap()
        XCTAssertTrue(app.buttons["Cancel"].firstMatch.waitForExistence(timeout: 10), "Add Videos must present the Photos picker.")
        app.buttons["Cancel"].firstMatch.tap()
    }

    @MainActor
    func testCustomLUTImportPresentsFilesAndCanCancel() throws {
        let app = XCUIApplication()
        app.launch()
        attachScreenshot("Initial app", app: app)
        let select = app.buttons["selectPrimaryLUT"]
        reveal(select, in: app)
        select.tap()
        attachScreenshot("Primary LUT selector", app: app)
        let custom = app.buttons["importCustomLUT"]
        reveal(custom, in: app, viewport: "lutCatalogScrollView")
        custom.tap()
        XCTAssertTrue(app.buttons["Cancel"].firstMatch.waitForExistence(timeout: 10), "Custom LUT import must present the Files picker.")
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
    }

    @MainActor
    func testFilesVideoImportIsReachable() throws {
        let app = XCUIApplication()
        app.launch()
        attachScreenshot("Initial app", app: app)
        let files = app.buttons["importFiles"]
        reveal(files, in: app)
        files.tap()
        XCTAssertTrue(app.buttons["Cancel"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["Cancel"].firstMatch.tap()
    }
}
