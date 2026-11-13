import XCTest
@testable import iOSLOG2LUTConverter

@MainActor
final class LUTLibraryTests: XCTestCase {
    private func fixture(contents: String, extension fileExtension: String = "cube") throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(fileExtension)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private let identityCube = """
    LUT_3D_SIZE 2
    0 0 0
    1 0 0
    0 1 0
    1 1 0
    0 0 1
    1 0 1
    0 1 1
    1 1 1
    """

    func testCustomPrimaryImportPersistsAndAppearsInSelector() throws {
        let source = try fixture(contents: identityCube)
        defer { try? FileManager.default.removeItem(at: source) }
        let manager = LUTManager()
        let imported = try manager.importCustomLUT(from: source)
        defer { try? FileManager.default.removeItem(at: imported.url) }
        XCTAssertNotEqual(imported.url, source)
        XCTAssertEqual(try Data(contentsOf: source), try Data(contentsOf: imported.url))
        XCTAssertEqual(manager.selectedPrimaryLUT?.url, imported.url)
        XCTAssertTrue(manager.primaryLutsByCategory[.custom]?.contains(where: { $0.url == imported.url }) == true)
        let reloaded = LUTManager()
        XCTAssertTrue(reloaded.customLUTs.contains(where: { $0.url == imported.url && !$0.isSecondary }))
        XCTAssertNil(reloaded.selectedPrimaryLUT)
    }

    func testInvalidLUTImportLeavesCurrentSelectionIntact() throws {
        let source = try fixture(contents: identityCube)
        let invalid = try fixture(contents: "LUT_3D_SIZE 2\n0 0 0")
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: invalid)
        }
        let manager = LUTManager()
        let valid = try manager.importCustomLUT(from: source, isSecondary: true)
        defer { try? FileManager.default.removeItem(at: valid.url) }
        let count = manager.customLUTs.count
        XCTAssertThrowsError(try manager.importCustomLUT(from: invalid, isSecondary: true))
        XCTAssertEqual(manager.selectedSecondaryLUT?.url, valid.url)
        XCTAssertEqual(manager.customLUTs.count, count)
        manager.clearSecondaryLUT()
        XCTAssertNil(manager.selectedSecondaryLUT)
    }

    func testUnsupportedCustomLUTFormatIsRejected() throws {
        let source = try fixture(contents: identityCube, extension: "3dl")
        defer { try? FileManager.default.removeItem(at: source) }
        let manager = LUTManager()
        XCTAssertThrowsError(try manager.importCustomLUT(from: source))
        XCTAssertNil(manager.selectedPrimaryLUT)
    }
    func testSelectedProjectLUTAppearsOnceAndClearingRemovesTemporaryEntry() throws {
        let source = try fixture(contents: identityCube)
        defer { try? FileManager.default.removeItem(at: source) }
        let manager = LUTManager()
        for secondary in [false, true] {
            let projectLUT = LUTManager.LUT(
                name: "saved-grade.cube", displayName: "Saved Grade", description: "Saved project LUT",
                category: .custom, url: source, isBuiltIn: false, isSecondary: secondary)
            if secondary { manager.selectSecondaryLUT(projectLUT) }
            else { manager.selectPrimaryLUT(projectLUT) }
            let catalog = secondary ? manager.secondaryLutsByCategory : manager.primaryLutsByCategory
            let matches = catalog.values.flatMap { $0 }.filter { $0.url == source }
            XCTAssertEqual(matches.count, 1)
            XCTAssertEqual(matches.first, projectLUT)
            XCTAssertEqual(matches.first?.description, "Saved project LUT")
            XCTAssertFalse(manager.customLUTs.contains(where: { $0.url == source }))
            // Re-reading the computed collection must not append persistent copies.
            let repeated = secondary ? manager.secondaryLutsByCategory : manager.primaryLutsByCategory
            XCTAssertEqual(repeated.values.flatMap { $0 }.filter { $0.url == source }.count, 1)
            if secondary { manager.clearSecondaryLUT() } else { manager.clearPrimaryLUT() }
            let cleared = secondary ? manager.secondaryLutsByCategory : manager.primaryLutsByCategory
            XCTAssertFalse(cleared.values.flatMap { $0 }.contains(where: { $0.url == source }))
        }
    }

}
