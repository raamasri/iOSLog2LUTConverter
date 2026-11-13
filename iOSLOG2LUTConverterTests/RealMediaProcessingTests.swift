import XCTest
import AVFoundation
import CoreImage
import UIKit
@testable import iOSLOG2LUTConverter

// Opt-in integration suite: copy the user's unchanged media/LUTs to the test host's
// Documents/RealMediaFixtures. A missing fixture directory skips ordinary CI runs;
// a staged but incomplete directory is a test failure. Results remain inspectable
// under Documents/RealMediaResults and never overwrite the supplied media.
final class RealMediaProcessingTests: XCTestCase {
    private func fixtureDirectory() throws -> URL {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RealMediaFixtures", isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else {
            throw XCTSkip("Stage the user's real files in Documents/RealMediaFixtures to run this integration suite")
        }
        for name in ["rsiv5362 ORIGINAL SLOG3CINE.MP4", "1_SGamut3CineSLog3_To_LC-709.cube", "M31 - Rec.709.cube"] {
            guard FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path) else {
                XCTFail("Required real-media fixture is missing: \(name)")
                throw RealMediaFailure.invalid("Incomplete real-media fixtures")
            }
        }
        return directory
    }

    private func resultDirectory() throws -> URL {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RealMediaResults", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @MainActor
    private func exportAndInspect(_ quality: LUTProcessor.OutputQuality, name: String) async throws {
        let fixtures = try fixtureDirectory()
        let source = fixtures.appendingPathComponent("rsiv5362 ORIGINAL SLOG3CINE.MP4")
        let destination = try resultDirectory().appendingPathComponent(name, isDirectory: true)
        let processor = VideoProcessor()
        let previousIdleSetting = UIApplication.shared.isIdleTimerDisabled
        let config = VideoProcessor.ProcessingConfig(videoURLs: [source],
            primaryLUTURL: fixtures.appendingPathComponent("1_SGamut3CineSLog3_To_LC-709.cube"),
            secondaryLUTURL: fixtures.appendingPathComponent("M31 - Rec.709.cube"),
            primaryLUTOpacity: 1, secondaryLUTOpacity: 0.47, whiteBalanceAdjustment: 0,
            useGPUProcessing: true, outputQuality: quality, outputDirectory: destination)
        await processor.processVideos(config: config)
        XCTAssertNil(processor.lastError, processor.lastError?.localizedDescription ?? "")
        XCTAssertFalse(processor.isExporting)
        XCTAssertEqual(processor.exportProgress, 1)
        XCTAssertEqual(UIApplication.shared.isIdleTimerDisabled, previousIdleSetting, "Export must restore the previous idle-timer setting")
        let output = try XCTUnwrap(processor.exportedVideoURLs.first, "The entire original must export successfully")
        let summary = try await inspectRealMedia(output)
        let expectedSize = quality.outputSize(from: CGSize(width: 3840, height: 2160))
        XCTAssertEqual(summary.width, Int(expectedSize.width))
        XCTAssertEqual(summary.height, Int(expectedSize.height))
        XCTAssertEqual(summary.frames, 180, "Every source frame must survive processing")
        XCTAssertTrue(summary.increasingPTS)
        XCTAssertEqual(summary.firstPTS, 0, accuracy: 0.001)
        XCTAssertEqual(summary.lastPTS, 179 * 1001.0 / 30000, accuracy: 0.002)
        XCTAssertEqual(summary.frameRate, 30000.0 / 1001, accuracy: 0.002)
        XCTAssertEqual(summary.duration, 6.006, accuracy: 0.04)
        XCTAssertGreaterThanOrEqual(summary.audioSamples, 288288 - 1024, "Export must retain the complete soundtrack")
        XCTAssertEqual(summary.audioDuration, 6.006, accuracy: 0.04)
        XCTAssertEqual(summary.videoCodec, quality == .maximum ? "hvc1" : "avc1")
        if quality == .maximum { XCTAssertEqual(summary.bitsPerComponent, 10, "Maximum must encode a true Main10 stream") }
        try JSONEncoder().encode(summary).write(to: destination.appendingPathComponent("summary.json"))
        print("REAL_MEDIA_RESULT \(name): \(output.path)")
    }

    @MainActor func testFullOriginalLowQuality() async throws { try await exportAndInspect(.low, name: "low") }
    @MainActor func testFullOriginalMediumQuality() async throws { try await exportAndInspect(.medium, name: "medium") }
    @MainActor func testFullOriginalHighQuality() async throws { try await exportAndInspect(.high, name: "high") }
    @MainActor func testFullOriginalMaximumHEVCQuality() async throws { try await exportAndInspect(.maximum, name: "maximum") }

    @MainActor
    func testEverySuppliedInputFullyExportsAndDecodes() async throws {
        let fixtures = try fixtureDirectory()
        let inputs = try FileManager.default.contentsOfDirectory(at: fixtures, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "mp4" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertEqual(inputs.count, 9, "Stage the original and all eight existing conversions")
        let destination = try resultDirectory().appendingPathComponent("input-matrix", isDirectory: true)
        var summaries: [RealMediaSummary] = []
        for source in inputs {
            let isOriginal = source.lastPathComponent == "rsiv5362 ORIGINAL SLOG3CINE.MP4"
            let sourceAudioTracks = try await AVURLAsset(url: source).loadTracks(withMediaType: .audio)
            let processor = VideoProcessor()
            let config = VideoProcessor.ProcessingConfig(videoURLs: [source],
                primaryLUTURL: isOriginal ? fixtures.appendingPathComponent("1_SGamut3CineSLog3_To_LC-709.cube") : nil,
                secondaryLUTURL: isOriginal ? fixtures.appendingPathComponent("M31 - Rec.709.cube") : nil,
                primaryLUTOpacity: 1, secondaryLUTOpacity: 0.47, whiteBalanceAdjustment: 0,
                useGPUProcessing: true, outputQuality: .low, outputDirectory: destination)
            await processor.processVideos(config: config)
            XCTAssertNil(processor.lastError, "\(source.lastPathComponent): \(processor.lastError?.localizedDescription ?? "")")
            let output = try XCTUnwrap(processor.exportedVideoURLs.first, "Failed to export \(source.lastPathComponent)")
            let summary = try await inspectRealMedia(output)
            XCTAssertEqual(summary.frames, 180, source.lastPathComponent)
            XCTAssertEqual(summary.width, 1280)
            XCTAssertEqual(summary.height, 720)
            XCTAssertEqual(summary.frameRate, 30000.0 / 1001, accuracy: 0.002)
            XCTAssertEqual(summary.duration, 6.006, accuracy: 0.04)
            if sourceAudioTracks.isEmpty { XCTAssertEqual(summary.audioSamples, 0, "Do not invent audio for the silent source") }
            else {
                XCTAssertGreaterThanOrEqual(summary.audioSamples, 288288 - 1024, "Preserve all source audio")
                XCTAssertEqual(summary.audioDuration, 6.006, accuracy: 0.04)
            }
            summaries.append(summary)
            print("REAL_MEDIA_INPUT_RESULT \(source.lastPathComponent): \(output.path)")
        }
        try JSONEncoder().encode(summaries).write(to: destination.appendingPathComponent("summary.json"))
    }

    func testFrameBoundaryAndEndPreviewMatchSequentialDecode() async throws {
        let fixtures = try fixtureDirectory()
        let source = fixtures.appendingPathComponent("rsiv5362 ORIGINAL SLOG3CINE.MP4")
        let settings = LUTProcessor.LUTSettings(primaryLUTURL: fixtures.appendingPathComponent("1_SGamut3CineSLog3_To_LC-709.cube"),
            secondaryLUTURL: fixtures.appendingPathComponent("M31 - Rec.709.cube"), secondaryLUTOpacity: 0.47)
        let asset = AVURLAsset(url: source)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let reader = try VideoFrameReader(url: source, asset: asset, track: track, pixelFormat: kCVPixelFormatType_32BGRA)
        defer { reader.cancel() }
        var frames: [Int: CIImage] = [:]
        for index in 0..<180 {
            try autoreleasepool {
                guard let frame = try reader.readFrame() else {
                    throw RealMediaFailure.invalid("Original sequential decoding stopped at frame \(index)")
                }
                if index == 60 || index == 179 { frames[index] = CIImage(cvPixelBuffer: frame.pixelBuffer) }
            }
        }
        let processor = LUTProcessor()
        let expectedProcessor = LUTProcessor()
        try expectedProcessor.loadLUTFilters(settings: settings)
        let context = CIContext(options: [.workingColorSpace: NSNull(), .cacheIntermediates: false])
        func bytes(_ image: CIImage) -> [UInt8] {
            var result = [UInt8](repeating: 0, count: 1280 * 720 * 4)
            context.render(image, toBitmap: &result, rowBytes: 1280 * 4, bounds: CGRect(x: 0, y: 0, width: 1280, height: 720), format: .RGBA8, colorSpace: nil)
            return result
        }
        for (index, time) in [(60, 2.002), (179, 6.006)] {
            let decoded = try XCTUnwrap(frames[index]).transformed(by: CGAffineTransform(scaleX: 1.0 / 3, y: 1.0 / 3))
            let expected = try XCTUnwrap(expectedProcessor.processImage(decoded, settings: settings))
            let preview = try await processor.generatePreviewAtTime(from: source, timeSeconds: time, settings: settings)
            let a = bytes(expected)
            let b = bytes(preview)
            let difference = zip(a, b).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) } / Double(a.count)
            XCTAssertLessThan(difference, 0.1, "Seek at \(time)s must select source frame \(index), not the preceding frame")
        }
    }

    func testFullOriginalPreviewEndpointsAndLUTOpacity() async throws {
        let fixtures = try fixtureDirectory()
        let source = fixtures.appendingPathComponent("rsiv5362 ORIGINAL SLOG3CINE.MP4")
        let destination = try resultDirectory()
        let processor = LUTProcessor()
        var settings = LUTProcessor.LUTSettings(primaryLUTURL: fixtures.appendingPathComponent("1_SGamut3CineSLog3_To_LC-709.cube"),
            secondaryLUTURL: fixtures.appendingPathComponent("M31 - Rec.709.cube"), secondaryLUTOpacity: 0.47)
        let context = CIContext(options: [.workingColorSpace: NSNull(), .cacheIntermediates: false])
        for (name, time) in [("start", 0.0), ("middle", 3.003), ("end", 6.006)] {
            let preview = try await processor.generatePreviewAtTime(from: source, timeSeconds: time, settings: settings)
            XCTAssertEqual(preview.extent.width, 1280, accuracy: 1)
            XCTAssertEqual(preview.extent.height, 720, accuracy: 1)
            let cg = try XCTUnwrap(context.createCGImage(preview, from: preview.extent))
            let png = try XCTUnwrap(UIImage(cgImage: cg).pngData())
            try png.write(to: destination.appendingPathComponent("preview-\(name).png"))
        }
        settings.secondaryLUTOpacity = 0
        let primaryOnly = try await processor.generatePreviewAtTime(from: source, timeSeconds: 2.002, settings: settings)
        settings.secondaryLUTOpacity = 1
        let creative = try await processor.generatePreviewAtTime(from: source, timeSeconds: 2.002, settings: settings)
        func bytes(_ image: CIImage) -> [UInt8] {
            let small = image.transformed(by: CGAffineTransform(scaleX: 1.0 / 16, y: 1.0 / 16))
            let width = Int(small.extent.width.rounded(.up))
            let height = Int(small.extent.height.rounded(.up))
            var result = [UInt8](repeating: 0, count: width * height * 4)
            context.render(small, toBitmap: &result, rowBytes: width * 4, bounds: CGRect(x: 0, y: 0, width: width, height: height), format: .RGBA8, colorSpace: nil)
            return result
        }
        let a = bytes(primaryOnly)
        let b = bytes(creative)
        XCTAssertEqual(a.count, b.count)
        let difference = zip(a, b).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) } / Double(a.count)
        XCTAssertGreaterThan(difference, 1, "The creative LUT must actually alter the real frame")
    }
}

