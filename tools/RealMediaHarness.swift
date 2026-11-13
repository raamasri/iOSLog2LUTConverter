// Compile with Services/LUTProcessor.swift; runs the production processing path on supplied media.
// swiftc -parse-as-library -target arm64-apple-macos15.0 <LUTProcessor.swift> <this file> -o <harness>
import Foundation
import AVFoundation
import CoreImage
import ImageIO

@main
struct RealMediaHarness {
    static func fourCC(_ value: FourCharCode) -> String {
        String(bytes: [(value >> 24), (value >> 16), (value >> 8), value].map { UInt8($0 & 255) }, encoding: .ascii) ?? "unknown"
    }

    static func inspect(_ url: URL) async throws -> [String: Any] {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw Failure.message("No video track") }
        let size = try await track.load(.naturalSize)
        let rate = try await track.load(.nominalFrameRate)
        let formats = try await track.load(.formatDescriptions)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? Failure.message("Cannot decode video") }
        var frames = 0
        var firstTime = Double.nan
        var lastTime = 0.0
        var monotonicallyIncreasing = true
        while true {
            let gotFrame = autoreleasepool { () -> Bool in
                guard let sample = output.copyNextSampleBuffer() else { return false }
                let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                if frames == 0 { firstTime = time } else if time <= lastTime { monotonicallyIncreasing = false }
                lastTime = time
                frames += 1
                return CMSampleBufferGetImageBuffer(sample) != nil
            }
            if !gotFrame { break }
        }
        guard reader.status == .completed, frames > 0 else { throw reader.error ?? Failure.message("Video full decode incomplete: \(reader.status.rawValue), \(frames) frames") }
        var result: [String: Any] = ["path": url.path, "duration": duration, "width": size.width, "height": size.height,
            "nominalFrameRate": rate, "videoFramesDecoded": frames, "firstVideoPTS": firstTime, "lastVideoPTS": lastTime,
            "videoTimestampsIncreasing": monotonicallyIncreasing, "videoCodec": formats.first.map { fourCC(CMFormatDescriptionGetMediaSubType($0)) } ?? "unknown"]
        if let format = formats.first, let extensions = CMFormatDescriptionGetExtensions(format) as? [String: Any] {
            if let bits = extensions[kCMFormatDescriptionExtension_BitsPerComponent as String] as? NSNumber {
                result["bitsPerComponent"] = bits
            } else if let atoms = extensions[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms as String] as? [String: Any],
                      let configuration = atoms["hvcC"] as? Data, configuration.count > 18 {
                result["bitsPerComponent"] = 8 + Int(configuration[17] & 7)
            }
        }
        if let audio = try await asset.loadTracks(withMediaType: .audio).first {
            let audioReader = try AVAssetReader(asset: asset)
            let audioOutput = AVAssetReaderTrackOutput(track: audio, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false])
            audioReader.add(audioOutput)
            guard audioReader.startReading() else { throw audioReader.error ?? Failure.message("Cannot decode audio") }
            var samples = 0
            while true {
                let count = autoreleasepool { () -> Int? in
                    guard let sample = audioOutput.copyNextSampleBuffer() else { return nil }
                    return CMSampleBufferGetNumSamples(sample)
                }
                guard let count else { break }
                samples += count
            }
            guard audioReader.status == .completed else { throw audioReader.error ?? Failure.message("Audio full decode incomplete") }
            result["audioSamplesDecoded"] = samples
            result["audioDecodedSeconds"] = Double(samples) / 48000
            result["audioTrackDuration"] = try await audio.load(.timeRange).duration.seconds
        } else { result["audioSamplesDecoded"] = 0 }
        result["bytes"] = try FileManager.default.attributesOfItem(atPath: url.path)[.size]
        return result
    }

    static func savePNG(_ image: CIImage, context: CIContext, url: URL) throws {
        guard let cg = context.createCGImage(image, from: image.extent),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw Failure.message("Cannot render diagnostic image")
        }
        CGImageDestinationAddImage(destination, cg, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure.message("Cannot save diagnostic image") }
    }

    static func diagnosticFrame(_ source: URL, time: Double) async throws -> CIImage {
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw Failure.message("Missing video") }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        reader.timeRange = CMTimeRange(start: CMTime(value: Int64((time * 30000).rounded()), timescale: 30000), duration: CMTime(seconds: 1, preferredTimescale: 30000))
        guard reader.startReading() else { throw reader.error ?? Failure.message("Diagnostic reader failed") }
        defer { reader.cancelReading() }
        guard let sample = output.copyNextSampleBuffer(), let pixels = CMSampleBufferGetImageBuffer(sample) else { throw reader.error ?? Failure.message("No diagnostic frame") }
        return CIImage(cvPixelBuffer: pixels)
    }

    static func writeJSON(_ value: Any, to url: URL) throws {
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: url)
    }

    static func main() async throws {
        guard CommandLine.arguments.count == 3 else { throw Failure.message("Usage: harness <fixture directory> <output directory>") }
        let fixtures = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let destination = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let source = fixtures.appendingPathComponent("rsiv5362 ORIGINAL SLOG3CINE.MP4")
        let primary = fixtures.appendingPathComponent("1_SGamut3CineSLog3_To_LC-709.cube")
        let secondary = fixtures.appendingPathComponent("M31 - Rec.709.cube")
        var report: [[String: Any]] = []
        print("Inspecting complete original…")
        fflush(stdout)
        report.append(try await inspect(source))
        try writeJSON(report, to: destination.appendingPathComponent("report.json"))
        let context = CIContext(options: [.workingColorSpace: NSNull(), .cacheIntermediates: false])
        let processor = LUTProcessor()
        let settings = LUTProcessor.LUTSettings(primaryLUTURL: primary, secondaryLUTURL: secondary,
            primaryLUTOpacity: 1, secondaryLUTOpacity: 0.47, whiteBalanceAdjustment: 0, useGPUProcessing: true, outputQuality: .high)
        for (frame, time) in [(0, 0.0), (60, 2.002)] {
            let raw = try await diagnosticFrame(source, time: time)
            try savePNG(raw, context: context, url: destination.appendingPathComponent("raw-frame\(frame).png"))
            for opacity: Float in [0, 0.35, 1] {
                var diagnosticSettings = settings
                diagnosticSettings.secondaryLUTOpacity = opacity
                let diagnosticProcessor = LUTProcessor()
                try diagnosticProcessor.loadLUTFilters(settings: diagnosticSettings)
                guard let graded = diagnosticProcessor.processImage(raw, settings: diagnosticSettings) else { throw Failure.message("Cannot apply diagnostic LUTs") }
                try savePNG(graded, context: context, url: destination.appendingPathComponent("primary-m31-\(Int(opacity * 100))-frame\(frame).png"))
            }
            var primaryOnly = settings
            primaryOnly.secondaryLUTURL = nil
            let primaryProcessor = LUTProcessor()
            try primaryProcessor.loadLUTFilters(settings: primaryOnly)
            try savePNG(primaryProcessor.processImage(raw, settings: primaryOnly)!, context: context,
                url: destination.appendingPathComponent("primary-only-frame\(frame).png"))
        }
        for (name, time) in [("start", 0.0), ("middle", 3.003), ("end", 6.006)] {
            let image = try await processor.generatePreviewAtTime(from: source, timeSeconds: time, settings: settings)
            guard let cg = context.createCGImage(image, from: image.extent),
                  let png = CGImageDestinationCreateWithURL(destination.appendingPathComponent("preview-\(name).png") as CFURL, "public.png" as CFString, 1, nil) else {
                throw Failure.message("Cannot render preview")
            }
            CGImageDestinationAddImage(png, cg, nil)
            guard CGImageDestinationFinalize(png) else { throw Failure.message("Cannot save preview") }
        }
        for (name, quality) in [("low", LUTProcessor.OutputQuality.low), ("medium", .medium), ("high", .high), ("maximum", .maximum)] {
            var configuration = settings
            configuration.outputQuality = quality
            let output = destination.appendingPathComponent("sony-primary-m31-47-\(name).mp4")
            let started = Date()
            print("Starting full \(name) export…")
            fflush(stdout)
            do {
                try await processor.processVideo(source, settings: configuration, outputURL: output)
                var record = try await inspect(output)
                record["quality"] = name
                record["processingAndVerificationSeconds"] = Date().timeIntervalSince(started)
                report.append(record)
                print("PASS \(name): \(record)")
            } catch {
                report.append(["quality": name, "error": String(describing: error), "elapsedSeconds": Date().timeIntervalSince(started)])
                print("FAIL \(name): \(error)")
            }
            try writeJSON(report, to: destination.appendingPathComponent("report.json"))
            fflush(stdout)
        }
    }

    enum Failure: Error { case message(String) }
}
