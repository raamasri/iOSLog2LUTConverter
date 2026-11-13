import XCTest
import CoreImage
import UIKit
@testable import iOSLOG2LUTConverter

@MainActor
final class iOSLOG2LUTConverterTests: XCTestCase {
    private func video(_ name: String) -> URL {
        URL(fileURLWithPath: "/test-videos/\(name).mov")
    }

    func testBuiltInLUTsLoadWithoutDuplicates() async throws {
        let manager = LUTManager()
        await manager.loadBuiltInLUTs().value
        XCTAssertFalse(manager.primaryLUTs.isEmpty)
        XCTAssertFalse(manager.secondaryLUTs.isEmpty)
        let luts = manager.primaryLUTs + manager.secondaryLUTs
        XCTAssertEqual(Set(luts.map(\.url)).count, luts.count)
        XCTAssertTrue(luts.allSatisfy { !$0.name.isEmpty && $0.isBuiltIn })
    }

    func testIdentityFilterPreservesImage() throws {
        let filter = try LUTProcessor().createIdentityFilter()
        let input = CIImage(color: CIColor(red: 0.2, green: 0.5, blue: 0.8))
            .cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1))
        filter.setValue(input, forKey: kCIInputImageKey)
        let output = try XCTUnwrap(filter.outputImage)
        let context = CIContext()
        var original = [Float](repeating: 0, count: 4)
        var pixel = [Float](repeating: 0, count: 4)
        context.render(input, toBitmap: &original, rowBytes: 16,
                       bounds: input.extent, format: .RGBAf, colorSpace: nil)
        context.render(output, toBitmap: &pixel, rowBytes: 16,
                       bounds: input.extent, format: .RGBAf, colorSpace: nil)
        for channel in 0..<4 {
            XCTAssertEqual(pixel[channel], original[channel], accuracy: 0.005)
        }
    }

    func testRemovingSelectedLastBatchItemUpdatesPreviewSelection() {
        let state = ProjectState()
        let a = ProjectState.BatchVideoItem(url: video("a"), name: "a")
        let b = ProjectState.BatchVideoItem(url: video("b"), name: "b")
        state.batchQueue = [a, b]
        state.selectedBatchVideoIndex = 1
        state.videoURLs = [b.url]
        state.removeVideoFromBatch(at: 1)
        XCTAssertEqual(state.selectedBatchVideoIndex, 0)
        XCTAssertEqual(state.videoURLs, [a.url])
        state.clearBatchQueue()
    }

    func testRemovingEarlierBatchRowKeepsSelectedVideo() {
        let state = ProjectState()
        let items = ["a", "b", "c"].map { ProjectState.BatchVideoItem(url: video($0), name: $0) }
        state.batchQueue = items
        state.selectedBatchVideoIndex = 1
        state.videoURLs = [items[1].url]
        state.removeVideoFromBatch(at: 0)
        XCTAssertEqual(state.selectedBatchVideoIndex, 0)
        XCTAssertEqual(state.batchQueue[0].id, items[1].id)
        XCTAssertEqual(state.videoURLs, [items[1].url])
    }

    func testReorderingBatchKeepsSelectedVideo() {
        let state = ProjectState()
        let items = ["a", "b", "c"].map { ProjectState.BatchVideoItem(url: video($0), name: $0) }
        state.batchQueue = items
        state.selectedBatchVideoIndex = 1
        state.videoURLs = [items[1].url]
        state.reorderBatchQueue(from: IndexSet(integer: 0), to: 3)
        XCTAssertEqual(state.batchQueue.map(\.name), ["b", "c", "a"])
        XCTAssertEqual(state.selectedBatchVideoIndex, 0)
        XCTAssertEqual(state.videoURLs, [items[1].url])
    }

    func testClearVideosResetsTimelineComparisonAndPendingRender() async {
        let state = ProjectState()
        state.videoURLs = [video("missing")]
        state.videoDuration = 10
        state.currentTime = 5
        state.previewImage = UIImage()
        state.rawPreviewImage = UIImage()
        state.generatePreviewAtTime(5)
        state.clearVideoURLs()
        await Task.yield()
        XCTAssertTrue(state.videoURLs.isEmpty)
        XCTAssertNil(state.previewImage)
        XCTAssertNil(state.rawPreviewImage)
        XCTAssertEqual(state.videoDuration, 0)
        XCTAssertEqual(state.currentTime, 0)
        XCTAssertFalse(state.isPreviewLoading)
        XCTAssertFalse(state.isScrubbing)
    }

    func testQueueCannotBeMutatedDuringExport() {
        let state = ProjectState()
        let a = ProjectState.BatchVideoItem(url: video("a"), name: "a")
        state.batchQueue = [a]
        state.videoURLs = [a.url]
        state.isBatchProcessing = true
        state.removeVideoFromBatch(at: 0)
        state.clearBatchQueue()
        state.addVideoToBatch(video("b"))
        state.replaceProjectVideos([video("replacement")])
        XCTAssertEqual(state.batchQueue.map(\.id), [a.id])
        XCTAssertEqual(state.videoURLs, [a.url])
        XCTAssertFalse(state.isReadyForExport)
    }

    func testVideoWithoutLUTIsValidForWhiteBalanceOrTranscode() {
        let state = ProjectState()
        XCTAssertFalse(state.validateConfiguration().isValid)
        state.videoURLs = [video("a")]
        state.whiteBalanceValue = 2
        XCTAssertTrue(state.validateConfiguration().isValid)
        XCTAssertTrue(state.isReadyForExport)
        XCTAssertEqual(state.formattedWhiteBalance, "6700K")
    }

    func testScrubbingRejectsNonfiniteAndClampsPastLastSample() {
        let state = ProjectState()
        state.videoDuration = 5
        state.currentTime = 2
        state.scrubToTime(.nan)
        XCTAssertEqual(state.currentTime, 2)
        state.scrubToTime(.infinity)
        XCTAssertEqual(state.currentTime, 2)
        state.scrubToTime(5)
        XCTAssertLessThan(state.currentTime, 5)
        XCTAssertGreaterThan(state.currentTime, 4.9)
        state.clearVideoURLs()
    }

    func testRestoringMultipleVideosRestoresBatchAndResetsOldState() {
        let state = ProjectState()
        state.videoDuration = 30
        state.currentTime = 20
        state.previewImage = UIImage()
        let urls = [video("a"), video("b")]
        state.replaceProjectVideos(urls)
        XCTAssertTrue(state.batchMode)
        XCTAssertEqual(state.batchQueue.map(\.url), urls)
        XCTAssertEqual(state.videoURLs, [urls[0]])
        XCTAssertEqual(state.currentTime, 0)
        XCTAssertEqual(state.videoDuration, 0)
        XCTAssertNil(state.previewImage)
        state.clearBatchQueue()
    }
    func testWhiteBalanceOnlyPreviewKeepsScrubbedFrameAndClearsSafely() async throws {
        let source = try await makeVideoFixture(frameCount: 30)
        defer { try? FileManager.default.removeItem(at: source) }
        let state = ProjectState()
        state.addVideoURL(source)
        state.whiteBalanceValue = 10
        state.generatePreviewAtTime(0.4)
        for _ in 0..<200 where state.isPreviewLoading {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(state.isPreviewLoading)
        XCTAssertEqual(state.currentTime, 0.4, accuracy: 0.001)
        let original = try XCTUnwrap(state.rawPreviewImage?.cgImage)
        let graded = try XCTUnwrap(state.previewImage?.cgImage)
        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        var before = [Float](repeating: 0, count: 4)
        var after = [Float](repeating: 0, count: 4)
        context.render(CIImage(cgImage: original), toBitmap: &before, rowBytes: 16,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf, colorSpace: nil)
        context.render(CIImage(cgImage: graded), toBitmap: &after, rowBytes: 16,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf, colorSpace: nil)
        XCTAssertGreaterThan(zip(before.prefix(3), after.prefix(3)).map { abs($0 - $1) }.max() ?? 0, 0.005)
        state.generatePreviewAtTime(0.6)
        await Task.yield()
        state.clearVideoURLs()
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertNil(state.previewImage)
        XCTAssertNil(state.rawPreviewImage)
        XCTAssertFalse(state.isPreviewLoading)
    }

    func testChangingGradeClearsStaleBatchResultsWithoutDeletingExport() throws {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("previous-export-\(UUID().uuidString).mp4")
        try Data([1, 2, 3]).write(to: output)
        defer { try? FileManager.default.removeItem(at: output) }
        let state = ProjectState()
        state.batchMode = true
        var item = ProjectState.BatchVideoItem(url: video("a"), name: "a")
        item.status = .completed
        item.progress = 1
        item.outputURL = output
        state.batchQueue = [item]
        state.batchExportedVideoURLs = [output]
        state.batchProgress = 1
        let revision = state.exportConfigurationVersion
        state.whiteBalanceValue = 1
        XCTAssertGreaterThan(state.exportConfigurationVersion, revision)
        XCTAssertTrue(state.batchExportedVideoURLs.isEmpty)
        XCTAssertEqual(state.batchQueue.first?.status, .pending)
        XCTAssertNil(state.batchQueue.first?.outputURL)
        XCTAssertEqual(state.batchProgress, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path), "Editing must retain prior exported files")
    }

    func testBatchPreviewKeepsResultsButAddingAnotherInputInvalidatesThem() {
        let state = ProjectState()
        state.batchMode = true
        var a = ProjectState.BatchVideoItem(url: video("a"), name: "a")
        var b = ProjectState.BatchVideoItem(url: video("b"), name: "b")
        a.status = .completed
        b.status = .completed
        let output = video("exported")
        a.outputURL = output
        state.batchQueue = [a, b]
        state.batchExportedVideoURLs = [output]
        let revision = state.exportConfigurationVersion
        state.selectBatchVideoForPreview(index: 1)
        XCTAssertEqual(state.exportConfigurationVersion, revision)
        XCTAssertEqual(state.batchExportedVideoURLs, [output])
        state.addVideoToBatch(a.url)
        XCTAssertEqual(state.batchExportedVideoURLs, [output], "Duplicate input attempts must preserve valid exports")
        state.addVideoToBatch(video("c"))
        XCTAssertTrue(state.batchExportedVideoURLs.isEmpty)
        XCTAssertTrue(state.batchQueue.allSatisfy { $0.status == .pending })
        state.clearBatchQueue()
    }

}
