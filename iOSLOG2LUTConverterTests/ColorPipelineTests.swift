import XCTest
import AVFoundation
import CoreImage
import AudioToolbox
@testable import iOSLOG2LUTConverter

// A real, small H.264/AAC asset exercises decoding, orientation and muxing without
// relying on developer-only bundle footage or a Photos library.
func makeVideoFixture(directory: URL = FileManager.default.temporaryDirectory,
                      size: CGSize = CGSize(width: 64, height: 32), frameCount: Int = 6,
                      transform: CGAffineTransform = .identity, withAudio: Bool = false) async throws -> URL {
    let url = directory.appendingPathComponent("fixture-\(UUID().uuidString).mp4")
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let video = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
         AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height)])
    video.transform = transform
    video.expectsMediaDataInRealTime = false
    writer.add(video)
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: Int(size.width), kCVPixelBufferHeightKey as String: Int(size.height),
        kCVPixelBufferIOSurfacePropertiesKey as String: [:]])
    var audio: AVAssetWriterInput?
    var audioFormat: CMAudioFormatDescription?
    if withAudio {
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
             AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 128000])
        input.expectsMediaDataInRealTime = false
        writer.add(input)
        audio = input
        var description = AudioStreamBasicDescription(mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked, mBytesPerPacket: 4,
            mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 2, mBitsPerChannel: 16, mReserved: 0)
        guard CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &description,
            layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil,
            extensions: nil, formatDescriptionOut: &audioFormat) == noErr else { throw FixtureError.failed }
    }
    guard writer.startWriting() else { throw writer.error ?? FixtureError.failed }
    writer.startSession(atSourceTime: .zero)
    let deadline = Date().addingTimeInterval(20)
    var videoIndex = 0
    var audioIndex = 0
    while videoIndex < frameCount || (withAudio && audioIndex < frameCount) {
        guard Date() < deadline, writer.status == .writing else { writer.cancelWriting(); throw writer.error ?? FixtureError.failed }
        if videoIndex < frameCount, video.isReadyForMoreMediaData {
            var pixels: CVPixelBuffer?
            guard let pool = adaptor.pixelBufferPool,
                  CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixels) == kCVReturnSuccess,
                  let pixels else { throw FixtureError.failed }
            CVPixelBufferLockBaseAddress(pixels, [])
            let base = CVPixelBufferGetBaseAddress(pixels)!.assumingMemoryBound(to: UInt8.self)
            let rowBytes = CVPixelBufferGetBytesPerRow(pixels)
            for y in 0..<Int(size.height) {
                for x in 0..<Int(size.width) {
                    let index = y * rowBytes + x * 4
                    base[index] = y < Int(size.height / 2) ? 0 : 200
                    base[index + 1] = 70
                    base[index + 2] = y < Int(size.height / 2) ? 200 : 0
                    base[index + 3] = 255
                }
            }
            CVPixelBufferUnlockBaseAddress(pixels, [])
            guard adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(videoIndex), timescale: 30)) else { throw writer.error ?? FixtureError.failed }
            videoIndex += 1
            if videoIndex == frameCount { video.markAsFinished() }
        }
        if let audio, let audioFormat, audioIndex < frameCount, audio.isReadyForMoreMediaData {
            var block: CMBlockBuffer?
            guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
                blockLength: 1600 * 4, blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
                offsetToData: 0, dataLength: 1600 * 4, flags: 0, blockBufferOut: &block) == noErr,
                  let block else { throw FixtureError.failed }
            guard CMBlockBufferFillDataBytes(with: 0, blockBuffer: block, offsetIntoDestination: 0, dataLength: 1600 * 4) == noErr else { throw FixtureError.failed }
            var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48000),
                presentationTimeStamp: CMTime(value: Int64(audioIndex * 1600), timescale: 48000), decodeTimeStamp: .invalid)
            var bytesPerFrame = 4
            var sample: CMSampleBuffer?
            guard CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: audioFormat,
                sampleCount: 1600, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                sampleSizeEntryCount: 1, sampleSizeArray: &bytesPerFrame, sampleBufferOut: &sample) == noErr,
                  let sample, audio.append(sample) else { throw writer.error ?? FixtureError.failed }
            audioIndex += 1
            if audioIndex == frameCount { audio.markAsFinished() }
        }
        try await Task.sleep(nanoseconds: 1_000_000)
    }
    writer.endSession(atSourceTime: CMTime(value: Int64(frameCount), timescale: 30))
    await writer.finishWriting()
    guard writer.status == .completed else { throw writer.error ?? FixtureError.failed }
    return url
}

private enum FixtureError: Error { case failed }

