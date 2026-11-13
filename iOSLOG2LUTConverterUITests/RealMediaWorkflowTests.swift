import XCTest

/// These tests use the real user-supplied Sony video and grading examples seeded
/// into the simulator's Photos library / Documents/RealMediaFixtures by the host.
/// They drive the same native pickers and app controls available to users.
final class RealMediaWorkflowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    override func setUp() async throws {
        await MainActor.run { XCUIDevice.shared.orientation = .portrait }
    }

    override func tearDown() async throws {
        if (testRun?.failureCount ?? 0) > 0 {
            await MainActor.run {
                capture(XCUIApplication(), "Failure in \(name)", hierarchy: true)
            }
        }
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String, hierarchy: Bool = false) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        if hierarchy {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "\(name) accessibility hierarchy"
            tree.lifetime = .keepAlways
            add(tree)
        }
    }

    @MainActor
    private func reveal(_ target: XCUIElement, app: XCUIApplication, limit: Int = 24,
                        viewport: String = "controlsScrollView",
                        file: StaticString = #filePath, line: UInt = #line) {
        // Callers know which screen they opened. A dismissed sheet may retain a
        // scroll-view accessibility node whose activation point is invalid.
        let scroll = app.scrollViews[viewport].firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 10), "Expected the opened screen's scroll view", file: file, line: line)
        for _ in 0..<limit {
            let frame = scroll.frame.intersection(app.frame)
            if target.exists {
                let targetFrame = target.frame
                // Check geometry before asking for an activation point. A partly
                // clipped slider must be scrolled fully clear of the preview.
                if targetFrame.width > 0 && targetFrame.height > 0 && targetFrame.minY.isFinite && targetFrame.maxY.isFinite && targetFrame.minY >= frame.minY + 12 && targetFrame.maxY <= frame.maxY - 12 && target.isHittable { return }
            }
            let down = target.exists && target.frame.minY < frame.minY + 12
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.4 : 0.7))
                .press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.7 : 0.4)))
        }
        capture(app, "Unreachable \(target.identifier)", hierarchy: true)
        let visible = scroll.frame.intersection(app.frame)
        XCTAssertTrue(target.exists && target.frame.width > 0 && target.frame.height > 0 && target.frame.minY >= visible.minY + 12 && target.frame.maxY <= visible.maxY - 12 && target.isHittable, "Control must be fully visible and reachable", file: file, line: line)
    }

    @MainActor
    private func selectPhotos(_ count: Int, app: XCUIApplication, originalSource: Bool = true) {
        let importButton = app.buttons["importPhotos"]
        reveal(importButton, app: app)
        importButton.tap()
        // iOS 27 exposes Photos grid assets as images, not collection cells.
        // The source metadata identifies the actual supplied Sony original.
        let videos = app.images.matching(identifier: "PXGGridLayout-Info")
        let date = originalSource ? "August 25, 2024" : "June 25, 2025"
        let source = videos.matching(NSPredicate(format: "label CONTAINS %@", date)).firstMatch
        let exists = source.waitForExistence(timeout: 15)
        capture(app, "Seeded Photos videos before selection", hierarchy: true)
        XCTAssertTrue(exists, "The explicitly requested supplied video must be visible in Photos")
        source.tap()
        if count > 1 {
            let reference = videos.matching(NSPredicate(format: "label CONTAINS %@", "June 25, 2025")).firstMatch
            XCTAssertTrue(reference.waitForExistence(timeout: 10), "The supplied converted reference must be visible in Photos")
            reference.tap()
        }
        if count > 1 {
            // The native checkmark is identifier Add / label Done. Restrict the
            // query to the picker navigation bar so the underlying app's Add
            // Videos button cannot be mistaken for confirmation.
            let confirm = app.navigationBars["Videos"].buttons["Add"]
            XCTAssertTrue(confirm.waitForExistence(timeout: 15), "The native Photos picker must offer confirmation of both selected videos")
            capture(app, "Native Photos batch ready for confirmation", hierarchy: true)
            confirm.tap()
        }
        XCTAssertTrue(app.images["gradedPreview"].waitForExistence(timeout: 120), "The selected real video must generate a preview")
        capture(app, "Imported real Photos video", hierarchy: true)
    }

    @MainActor
    private func chooseLUT(_ filename: String, secondary: Bool, app: XCUIApplication) {
        let selector = app.buttons[secondary ? "selectSecondaryLUT" : "selectPrimaryLUT"]
        reveal(selector, app: app)
        selector.tap()
        let lut = app.buttons["lut-builtin-\(filename)"]
        reveal(lut, app: app, limit: 40, viewport: "lutCatalogScrollView")
        lut.tap()
        XCTAssertTrue(app.images["gradedPreview"].waitForExistence(timeout: 60))
    }

    @MainActor
    private func adjustGrade(app: XCUIApplication) {
        let primary = app.sliders["primaryOpacity"]
        reveal(primary, app: app)
        let initialPrimary = primary.value as? String
        primary.adjust(toNormalizedSliderPosition: 0.85)
        XCTAssertNotEqual(primary.value as? String, initialPrimary)
        let whiteBalance = app.sliders["whiteBalance"]
        reveal(whiteBalance, app: app)
        let initialWhiteBalance = whiteBalance.value as? String
        // This signed-value SwiftUI slider exposes a raw value ("0"), whereas
        // opacity exposes a percentage. XCTest's normalized accessibility
        // adjustment does not reliably move it on iPad; drag the visible thumb
        // as a user would and still require the value to actually change.
        whiteBalance.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: whiteBalance.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)))
        XCTAssertNotEqual(whiteBalance.value as? String, initialWhiteBalance)
        let secondary = app.sliders["secondaryOpacity"]
        reveal(secondary, app: app)
        let initialSecondary = secondary.value as? String
        secondary.adjust(toNormalizedSliderPosition: 0.35)
        XCTAssertNotEqual(secondary.value as? String, initialSecondary)
        let timeline = app.sliders["videoTimeline"]
        XCTAssertTrue(timeline.waitForExistence(timeout: 30))
        timeline.adjust(toNormalizedSliderPosition: 0.45)
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.progressIndicators["previewLoading"])
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 90), .completed)
        let comparison = app.buttons["toggleComparison"]
        comparison.tap()
        XCTAssertTrue(app.staticTexts["BEFORE"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["AFTER"].exists)
        XCTAssertLessThan(app.staticTexts["BEFORE"].frame.maxY, timeline.frame.minY - 40, "Comparison labels must stay above the timeline overlay")
        XCTAssertLessThan(app.staticTexts["AFTER"].frame.maxY, timeline.frame.minY - 40, "Comparison labels must stay above the timeline overlay")
        capture(app, "Real media before-after after scrubbing")
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.width > app.frame.height && self.comparisonFitsWindow(app)
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 10), .completed)
        capture(app, "Real media landscape comparison", hierarchy: true)
        XCTAssertGreaterThan(app.images["comparisonOriginal"].frame.height, 60, "Landscape must reserve meaningful image height")
        XCTAssertGreaterThan(app.images["comparisonGraded"].frame.height, 60, "Landscape must reserve meaningful image height")
        XCTAssertLessThan(app.staticTexts["BEFORE"].frame.maxY, app.sliders["videoTimeline"].frame.minY - 40)
        XCTAssertLessThan(app.staticTexts["AFTER"].frame.maxY, app.sliders["videoTimeline"].frame.minY - 40)
        XCUIDevice.shared.orientation = .portrait
        let portrait = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.height > app.frame.width && self.comparisonFitsWindow(app)
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [portrait], timeout: 10), .completed)
        capture(app, "Real media portrait comparison after rotation")
        XCTAssertGreaterThan(app.images["comparisonOriginal"].frame.height, 60)
        XCTAssertLessThan(app.staticTexts["BEFORE"].frame.maxY, app.sliders["videoTimeline"].frame.minY - 40)
        let mode = app.buttons["comparisonMode"]
        mode.tap()
        app.buttons["A/B Toggle"].tap()
        let before = app.buttons["Before (Original)"]
        XCTAssertTrue(before.waitForExistence(timeout: 5))
        before.tap()
        app.buttons["After (LUT)"].tap()
        capture(app, "Real media A-B comparison")
        mode.tap()
        app.buttons["Top/Bottom Split"].tap()
        XCTAssertTrue(app.staticTexts["BEFORE"].waitForExistence(timeout: 5))
        capture(app, "Real media split comparison")
        comparison.tap()
    }

    @MainActor
    private func comparisonFitsWindow(_ app: XCUIApplication) -> Bool {
        let window = app.frame.insetBy(dx: -1, dy: -1)
        return ["comparisonOriginal", "comparisonGraded"].allSatisfy { identifier in
            let image = app.images[identifier]
            guard image.exists else { return false }
            let frame = image.frame
            return frame.width > 60 && frame.height > 60 && window.contains(frame)
        }
    }

    @MainActor
    private func export(app: XCUIApplication, batch: Bool = false) {
        let quality = app.buttons["exportQuality"]
        reveal(quality, app: app)
        quality.tap()
        let low = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Low (")).firstMatch
        XCTAssertTrue(low.waitForExistence(timeout: 5))
        low.tap()
        let convert = app.buttons["convertVideo"]
        reveal(convert, app: app)
        XCTAssertTrue(convert.isEnabled)
        convert.tap()
        let output = app.buttons[batch ? "saveBatchToPhotos" : "saveVideoToPhotos"]
        XCTAssertTrue(output.waitForExistence(timeout: 360), "Processing must produce an actual shareable export")
        reveal(output, app: app)
        if batch {
            XCTAssertEqual(app.staticTexts["operationStatus"].label, "Batch finished: 2 completed, 0 failed", "Every selected real video must export successfully")
        }
        capture(app, batch ? "Real batch export completed" : "Real single export completed", hierarchy: true)
    }

    @MainActor
    private func saveExportToPhotos(app: XCUIApplication, batch: Bool = false) {
        let save = app.buttons[batch ? "saveBatchToPhotos" : "saveVideoToPhotos"]
        reveal(save, app: app)
        save.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        if alert.waitForExistence(timeout: 3) {
            let allow = alert.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Allow' OR label == 'Add Photos Only' OR label == 'OK'")).firstMatch
            XCTAssertTrue(allow.exists, "Expected Photos add authorization")
            allow.tap()
        }
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Saved to Photos"), object: save)
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 90), .completed)
        XCTAssertFalse(save.isEnabled, "A saved result must not be saved twice by repeated taps")
        capture(app, "Export saved to Photos")
    }

    @MainActor
    private func openShare(app: XCUIApplication, batch: Bool = false) {
        let share = app.buttons[batch ? "shareBatch" : "shareVideo"]
        reveal(share, app: app)
        share.tap()
        let action = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Save to Files' OR label == 'Copy' OR label == 'AirDrop'")).firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: 15), "Share must open the native activity sheet for the exported video")
        capture(app, "Export native share sheet", hierarchy: true)
        let close = app.buttons["Close"].firstMatch
        if close.exists { close.tap() }
        else { app.swipeDown() }
    }

    @MainActor
    private func projectRoundTrip(app: XCUIApplication) {
        let name = "Real media UI \(UUID().uuidString.prefix(8))"
        let projects = app.buttons["projectManagement"]
        reveal(projects, app: app)
        projects.tap()
        app.buttons["saveCurrentProject"].tap()
        let field = app.textFields["projectName"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(name)
        app.buttons["saveProject"].tap()
        XCTAssertTrue(app.buttons["projectTab-Saved"].waitForExistence(timeout: 30))
        app.buttons["projectTab-Saved"].tap()
        let search = app.textFields["projectSearch"]
        search.tap()
        search.typeText(name + "\n")
        let favorite = app.buttons["favoriteProject-\(name)"]
        XCTAssertTrue(favorite.waitForExistence(timeout: 10))
        favorite.tap()
        XCTAssertEqual(favorite.label, "Remove favorite")
        app.buttons["projectTab-Favorites"].tap()
        let load = app.buttons["loadProject-\(name)"]
        XCTAssertTrue(load.waitForExistence(timeout: 10))
        capture(app, "Saved, searched and favorited real-media project")
        load.tap()
        XCTAssertTrue(app.images["gradedPreview"].waitForExistence(timeout: 90))
        XCTAssertFalse(app.buttons["shareVideo"].exists, "A newly loaded project must not offer the previous export")
        // Clear the active project before deleting its owned media.
        let reset = app.buttons["resetAll"]
        reveal(reset, app: app)
        reset.tap()
        reveal(projects, app: app)
        projects.tap()
        app.buttons["projectTab-Saved"].tap()
        let remove = app.buttons["deleteProject-\(name)"]
        reveal(remove, app: app, viewport: "projectCatalogScrollView")
        remove.tap()
        app.alerts["Delete Project"].buttons["Delete"].tap()
        let deleted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["loadProject-\(name)"])
        XCTAssertEqual(XCTWaiter.wait(for: [deleted], timeout: 30), .completed)
        app.buttons["projectTab-Templates"].tap()
        let templateSearch = app.textFields["projectSearch"]
        templateSearch.tap()
        templateSearch.typeText("Sony S-Log3 to Rec709\n")
        let template = app.buttons["applyTemplate-Sony S-Log3 to Rec709"]
        XCTAssertTrue(template.waitForExistence(timeout: 10))
        template.tap()
        XCTAssertTrue(app.buttons["selectPrimaryLUT"].waitForExistence(timeout: 10))
        capture(app, "Saved project removed and Sony template applied")
    }

    @MainActor
    private func chooseDocument(_ filename: String, app: XCUIApplication) {
        capture(app, "Native Files picker for \(filename)", hierarchy: true)
        let stem = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        func item(_ prefix: String) -> XCUIElement {
            app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
        }
        if !item(stem).exists {
            let device = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'On My iPhone' OR label == 'On My iPad'")).firstMatch
            // iPad presents locations directly in its sidebar; iPhone exposes
            // them after Browse. Wait for the hosted picker before deciding
            // which of these actual native layouts needs navigation.
            if !device.waitForExistence(timeout: 5) {
                let browse = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Browse")).firstMatch
                XCTAssertTrue(browse.waitForExistence(timeout: 15), "The native Files Browse tab or locations sidebar must be available")
                browse.tap()
            }
            capture(app, "Files locations for \(filename)", hierarchy: true)
            XCTAssertTrue(device.waitForExistence(timeout: 10), "The app's Files documents provider must be visible")
            device.tap()
            let appFolder = item("VideoLUTConverter")
            XCTAssertTrue(appFolder.waitForExistence(timeout: 10))
            appFolder.tap()
            let fixtures = item("RealMediaFixtures")
            XCTAssertTrue(fixtures.waitForExistence(timeout: 10))
            fixtures.tap()
        }
        let file = item(stem)
        XCTAssertTrue(file.waitForExistence(timeout: 10), "The supplied file must be available through native Files")
        file.tap()
    }

    @MainActor
    func testRealCustomLUTFilesImportSelectsSuppliedCubes() throws {
        let app = XCUIApplication()
        app.launch()
        for (secondary, filename) in [(false, "1_SGamut3CineSLog3_To_LC-709.cube"), (true, "IWLTBAP Aspen - Standard.cube")] {
            let selector = app.buttons[secondary ? "selectSecondaryLUT" : "selectPrimaryLUT"]
            reveal(selector, app: app)
            selector.tap()
            let custom = app.buttons["importCustomLUT"]
            XCTAssertTrue(custom.waitForExistence(timeout: 10))
            custom.tap()
            chooseDocument(filename, app: app)
            XCTAssertTrue(selector.waitForExistence(timeout: 20))
            let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", secondary ? "IWLTBAP Aspen" : "SGamut3CineSLog3"), object: selector)
            XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 30), .completed, "The selected supplied custom LUT must be reflected in the main controls after import completes")
        }
        capture(app, "Both supplied custom LUTs imported through native Files", hierarchy: true)
    }

    @MainActor
    func testRealOriginalFromFilesWithCustomLUTsExports() throws {
        let app = XCUIApplication()
        app.launch()
        let files = app.buttons["importFiles"]
        reveal(files, app: app)
        files.tap()
        chooseDocument("rsiv5362 ORIGINAL SLOG3CINE.MP4", app: app)
        XCTAssertTrue(app.images["gradedPreview"].waitForExistence(timeout: 120))
        capture(app, "Original Sony source imported through Files", hierarchy: true)
        for (secondary, filename) in [(false, "1_SGamut3CineSLog3_To_LC-709.cube"), (true, "IWLTBAP Aspen - Standard.cube")] {
            let selector = app.buttons[secondary ? "selectSecondaryLUT" : "selectPrimaryLUT"]
            reveal(selector, app: app)
            selector.tap()
            let custom = app.buttons["importCustomLUT"]
            XCTAssertTrue(custom.waitForExistence(timeout: 10))
            custom.tap()
            chooseDocument(filename, app: app)
            let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", secondary ? "IWLTBAP Aspen" : "SGamut3CineSLog3"), object: selector)
            XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 30), .completed, "The supplied custom LUT must finish importing before grading")
            XCTAssertTrue(app.images["gradedPreview"].waitForExistence(timeout: 60))
        }
        adjustGrade(app: app)
        export(app: app)
        openShare(app: app)
        let primary = app.sliders["primaryOpacity"]
        reveal(primary, app: app)
        let exportedOpacity = primary.value as? String
        primary.adjust(toNormalizedSliderPosition: 0.60)
        XCTAssertNotEqual(primary.value as? String, exportedOpacity, "The grade must actually change after the completed export")
        let invalidated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["shareVideo"])
        XCTAssertEqual(XCTWaiter.wait(for: [invalidated], timeout: 15), .completed)
        XCTAssertFalse(app.buttons["saveVideoToPhotos"].exists, "An old grade must not remain available for saving after a setting edit")
        let convertAgain = app.buttons["convertVideo"]
        reveal(convertAgain, app: app)
        XCTAssertTrue(convertAgain.isEnabled)
        XCTAssertEqual(convertAgain.label, "Convert Video", "Editing the grade must clear the previous Converted state")
        capture(app, "Grade edit invalidated the previous export", hierarchy: true)
        export(app: app)
        capture(app, "Changed grade exported successfully again", hierarchy: true)
    }

    @MainActor
    func testRealPhotosSingleExportSaveShareAndProjectRoundTrip() throws {
        let app = XCUIApplication()
        app.launch()
        selectPhotos(1, app: app)
        chooseLUT("1_SGamut3CineSLog3_To_LC-709.cube", secondary: false, app: app)
        chooseLUT("IWLTBAP Aspen - Standard.cube", secondary: true, app: app)
        adjustGrade(app: app)
        export(app: app)
        saveExportToPhotos(app: app)
        openShare(app: app)
        projectRoundTrip(app: app)
    }

    @MainActor
    func testRealReferencePhotosSingleExportSaveShareAndProjectRoundTrip() throws {
        let app = XCUIApplication()
        app.launch()
        selectPhotos(1, app: app, originalSource: false)
        chooseLUT("1_SGamut3CineSLog3_To_LC-709.cube", secondary: false, app: app)
        chooseLUT("IWLTBAP Aspen - Standard.cube", secondary: true, app: app)
        adjustGrade(app: app)
        export(app: app)
        saveExportToPhotos(app: app)
        openShare(app: app)
        projectRoundTrip(app: app)
    }

    @MainActor
    func testRealOriginalExportCancellationThenRetry() throws {
        let app = XCUIApplication()
        app.launch()
        selectPhotos(1, app: app)
        chooseLUT("1_SGamut3CineSLog3_To_LC-709.cube", secondary: false, app: app)
        let quality = app.buttons["exportQuality"]
        reveal(quality, app: app)
        quality.tap()
        let maximum = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Maximum (")).firstMatch
        XCTAssertTrue(maximum.waitForExistence(timeout: 5))
        maximum.tap()
        let convert = app.buttons["convertVideo"]
        reveal(convert, app: app)
        convert.tap()
        let cancel = app.buttons["cancelProcessing"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 15), "An active export must offer cancellation")
        reveal(cancel, app: app)
        cancel.tap()
        let status = app.staticTexts["operationStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 45), "Cancellation must finish and restore the editor")
        XCTAssertTrue(status.label.localizedCaseInsensitiveContains("cancelled"), "Cancellation must be reported accurately")
        XCTAssertFalse(app.buttons["shareVideo"].exists, "A cancelled partial export must not be shareable")
        XCTAssertFalse(app.buttons["saveVideoToPhotos"].exists, "A cancelled partial export must not be offered for saving")
        XCTAssertTrue(convert.isEnabled, "The user must be able to retry after cancelling")
        capture(app, "Real original maximum export cancelled", hierarchy: true)
        export(app: app)
        capture(app, "Real original export succeeded after cancellation and low-quality retry", hierarchy: true)
    }

    @MainActor
    func testRealPhotosBatchExportsSaveAndShare() throws {
        let app = XCUIApplication()
        app.launch()
        app.segmentedControls.buttons["Batch Processing"].tap()
        selectPhotos(2, app: app)
        chooseLUT("1_SGamut3CineSLog3_To_LC-709.cube", secondary: false, app: app)
        chooseLUT("IWLTBAP Aspen - Standard.cube", secondary: true, app: app)
        export(app: app, batch: true)
        saveExportToPhotos(app: app, batch: true)
        openShare(app: app, batch: true)
    }
}
