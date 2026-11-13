import XCTest
import AVFoundation
import CryptoKit
@testable import iOSLOG2LUTConverter

/// Opt-in acceptance coverage using the user's supplied, unmodified media.
/// Stage it with scripts/validation/stage_simulator_fixtures.py before running.
@MainActor
final class RealProjectAcceptanceTests: XCTestCase {
    private func fixtureDirectory() throws -> URL {
        let directory = URL.documentsDirectory.appendingPathComponent("RealMediaFixtures", isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else {
            throw XCTSkip("Real-media acceptance requires staged RealMediaFixtures.")
        }
        return directory
    }

    private nonisolated static func digest(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let chunk = try file.read(upToCount: 1_048_576), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    func testRealMediaImportSaveReloadAndBatchExport() async throws {
        let fixtures = try fixtureDirectory()
        let source = fixtures.appendingPathComponent("rsiv5362 ORIGINAL SLOG3CINE.MP4")
        let converted = fixtures.appendingPathComponent("rsiv5362_converted_M31 - Rec.709_47percent.mp4")
        let primary = fixtures.appendingPathComponent("1_SGamut3CineSLog3_To_LC-709.cube")
        let secondary = fixtures.appendingPathComponent("M31 - Rec.709.cube")
        for url in [source, converted, primary, secondary] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Missing fixture: \(url.lastPathComponent)")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("RealProjectAcceptance-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaultsName = "RealProjectAcceptance.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let imports = directory.appendingPathComponent("Imports", isDirectory: true)
        let imported = try FileImportManager.copyImportedFile(from: source, to: imports)
        let importedConversion = try FileImportManager.copyImportedFile(from: converted, to: imports)
        let importedHash = try await Task.detached { try Self.digest(imported) }.value
        let sourceHash = try await Task.detached { try Self.digest(source) }.value
        XCTAssertEqual(importedHash, sourceHash, "Import must preserve the supplied 10-bit original bytes")

        let library = LUTManager()
        await library.loadBuiltInLUTs().value
        let state = ProjectState()
        state.primaryLUTURL = primary
        state.secondaryLUTURL = secondary
        state.primaryLUTOpacity = 1
        state.secondLUTOpacity = 0.47
        state.whiteBalanceValue = 1
        state.exportQuality = .low
        state.replaceProjectVideos([imported, importedConversion])
        state.selectBatchVideoForPreview(index: 1)
        let storage = directory.appendingPathComponent("Projects", isDirectory: true)
        let manager = ProjectManager(projectsDirectory: storage, userDefaults: defaults)
        let saved = await manager.saveProject(name: "Real Sony batch", projectState: state, lutManager: library)
        XCTAssertTrue(saved, manager.lastError ?? "Save failed")
        let project = try XCTUnwrap(manager.savedProjects.first)
        manager.toggleFavorite(project)
        state.clearBatchQueue()
        state.setPrimaryLUT(nil)
        state.setSecondaryLUT(nil)
        try FileManager.default.removeItem(at: imports)

        let reloadedManager = ProjectManager(projectsDirectory: storage, userDefaults: defaults)
        XCTAssertTrue(reloadedManager.favoriteProjects.contains(project.id))
        XCTAssertTrue(reloadedManager.recentProjects.contains { $0.projectId == project.id })
        let persisted = try XCTUnwrap(reloadedManager.savedProjects.first)
        let restored = await reloadedManager.loadProject(persisted, into: state, lutManager: library)
        XCTAssertTrue(restored, reloadedManager.lastError ?? "Load failed")
        XCTAssertEqual(state.batchQueue.count, 2)
        XCTAssertEqual(state.secondLUTOpacity, 0.47)
        XCTAssertEqual(state.whiteBalanceValue, 1)
        let restoredOriginal = try XCTUnwrap(state.batchQueue.first?.url)
        let restoredHash = try await Task.detached { try Self.digest(restoredOriginal) }.value
        XCTAssertEqual(restoredHash, sourceHash, "A reopened project must retain the complete original")
        let preview = try await VideoProcessor().generatePreviewAtTime(videoURL: restoredOriginal, timeSeconds: 3,
            settings: .init(videoURLs: [restoredOriginal], primaryLUTURL: state.primaryLUTURL,
                secondaryLUTURL: state.secondaryLUTURL, primaryLUTOpacity: 1, secondaryLUTOpacity: 0.47,
                whiteBalanceAdjustment: 1, useGPUProcessing: true, outputQuality: .low, outputDirectory: directory))
        XCTAssertGreaterThan(preview.size.width, 0)
        await state.startBatchProcessing()
        XCTAssertFalse(state.isBatchProcessing)
        XCTAssertEqual(state.batchQueue.filter { $0.status == .completed }.count, 2, state.batchProcessingStatus)
        XCTAssertEqual(state.batchExportedVideoURLs.count, 2, state.batchProcessingStatus)
        XCTAssertEqual(state.batchProgress, 1)
        var results: [[String: Any]] = []
        for url in state.batchExportedVideoURLs {
            let asset = AVURLAsset(url: url)
            let playable = try await asset.load(.isPlayable)
            let duration = try await asset.load(.duration).seconds
            let tracks = try await asset.loadTracks(withMediaType: .video)
            let size = try await XCTUnwrap(tracks.first).load(.naturalSize)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            XCTAssertTrue(playable)
            XCTAssertEqual(duration, 6.006, accuracy: 0.08)
            XCTAssertEqual(size, CGSize(width: 1280, height: 720))
            XCTAssertEqual(audioTracks.count, 1)
            results.append(["path": url.path, "duration": duration, "width": size.width,
                            "height": size.height, "audioTracks": audioTracks.count])
        }
        let resultDirectory = URL.documentsDirectory.appendingPathComponent("RealMediaResults", isDirectory: true)
        try FileManager.default.createDirectory(at: resultDirectory, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["sourceSHA256": sourceHash, "projectBatchOutputs": results], options: [.prettyPrinted, .sortedKeys])
            .write(to: resultDirectory.appendingPathComponent("project-round-trip.json"), options: .atomic)
        state.clearBatchQueue()
        state.setPrimaryLUT(nil)
        state.setSecondaryLUT(nil)
        let deleted = await reloadedManager.deleteProject(persisted, projectState: state)
        XCTAssertTrue(deleted, reloadedManager.lastError ?? "Delete failed")
        XCTAssertTrue(reloadedManager.favoriteProjects.isEmpty)
        XCTAssertTrue(reloadedManager.recentProjects.isEmpty)
    }
}