private enum RealMediaFailure: Error { case invalid(String) }
private struct RealMediaSummary: Codable {
    let path: String
    let width: Int
    let height: Int
    let duration: Double
    let frameRate: Double
    let frames: Int
    let firstPTS: Double
    let lastPTS: Double
    let increasingPTS: Bool
    let videoCodec: String
    let bitsPerComponent: Int?
    let audioSamples: Int
    let audioDuration: Double
}

private func inspectRealMedia(_ url: URL) async throws -> RealMediaSummary {
    let asset = AVURLAsset(url: url)
    let tracks = try await asset.loadTracks(withMediaType: .video)
    guard let track = tracks.first else { throw RealMediaFailure.invalid("Missing output video track") }
    let size = try await track.load(.naturalSize)
    let frameRate = try await track.load(.nominalFrameRate)
    let duration = try await asset.load(.duration).seconds
    let formats = try await track.load(.formatDescriptions)
    let code = formats.first.map { CMFormatDescriptionGetMediaSubType($0) } ?? 0
    let codec = String(bytes: [(code >> 24), (code >> 16), (code >> 8), code].map { UInt8($0 & 255) }, encoding: .ascii) ?? "unknown"
    var bitsPerComponent: Int?
    if let format = formats.first, let extensions = CMFormatDescriptionGetExtensions(format) as? [String: Any] {
        bitsPerComponent = (extensions[kCMFormatDescriptionExtension_BitsPerComponent as String] as? NSNumber)?.intValue
        if bitsPerComponent == nil,
           let atoms = extensions[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms as String] as? [String: Any],
           let configuration = atoms["hvcC"] as? Data, configuration.count > 18 {
            // HEVCDecoderConfigurationRecord explicitly stores bitDepthLumaMinus8.
            bitsPerComponent = 8 + Int(configuration[17] & 7)
        }
    }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    reader.add(output)
    guard reader.startReading() else { throw reader.error ?? RealMediaFailure.invalid("Video decoding could not start") }
    var frames = 0
    var firstPTS = 0.0
    var lastPTS = 0.0
    var increasing = true
    while true {
        let found = autoreleasepool { () -> Bool in
            guard let sample = output.copyNextSampleBuffer() else { return false }
            guard CMSampleBufferGetImageBuffer(sample) != nil else { return false }
            let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            if frames == 0 { firstPTS = pts } else if pts <= lastPTS { increasing = false }
            lastPTS = pts
            frames += 1
            return true
        }
        if !found { break }
    }
    guard reader.status == .completed else { throw reader.error ?? RealMediaFailure.invalid("Full video decoding failed") }
    let audioTracks = try await asset.loadTracks(withMediaType: .audio)
    guard let audio = audioTracks.first else {
        return RealMediaSummary(path: url.path, width: Int(size.width), height: Int(size.height), duration: duration,
            frameRate: Double(frameRate), frames: frames, firstPTS: firstPTS, lastPTS: lastPTS,
            increasingPTS: increasing, videoCodec: codec, bitsPerComponent: bitsPerComponent, audioSamples: 0, audioDuration: 0)
    }
    let audioDuration = try await audio.load(.timeRange).duration.seconds
    let audioReader = try AVAssetReader(asset: asset)
    let audioOutput = AVAssetReaderTrackOutput(track: audio, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false])
    audioReader.add(audioOutput)
    guard audioReader.startReading() else { throw audioReader.error ?? RealMediaFailure.invalid("Audio decoding could not start") }
    var samples = 0
    while true {
        let count = autoreleasepool { () -> Int? in
            guard let sample = audioOutput.copyNextSampleBuffer() else { return nil }
            return CMSampleBufferGetNumSamples(sample)
        }
        guard let count else { break }
        samples += count
    }
    guard audioReader.status == .completed else { throw audioReader.error ?? RealMediaFailure.invalid("Full audio decoding failed") }
    return RealMediaSummary(path: url.path, width: Int(size.width), height: Int(size.height), duration: duration,
        frameRate: Double(frameRate), frames: frames, firstPTS: firstPTS, lastPTS: lastPTS,
        increasingPTS: increasing, videoCodec: codec, bitsPerComponent: bitsPerComponent, audioSamples: samples, audioDuration: audioDuration)
}
