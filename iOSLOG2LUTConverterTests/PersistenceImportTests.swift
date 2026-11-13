import XCTest
@testable import iOSLOG2LUTConverter

final class PersistenceImportTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var defaultsName: String!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defaultsName = "PersistenceImportTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsName)!
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: defaultsName)
    }

    func testLocalFileImportCopiesBeforeOriginalDisappears() throws {
        let source = directory.appendingPathComponent("source.mov")
        let bytes = Data([1, 2, 3, 4])
        try bytes.write(to: source)
        let imports = directory.appendingPathComponent("imports", isDirectory: true)
        let imported = try FileImportManager.copyImportedFile(from: source, to: imports)
        let second = try FileImportManager.copyImportedFile(from: source, to: imports)
        try FileManager.default.removeItem(at: source)
        XCTAssertEqual(try Data(contentsOf: imported), bytes)
        XCTAssertEqual(imported.pathExtension, "mov")
        XCTAssertNotEqual(imported, second)
    }

    func testImportRejectsEmptyAndMissingFiles() throws {
        let source = directory.appendingPathComponent("empty.mov")
        try Data().write(to: source)
        XCTAssertThrowsError(try FileImportManager.copyImportedFile(from: source, to: directory))
        XCTAssertThrowsError(try FileImportManager.copyImportedFile(from: directory, to: directory))
        XCTAssertThrowsError(try FileImportManager.copyImportedFile(from: directory.appendingPathComponent("missing.mov"), to: directory))
    }

    @MainActor
    func testSavedProjectOwnsVideoAndLUTAndSurvivesStorageRelocation() async throws {
        let source = directory.appendingPathComponent("original.mov")
        let lut = directory.appendingPathComponent("custom.cube")
        let secondSource = directory.appendingPathComponent("second.mov")
        try Data([6, 7, 8]).write(to: secondSource)
        let videoBytes = Data([3, 4, 5])
        let lutBytes = Data("LUT_3D_SIZE 2\n0 0 0\n1 0 0\n0 1 0\n1 1 0\n0 0 1\n1 0 1\n0 1 1\n1 1 1\n".utf8)
        try videoBytes.write(to: source)
        try lutBytes.write(to: lut)
        let storage = directory.appendingPathComponent("projects", isDirectory: true)
        let manager = ProjectManager(projectsDirectory: storage, userDefaults: defaults)
        let state = ProjectState()
        // Previewing the second clip must not omit the first clip from a batch save.
        state.videoURLs = [secondSource]
        state.batchMode = true
        state.batchQueue = [.init(url: source, name: source.lastPathComponent), .init(url: secondSource, name: secondSource.lastPathComponent)]
        state.primaryLUTURL = lut
        state.primaryLUTOpacity = 0.42
        let library = LUTManager()
        let saved = await manager.saveProject(name: "  Test  ", projectState: state, lutManager: library)
        XCTAssertTrue(saved, manager.lastError ?? "")
        let project = try XCTUnwrap(manager.savedProjects.first)
        XCTAssertEqual(project.name, "Test")
        XCTAssertEqual(project.videoURLs.count, 2)
        XCTAssertEqual(try Data(contentsOf: project.videoURLs[0]), videoBytes)
        XCTAssertNotNil(project.primaryLUTFileName)
        try FileManager.default.removeItem(at: source)
        try FileManager.default.removeItem(at: secondSource)
        try FileManager.default.removeItem(at: lut)
        let relocated = directory.appendingPathComponent("relocated", isDirectory: true)
        try FileManager.default.moveItem(at: storage, to: relocated)
        let restoredManager = ProjectManager(projectsDirectory: relocated, userDefaults: defaults)
        let restoredProject = try XCTUnwrap(restoredManager.savedProjects.first)
        let restoredState = ProjectState()
        let loaded = await restoredManager.loadProject(restoredProject, into: restoredState, lutManager: library)
        XCTAssertTrue(loaded, restoredManager.lastError ?? "")
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(restoredState.videoURLs.first)), videoBytes)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(restoredState.primaryLUTURL)), lutBytes)
        XCTAssertEqual(restoredState.primaryLUTOpacity, 0.42)
        XCTAssertEqual(restoredState.batchQueue.count, 2)
        let deletedWhileOpen = await restoredManager.deleteProject(restoredProject, projectState: restoredState)
        XCTAssertFalse(deletedWhileOpen)
        XCTAssertTrue(FileManager.default.fileExists(atPath: restoredState.videoURLs[0].path))
        restoredState.videoURLs = []
        restoredState.batchQueue = []
        restoredState.primaryLUTURL = nil
        let deleted = await restoredManager.deleteProject(restoredProject, projectState: restoredState)
        XCTAssertTrue(deleted)
        XCTAssertFalse(FileManager.default.fileExists(atPath: relocated.appendingPathComponent(project.id.uuidString).path))
    }

    @MainActor
    func testOpeningProjectWithoutLUTClearsPreviousSelection() async throws {
        let manager = ProjectManager(projectsDirectory: directory.appendingPathComponent("projects"), userDefaults: defaults)
        let state = ProjectState()
        state.primaryLUTURL = directory.appendingPathComponent("previous.cube")
        state.secondaryLUTURL = directory.appendingPathComponent("previous-secondary.cube")
        let project = SavedProject(name: "Empty", videoURLs: [], primaryLUTName: nil, secondaryLUTName: nil, settings: ProjectSettings())
        let loaded = await manager.loadProject(project, into: state, lutManager: LUTManager())
        XCTAssertTrue(loaded)
        XCTAssertNil(state.primaryLUTURL)
        XCTAssertNil(state.secondaryLUTURL)
    }

    @MainActor
    func testMissingAssetsLeaveActiveProjectUntouched() async throws {
        let manager = ProjectManager(projectsDirectory: directory.appendingPathComponent("projects"), userDefaults: defaults)
        let state = ProjectState()
        let activeURL = directory.appendingPathComponent("active.mov")
        state.videoURLs = [activeURL]
        state.primaryLUTOpacity = 0.23
        let missingProject = SavedProject(name: "Missing", videoURLs: [directory.appendingPathComponent("missing.mov")], primaryLUTName: nil, secondaryLUTName: nil, settings: ProjectSettings())
        let loaded = await manager.loadProject(missingProject, into: state, lutManager: LUTManager())
        XCTAssertFalse(loaded)
        XCTAssertNotNil(manager.lastError)
        XCTAssertEqual(state.videoURLs, [activeURL])
        XCTAssertEqual(state.primaryLUTOpacity, 0.23)
    }

    @MainActor
    func testCorruptLUTAndOutOfRangeSettingsDoNotReplaceActiveProject() async throws {
        let storage = directory.appendingPathComponent("projects", isDirectory: true)
        let manager = ProjectManager(projectsDirectory: storage, userDefaults: defaults)
        let state = ProjectState()
        state.primaryLUTOpacity = 0.23
        let library = LUTManager()
        let id = UUID()
        let assets = storage.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try Data("not a LUT".utf8).write(to: assets.appendingPathComponent("bad.cube"))
        let corrupt = SavedProject(id: id, name: "Corrupt", videoURLs: [], primaryLUTName: "Bad", secondaryLUTName: nil, settings: ProjectSettings(), primaryLUTFileName: "bad.cube")
        let openedCorrupt = await manager.loadProject(corrupt, into: state, lutManager: library)
        XCTAssertFalse(openedCorrupt)
        XCTAssertEqual(state.primaryLUTOpacity, 0.23)
        XCTAssertNil(state.primaryLUTURL)
        let invalidSettings = SavedProject(name: "Invalid", videoURLs: [], primaryLUTName: nil, secondaryLUTName: nil, settings: ProjectSettings(primaryLUTOpacity: 2, whiteBalanceValue: 30))
        let openedInvalid = await manager.loadProject(invalidSettings, into: state, lutManager: library)
        XCTAssertFalse(openedInvalid)
        XCTAssertEqual(state.primaryLUTOpacity, 0.23)
    }

    @MainActor
    func testTemplateMatchesBuiltInNamesWithCubeExtension() async throws {
        let manager = ProjectManager(projectsDirectory: directory.appendingPathComponent("projects"), userDefaults: defaults)
        let library = LUTManager()
        let primaryURL = directory.appendingPathComponent("AppleLogToRec709-v1.0.cube")
        let secondaryURL = directory.appendingPathComponent("BLADE RUNNER 2049 - STREET.cube")
        library.primaryLUTs = [.init(name: primaryURL.lastPathComponent, displayName: "Apple Log", description: "", category: .appleLog, url: primaryURL, isBuiltIn: true, isSecondary: false)]
        library.secondaryLUTs = [.init(name: secondaryURL.lastPathComponent, displayName: "Blade Runner", description: "", category: .cinematic, url: secondaryURL, isBuiltIn: true, isSecondary: true)]
        let state = ProjectState()
        let template = try XCTUnwrap(manager.projectTemplates.first { $0.name == "iPhone Log to Cinematic" })
        let applied = await manager.applyTemplate(template, to: state, lutManager: library)
        XCTAssertTrue(applied, manager.lastError ?? "")
        XCTAssertEqual(state.primaryLUTURL, primaryURL)
        XCTAssertEqual(state.secondaryLUTURL, secondaryURL)
        XCTAssertEqual(state.secondLUTOpacity, template.settings.secondaryLUTOpacity)
    }

    func testOlderProjectJSONWithoutAssetFieldsStillDecodes() throws {
        let project = SavedProject(name: "Legacy", videoURLs: [], primaryLUTName: nil, secondaryLUTName: nil, settings: ProjectSettings())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(project)) as? [String: Any])
        object.removeValue(forKey: "videoFileNames")
        object.removeValue(forKey: "primaryLUTFileName")
        object.removeValue(forKey: "secondaryLUTFileName")
        let decoded = try JSONDecoder().decode(SavedProject.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.id, project.id)
        XCTAssertEqual(decoded.name, "Legacy")
        XCTAssertNil(decoded.videoFileNames)
    }

    @MainActor
    func testRelativeAssetsCannotEscapeProjectFolder() async throws {
        let manager = ProjectManager(projectsDirectory: directory.appendingPathComponent("projects"), userDefaults: defaults)
        let state = ProjectState()
        let activeURL = directory.appendingPathComponent("active.mov")
        state.videoURLs = [activeURL]
        let library = LUTManager()
        for invalidName in ["../outside.mov", ".", ".."] {
            let project = SavedProject(name: "Invalid", videoURLs: [], primaryLUTName: nil, secondaryLUTName: nil, settings: ProjectSettings(), videoFileNames: [invalidName])
            let loaded = await manager.loadProject(project, into: state, lutManager: library)
            XCTAssertFalse(loaded, "Invalid relative filename: \(invalidName)")
            XCTAssertNotNil(manager.lastError)
            XCTAssertEqual(state.videoURLs, [activeURL])
        }
        let emptyURL = directory.appendingPathComponent("empty.mov")
        try Data().write(to: emptyURL)
        for invalidURL in [directory!, emptyURL] {
            let project = SavedProject(name: "Invalid video", videoURLs: [invalidURL], primaryLUTName: nil, secondaryLUTName: nil, settings: ProjectSettings())
            let loaded = await manager.loadProject(project, into: state, lutManager: library)
            XCTAssertFalse(loaded, "Invalid video source: \(invalidURL)")
            XCTAssertNotNil(manager.lastError)
            XCTAssertEqual(state.videoURLs, [activeURL])
        }
    }
}