final class ColorPipelineTests: XCTestCase {
    func test1DLUTKeepsIndependentRGBAChannels() throws {
        let info = try LUTParsingUtils.parseCubeFile("LUT_1D_SIZE\t  2 # size\n0.1 0.2 0.3\n0.7 0.8 0.9 # end\n")
        let cube = try LUTParsingUtils.convert1DTo3D(info)
        let values = cube.data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        XCTAssertEqual(Array(values.prefix(4)), [0.1, 0.2, 0.3, 1])
        XCTAssertEqual(Array(values.suffix(4)), [0.7, 0.8, 0.9, 1])
        XCTAssertEqual(Array(values[4..<8]), [0.7, 0.2, 0.3, 1])
    }

    func testMalformedLUTsFailWithoutUnsafeAllocation() {
        for content in ["LUT_3D_SIZE 0", "LUT_3D_SIZE -2", "LUT_3D_SIZE 99999999999999",
                        "LUT_1D_SIZE 1\n0 0 0", "LUT_1D_SIZE 2\nNaN 0 0\n1 1 1",
                        "LUT_1D_SIZE 2\n0 0\n1 1 1", "0 0 0", "LUT_1D_SIZE 2\nLUT_3D_SIZE 2",
                        "DOMAIN_MIN 1 1 1\nDOMAIN_MAX 0 0 0\nLUT_1D_SIZE 2\n0 0 0\n1 1 1",
                        "DOMAIN_MIN -3e38 -3e38 -3e38\nDOMAIN_MAX 3e38 3e38 3e38\nLUT_1D_SIZE 2\n0 0 0\n1 1 1"] {
            XCTAssertThrowsError(try LUTParsingUtils.parseCubeFile(content), content)
        }
    }

    func testDomainMetadataPreservedThrough1DConversion() throws {
        let info = try LUTParsingUtils.parseCubeFile("DOMAIN_MIN -1 -2 -3\nDOMAIN_MAX 1 2 3\nLUT_1D_SIZE 2\n0 0 0\n1 1 1")
        let cube = try LUTParsingUtils.convert1DTo3D(info)
        XCTAssertEqual(cube.domainMin, [-1, -2, -3])
        XCTAssertEqual(cube.domainMax, [1, 2, 3])
    }

