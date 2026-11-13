import XCTest
import AVFoundation
import CoreVideo
@testable import iOSLOG2LUTConverter

#if os(iOS)
/// Stage the generated neutral-ramp fixture under Documents/PrecisionFixtures.
/// Ordinary CI skips these tests when the optional fixture is absent.
final class SoftwareDecoderAcceptanceTests: XCTestCase {
    private func fixtureURL() throws -> URL {
        let directory = URL.documentsDirectory.appendingPathComponent("PrecisionFixtures", isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else {
            throw XCTSkip("Generate and stage PrecisionFixtures to run software decoder precision acceptance.")
        }
        let source = directory.appendingPathComponent("neutral-ramp-10bit-high422.mp4")
        guard FileManager.default.fileExists(atPath: source.path) else {
            XCTFail("Staged precision fixture directory is incomplete")
            throw PrecisionFailure.invalid("Missing neutral 10-bit ramp")
        }
        return source
    }

    private func redSamples(_ buffer: CVPixelBuffer) throws -> [Float] {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer))
        let width = CVPixelBufferGetWidth(buffer)
        let row = base.advanced(by: (CVPixelBufferGetHeight(buffer) / 2) * CVPixelBufferGetBytesPerRow(buffer))
        switch CVPixelBufferGetPixelFormatType(buffer) {
        case kCVPixelFormatType_64RGBAHalf:
            let pixels = row.assumingMemoryBound(to: UInt16.self)
            return (0..<width).map { Float(Float16(bitPattern: pixels[$0 * 4])) }
        case kCVPixelFormatType_32BGRA:
            let pixels = row.assumingMemoryBound(to: UInt8.self)
            return (0..<width).map { Float(pixels[$0 * 4 + 2]) / 255 }
        default:
            throw PrecisionFailure.invalid("Unexpected decoded pixel format")
        }
    }

    func testSoftwareHalfDecodeRetainsMoreThanEightBitPrecision() throws {
        let source = try fixtureURL()
        let halfDecoder = try SoftwareVideoDecoder(url: source, pixelFormat: kCVPixelFormatType_64RGBAHalf)
        let halfFrame = try XCTUnwrap(halfDecoder.readFrame())
        let halfSamples = try redSamples(halfFrame.pixelBuffer)
        let byteDecoder = try SoftwareVideoDecoder(url: source, pixelFormat: kCVPixelFormatType_32BGRA)
        let byteFrame = try XCTUnwrap(byteDecoder.readFrame())
        let byteSamples = try redSamples(byteFrame.pixelBuffer)
        let halfLevels = Set(halfSamples).count
        let byteLevels = Set(byteSamples).count
        let offByteGrid = halfSamples.filter { abs($0 * 255 - ($0 * 255).rounded()) > 0.1 }.count
        XCTAssertEqual(halfSamples[0], 0, accuracy: 0.00001, "Limited-range black must normalize to zero.")
        XCTAssertEqual(halfSamples[512], 0.5, accuracy: 0.0005, "Limited-range midpoint must retain its signal value.")
        XCTAssertEqual(halfSamples[1023], 1, accuracy: 0.00001, "Limited-range white must normalize to one.")
        XCTAssertGreaterThan(halfLevels, 700, "The 877-level ramp must not be reduced to an 8-bit decode.")
        XCTAssertLessThanOrEqual(byteLevels, 256)
        XCTAssertGreaterThan(offByteGrid, 500, "Half samples must carry meaningful values between the 8-bit grid.")
        XCTAssertEqual(halfFrame.presentationTime.seconds, 0, accuracy: 0.000001)
        print("SOFTWARE_PRECISION halfLevels=\(halfLevels) byteLevels=\(byteLevels) offByteGrid=\(offByteGrid)")
    }

    @MainActor
    func testMaximumOutputRetainsDecodedRampPrecisionAndMain10Profile() async throws {
        let source = try fixtureURL()
        let directory = URL.documentsDirectory.appendingPathComponent("PrecisionResults", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = directory.appendingPathComponent("maximum-ramp-\(UUID().uuidString).mp4")
        let settings = LUTProcessor.LUTSettings(primaryLUTURL: nil, secondaryLUTURL: nil, outputQuality: .maximum)
        try await LUTProcessor().processVideo(source, settings: settings, outputURL: output)
        let asset = AVURLAsset(url: output)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let formats = try await track.load(.formatDescriptions)
        let format = try XCTUnwrap(formats.first)
        let extensions = try XCTUnwrap(CMFormatDescriptionGetExtensions(format) as? [String: Any])
        let atoms = try XCTUnwrap(extensions[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms as String] as? [String: Any])
        let configuration = try XCTUnwrap(atoms["hvcC"] as? Data)
        XCTAssertGreaterThan(configuration.count, 18)
        guard configuration.count > 18 else { return }
        XCTAssertEqual(8 + Int(configuration[17] & 7), 10, "The encoder must produce Main10 luma.")
        XCTAssertEqual(8 + Int(configuration[18] & 7), 10, "The encoder must produce Main10 chroma.")

        // Inspect the decoded native 10-bit luma, not BGRA8 or just the codec flag.
        let reader = try AVAssetReader(asset: asset)
        let decoded = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
        ])
        XCTAssertTrue(reader.canAdd(decoded))
        reader.add(decoded)
        XCTAssertTrue(reader.startReading(), reader.error?.localizedDescription ?? "")
        let first = try XCTUnwrap(decoded.copyNextSampleBuffer(), reader.error?.localizedDescription ?? "No decoded Main10 frame")
        let pixels = try XCTUnwrap(CMSampleBufferGetImageBuffer(first))
        XCTAssertEqual(CVPixelBufferGetPixelFormatType(pixels), kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange)
        let luma = try lumaSamples(pixels)
        let levels = Set(luma).count
        let expected = (0..<luma.count).map { 64 + Int((876.0 * Double($0) / Double(luma.count - 1)).rounded(.down)) }
        let meanError = zip(luma, expected).map { abs(Double($0.0) - Double($0.1)) }.reduce(0, +) / Double(luma.count)
        XCTAssertGreaterThan(levels, 700, "A 10-bit container around an 8-bit ramp is insufficient.")
        XCTAssertLessThan(meanError, 1.5, "The output must retain the source ramp's luma values.")
        var frames = 1
        while decoded.copyNextSampleBuffer() != nil { frames += 1 }
        XCTAssertEqual(reader.status, .completed, reader.error?.localizedDescription ?? "")
        XCTAssertEqual(frames, 30)
        let summary: [String: Any] = ["output": output.path, "codedBits": 10,
                                     "decodedUniqueLumaLevels": levels, "meanLumaErrorIn10BitCodes": meanError,
                                     "frames": frames]
        try JSONSerialization.data(withJSONObject: summary, options: .prettyPrinted)
            .write(to: directory.appendingPathComponent("precision-summary.json"), options: .atomic)
        print("MAXIMUM_PRECISION levels=\(levels) meanError=\(meanError) output=\(output.path)")
    }

    private func lumaSamples(_ buffer: CVPixelBuffer) throws -> [Int] {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        XCTAssertTrue(CVPixelBufferIsPlanar(buffer))
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddressOfPlane(buffer, 0))
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let row = base.advanced(by: (CVPixelBufferGetHeightOfPlane(buffer, 0) / 2) * CVPixelBufferGetBytesPerRowOfPlane(buffer, 0))
        let values = row.assumingMemoryBound(to: UInt16.self)
        // P010-style Core Video pixels store each 10-bit code in the high bits.
        return (0..<width).map { Int(values[$0] >> 6) }
    }

    func testExactSeekAndEndFallbackKeepRationalTimestamps() throws {
        let decoder = try SoftwareVideoDecoder(url: fixtureURL(), pixelFormat: kCVPixelFormatType_32BGRA)
        try decoder.seek(to: CMTime(value: 15, timescale: 30))
        XCTAssertEqual(try XCTUnwrap(decoder.readFrame()).presentationTime.seconds, 0.5, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(decoder.readFrame()).presentationTime.seconds, 16.0 / 30, accuracy: 0.000001)
        // A time in the final frame's duration must return that last frame at EOF.
        try decoder.seek(to: CMTime(value: 1, timescale: 1))
        XCTAssertEqual(try XCTUnwrap(decoder.readFrame()).presentationTime.seconds, 29.0 / 30, accuracy: 0.000001)
        XCTAssertNil(try decoder.readFrame())
    }

    func testIndependentSoftwareDecodersReadConcurrently() async throws {
        let source = try fixtureURL()
        func decode(_ format: OSType) async throws -> Int {
            try await Task.detached {
                let decoder = try SoftwareVideoDecoder(url: source, pixelFormat: format)
                var count = 0
                var previous = -Double.infinity
                while let frame = try decoder.readFrame() {
                    guard frame.presentationTime.seconds > previous else {
                        throw PrecisionFailure.invalid("Presentation timestamps must increase")
                    }
                    previous = frame.presentationTime.seconds
                    count += 1
                }
                return count
            }.value
        }
        async let half = decode(kCVPixelFormatType_64RGBAHalf)
        async let byte = decode(kCVPixelFormatType_32BGRA)
        let counts = try await (half, byte)
        XCTAssertEqual(counts.0, 30)
        XCTAssertEqual(counts.1, 30)
    }

    func testCancelledTaskDoesNotDecodeAnotherFrame() async throws {
        let decoder = try SoftwareVideoDecoder(url: fixtureURL(), pixelFormat: kCVPixelFormatType_64RGBAHalf)
        let gate = DispatchSemaphore(value: 0)
        let task = Task.detached {
            gate.wait()
            return try decoder.readFrame()
        }
        task.cancel()
        gate.signal()
        do {
            _ = try await task.value
            XCTFail("Cancelled reads must throw before decoding")
        } catch is CancellationError {
            // Expected. No shared decoder state was consumed by cancellation.
        }
        XCTAssertEqual(try XCTUnwrap(decoder.readFrame()).presentationTime.seconds, 0, accuracy: 0.000001)
    }
}

private enum PrecisionFailure: Error { case invalid(String) }
#endif