    func testInputDomainAndOpacityAffectRenderedPixels() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("domain-\(UUID().uuidString).cube")
        try "DOMAIN_MIN 0 0 0\nDOMAIN_MAX 2 2 2\nLUT_3D_SIZE 2\n0 0 0\n1 0 0\n0 1 0\n1 1 0\n0 0 1\n1 0 1\n0 1 1\n1 1 1".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let processor = LUTProcessor()
        var settings = LUTProcessor.LUTSettings(primaryLUTURL: url)
        try processor.loadLUTFilters(settings: settings)
        let input = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1))
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        func red(_ image: CIImage) -> Float {
            var pixel: [Float] = [0, 0, 0, 0]
            context.render(image, toBitmap: &pixel, rowBytes: 16, bounds: image.extent, format: .RGBAf, colorSpace: nil)
            return pixel[0]
        }
        XCTAssertEqual(red(try XCTUnwrap(processor.processImage(input, settings: settings))), 0.25, accuracy: 0.01)
        settings.primaryLUTOpacity = 0
        XCTAssertEqual(red(try XCTUnwrap(processor.processImage(input, settings: settings))), 0.5, accuracy: 0.01)
    }

    func testQualityCapsRespectPortraitAndDoNotUnnecessarilyShrink() {
        XCTAssertEqual(LUTProcessor.OutputQuality.low.outputSize(from: CGSize(width: 1080, height: 1920)), CGSize(width: 720, height: 1280))
        XCTAssertEqual(LUTProcessor.OutputQuality.low.outputSize(from: CGSize(width: 640, height: 480)), CGSize(width: 640, height: 480))
        XCTAssertEqual(LUTProcessor.OutputQuality.medium.outputSize(from: CGSize(width: 1920, height: 1080)), CGSize(width: 1920, height: 1080))
        XCTAssertEqual(LUTProcessor.OutputQuality.high.outputSize(from: CGSize(width: CGFloat.infinity, height: 1)), .zero)
    }

    func testExportPreservesPortraitOrientationAndAudio() async throws {
        let source = try await makeVideoFixture(frameCount: 12, transform: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 32, ty: 0), withAudio: true)
        let output = source.deletingLastPathComponent().appendingPathComponent("export-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: output) }
        try await LUTProcessor().processVideo(source, settings: .init(), outputURL: output)
        let asset = AVURLAsset(url: output)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let video = try XCTUnwrap(videoTracks.first)
        let size = try await video.load(.naturalSize)
        XCTAssertEqual(size, CGSize(width: 32, height: 64))
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let audio = try XCTUnwrap(audioTracks.first)
        let audioRange = try await audio.load(.timeRange)
        XCTAssertGreaterThanOrEqual(audioRange.duration.seconds, 0.35)
        let duration = try await asset.load(.duration)
        XCTAssertEqual(duration.seconds, 0.4, accuracy: 0.08)
    }

    func testPortraitContentMatchesAVFoundationOrientation() async throws {
        let source = try await makeVideoFixture(transform: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 32, ty: 0))
        let output = source.deletingLastPathComponent().appendingPathComponent("orientation-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: output) }
        func reference(_ url: URL) async throws -> CIImage {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            let image = try await generator.image(at: .zero).image
            return CIImage(cgImage: image)
        }
        let expected = try await reference(source)
        let processor = LUTProcessor()
        let preview = try await processor.generatePreviewAtTime(from: source, timeSeconds: 0, settings: .init())
        try await processor.processVideo(source, settings: .init(), outputURL: output)
        let exported = try await reference(output)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        func isRed(_ image: CIImage, fraction: CGFloat) -> Bool {
            var pixel: [UInt8] = [0, 0, 0, 0]
            let point = CGRect(x: floor(image.extent.width * fraction), y: floor(image.extent.height / 2), width: 1, height: 1)
            context.render(image, toBitmap: &pixel, rowBytes: 4, bounds: point, format: .RGBA8, colorSpace: nil)
            return pixel[0] > pixel[2]
        }
        XCTAssertNotEqual(isRed(expected, fraction: 0.25), isRed(expected, fraction: 0.75), "The fixture must have distinct red and blue sides")
        for fraction: CGFloat in [0.25, 0.75] {
            XCTAssertEqual(isRed(preview, fraction: fraction), isRed(expected, fraction: fraction), "Preview rotated in the wrong direction")
            XCTAssertEqual(isRed(exported, fraction: fraction), isRed(expected, fraction: fraction), "Export rotated in the wrong direction")
        }
    }

    func testPreviewClampsNonfiniteAndEndTimes() async throws {
        let source = try await makeVideoFixture(frameCount: 3)
        defer { try? FileManager.default.removeItem(at: source) }
        let processor = LUTProcessor()
        let first = try await processor.generatePreviewAtTime(from: source, timeSeconds: .nan, settings: .init())
        let last = try await processor.generatePreviewAtTime(from: source, timeSeconds: 1000, settings: .init())
        XCTAssertEqual(first.extent.size, CGSize(width: 64, height: 32))
        XCTAssertEqual(last.extent.size, first.extent.size)
    }

    @MainActor
    func testPassthroughBatchUsesUniqueOutputsAndReportsCompletion() async throws {
        let source = try await makeVideoFixture(frameCount: 3)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("batch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: directory) }
        let processor = VideoProcessor()
        let config = VideoProcessor.ProcessingConfig(videoURLs: [source, source], primaryLUTURL: nil,
            secondaryLUTURL: nil, primaryLUTOpacity: 1, secondaryLUTOpacity: 1, whiteBalanceAdjustment: 0,
            useGPUProcessing: true, outputQuality: .low, outputDirectory: directory)
        await processor.processVideos(config: config)
        XCTAssertNil(processor.lastError)
        XCTAssertFalse(processor.isExporting)
        XCTAssertEqual(processor.exportProgress, 1)
        XCTAssertEqual(processor.exportedVideoURLs.count, 2)
        XCTAssertEqual(Set(processor.exportedVideoURLs).count, 2)
        XCTAssertTrue(processor.exportedVideoURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }

    func testActiveExportCancellationRemovesWrittenPartialFile() async throws {
        let source = try await makeVideoFixture(size: CGSize(width: 640, height: 360), frameCount: 180)
        let output = source.deletingLastPathComponent().appendingPathComponent("active-cancel-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: output) }
        let processor = LUTProcessor()
        let task = Task { try await processor.processVideo(source, settings: .init(), outputURL: output) }
        defer { task.cancel() }
        var writerStarted = false
        for _ in 0..<5000 {
            if let attributes = try? FileManager.default.attributesOfItem(atPath: output.path),
               let bytes = attributes[.size] as? NSNumber, bytes.int64Value > 0 {
                writerStarted = true
                break
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        guard writerStarted else {
            task.cancel()
            _ = try? await task.value
            return XCTFail("The writer must start before testing active cancellation")
        }
        processor.cancelProcessing()
        do { try await task.value; XCTFail("An active cancelled export must not report success") }
        catch is CancellationError { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testCancelledExportRemovesPartialFile() async throws {
        let source = try await makeVideoFixture(frameCount: 60)
        let output = source.deletingLastPathComponent().appendingPathComponent("cancel-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: output) }
        let task = Task { try await LUTProcessor().processVideo(source, settings: .init(), outputURL: output) }
        task.cancel()
        do { try await task.value; XCTFail("Cancelled work must not report success") }
        catch is CancellationError { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }
}
