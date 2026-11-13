import Foundation
import Combine
import CoreImage
import CoreVideo
import AVFoundation
import AudioToolbox
import VideoToolbox

// Cube files contain RGB triples; Core Image requires an RGBA float for every entry.
enum LUTParsingUtils {
    struct LUTInfo {
        let data: Data
        let is1D: Bool
        let dimension: Int
        var domainMin: [Float] = [0, 0, 0]
        var domainMax: [Float] = [1, 1, 1]
    }

    static func parseLUTFile(_ url: URL) throws -> LUTInfo {
        guard url.pathExtension.lowercased() == "cube" else {
            throw LUTProcessor.LUTProcessingError.invalidLUTFile("Only .cube files are supported")
        }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        return try parseCubeFile(String(contentsOf: url, encoding: .utf8))
    }

    static func parseCubeFile(_ content: String) throws -> LUTInfo {
        var dimension: Int?
        var is1D = false
        var domainMin: [Float] = [0, 0, 0]
        var domainMax: [Float] = [1, 1, 1]
        var entries: [Float] = []

        func invalid(_ message: String) -> LUTProcessor.LUTProcessingError { .invalidLUTFile(message) }
        for (lineIndex, line) in content.components(separatedBy: .newlines).enumerated() {
            let tokens = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
                .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{feff}")))
                .split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard let first = tokens.first else { continue }
            switch first {
            case "TITLE": continue
            case "LUT_1D_SIZE", "LUT_3D_SIZE":
                guard dimension == nil, tokens.count == 2, let size = Int(tokens[1]),
                      size >= 2, size <= (first == "LUT_1D_SIZE" ? 65536 : 128) else {
                    throw invalid("Invalid or unsupported LUT size on line \(lineIndex + 1). Use one 1D size (2–65536) or 3D size (2–128).")
                }
                guard entries.isEmpty else { throw invalid("LUT size must precede data") }
                dimension = size
                is1D = first == "LUT_1D_SIZE"
            case "DOMAIN_MIN", "DOMAIN_MAX":
                let values = tokens.dropFirst().compactMap(Float.init)
                guard values.count == 3, tokens.count == 4, values.allSatisfy(\.isFinite), entries.isEmpty else {
                    throw invalid("Invalid input domain on line \(lineIndex + 1)")
                }
                if first == "DOMAIN_MIN" { domainMin = values } else { domainMax = values }
            case "LUT_1D_INPUT_RANGE", "LUT_3D_INPUT_RANGE":
                let values = tokens.dropFirst().compactMap(Float.init)
                guard tokens.count == 3, values.count == 2, values.allSatisfy(\.isFinite), entries.isEmpty else {
                    throw invalid("Invalid input range on line \(lineIndex + 1)")
                }
                domainMin = Array(repeating: values[0], count: 3)
                domainMax = Array(repeating: values[1], count: 3)
            default:
                guard let size = dimension else { throw invalid("Missing LUT size before data on line \(lineIndex + 1)") }
                let values = tokens.compactMap(Float.init)
                guard tokens.count == 3, values.count == 3, values.allSatisfy(\.isFinite) else {
                    throw invalid("Expected three finite RGB values on line \(lineIndex + 1)")
                }
                let expected = (is1D ? size : size * size * size) * 4
                guard entries.count < expected else { throw invalid("Too many LUT entries") }
                entries.append(contentsOf: values)
                entries.append(1)
            }
        }
        guard let size = dimension else { throw invalid("Missing LUT_1D_SIZE or LUT_3D_SIZE") }
        guard zip(domainMin, domainMax).allSatisfy({ minimum, maximum in
            let width = maximum - minimum
            return width > 0 && width.isFinite && (1 / width).isFinite
        }) else { throw invalid("DOMAIN_MAX must exceed DOMAIN_MIN by a finite, usable range for every channel") }
        let expectedCount = (is1D ? size : size * size * size) * 4
        guard entries.count == expectedCount else {
            throw invalid("Expected \(expectedCount / 4) RGB entries, found \(entries.count / 4)")
        }
        let data = entries.withUnsafeBytes { Data($0) }
        return LUTInfo(data: data, is1D: is1D, dimension: size, domainMin: domainMin, domainMax: domainMax)
    }

    static func convert1DTo3D(_ lutInfo: LUTInfo) throws -> LUTInfo {
        guard lutInfo.is1D, lutInfo.dimension >= 2,
              lutInfo.data.count == lutInfo.dimension * 4 * MemoryLayout<Float>.size else {
            throw LUTProcessor.LUTProcessingError.invalidLUTFile("Invalid 1D LUT data")
        }
        let floatArray = lutInfo.data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        let size = min(64, lutInfo.dimension)
        var cube: [Float] = []
        cube.reserveCapacity(size * size * size * 4)
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    cube.append(interpolate1D(value: Float(r) / Float(size - 1), lutData: floatArray, lutSize: lutInfo.dimension, channel: 0))
                    cube.append(interpolate1D(value: Float(g) / Float(size - 1), lutData: floatArray, lutSize: lutInfo.dimension, channel: 1))
                    cube.append(interpolate1D(value: Float(b) / Float(size - 1), lutData: floatArray, lutSize: lutInfo.dimension, channel: 2))
                    cube.append(1)
                }
            }
        }
        return LUTInfo(data: cube.withUnsafeBytes { Data($0) }, is1D: false, dimension: size,
                       domainMin: lutInfo.domainMin, domainMax: lutInfo.domainMax)
    }

    static func interpolate1D(value: Float, lutData: [Float], lutSize: Int, channel: Int) -> Float {
        guard value.isFinite, lutSize >= 2, (0..<3).contains(channel), lutData.count == lutSize * 4 else { return 0 }
        let position = max(0, min(1, value)) * Float(lutSize - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, lutSize - 1)
        let fraction = position - Float(lower)
        // The parser has already inserted alpha, so the entry stride is four.
        return lutData[lower * 4 + channel] * (1 - fraction) + lutData[upper * 4 + channel] * fraction
    }
}

// Decoding is deliberately independent from encoding and audio. Some valid camera
// codecs (notably H.264 4:2:2 10-bit) expose tracks on iOS but fail on the first
// AVAssetReader sample; use the bundled software decoder for those files.
struct DecodedVideoFrame {
    let pixelBuffer: CVPixelBuffer
    let presentationTime: CMTime
}

final class VideoFrameReader {
    private var reader: AVAssetReader?
    private var output: AVAssetReaderTrackOutput?
    private var pendingFrame: DecodedVideoFrame?
    #if os(iOS) && ENABLE_SOFTWARE_VIDEO_DECODER
    private var software: SoftwareVideoDecoder?
    #endif

    init(url: URL, asset: AVAsset, track: AVAssetTrack, pixelFormat: OSType, startTime: CMTime = .zero) throws {
        let nativeReader = try AVAssetReader(asset: asset)
        let nativeOutput = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: pixelFormat])
        var nativeError: Error?
        if nativeReader.canAdd(nativeOutput) {
            nativeReader.add(nativeOutput)
            if startTime > .zero { nativeReader.timeRange = CMTimeRange(start: startTime, duration: .positiveInfinity) }
            if nativeReader.startReading(), let sample = nativeOutput.copyNextSampleBuffer(),
               let pixels = CMSampleBufferGetImageBuffer(sample) {
                reader = nativeReader
                output = nativeOutput
                pendingFrame = DecodedVideoFrame(pixelBuffer: pixels, presentationTime: CMSampleBufferGetPresentationTimeStamp(sample))
                return
            }
            nativeError = nativeReader.error
        }
        nativeReader.cancelReading()
        try Task.checkCancellation()
        #if os(iOS) && ENABLE_SOFTWARE_VIDEO_DECODER
        do {
            let fallback = try SoftwareVideoDecoder(url: url, pixelFormat: pixelFormat)
            if startTime > .zero { try fallback.seek(to: startTime) }
            guard let frame = try fallback.readFrame() else {
                throw LUTProcessor.LUTProcessingError.videoProcessingFailed("No video frames could be decoded")
            }
            software = fallback
            pendingFrame = DecodedVideoFrame(pixelBuffer: frame.pixelBuffer, presentationTime: frame.presentationTime)
            print("Using compatible camera decoder: \(url.lastPathComponent)")
            return
        } catch {
            throw LUTProcessor.LUTProcessingError.videoProcessingFailed("Cannot decode this video. \(error.localizedDescription)")
        }
        #else
        throw nativeError ?? LUTProcessor.LUTProcessingError.videoProcessingFailed("No video frame is available at this time")
        #endif
    }

    func readFrame() throws -> DecodedVideoFrame? {
        try Task.checkCancellation()
        if let frame = pendingFrame { pendingFrame = nil; return frame }
        #if os(iOS) && ENABLE_SOFTWARE_VIDEO_DECODER
        if let software {
            guard let frame = try software.readFrame() else { return nil }
            return DecodedVideoFrame(pixelBuffer: frame.pixelBuffer, presentationTime: frame.presentationTime)
        }
        #endif
        guard let reader, let output else { return nil }
        if let sample = output.copyNextSampleBuffer(), let pixels = CMSampleBufferGetImageBuffer(sample) {
            return DecodedVideoFrame(pixelBuffer: pixels, presentationTime: CMSampleBufferGetPresentationTimeStamp(sample))
        }
        if reader.status == .failed { throw reader.error ?? LUTProcessor.LUTProcessingError.videoProcessingFailed("The video decoder stopped") }
        return nil
    }

    func cancel() { reader?.cancelReading() }
    deinit { cancel() }
}

class LUTProcessor: ObservableObject {
    // .cube values index the encoded RGB signal. The default linear-light working
    // space changes those indices before lookup, so use the same unmanaged pipeline
    // for decoded preview pixels and exported frames.
    private let context = CIContext(options: [.workingColorSpace: NSNull(), .cacheIntermediates: false])
    private struct LoadedLUT {
        let filter: CIFilter
        let info: LUTParsingUtils.LUTInfo
    }
    private var primaryLUT: LoadedLUT?
    private var secondaryLUT: LoadedLUT?
    private let filterLock = NSLock()
    private let cancellationLock = NSLock()
    private var cancelled = false

    @Published var isProcessing = false
    @Published var processingProgress: Double = 0
    @Published var processingStatus = "Ready"
    @Published var lastError: LUTProcessingError?

    struct LUTSettings {
        var primaryLUTURL: URL?
        var secondaryLUTURL: URL?
        var primaryLUTOpacity: Float = 1
        var secondaryLUTOpacity: Float = 1
        var whiteBalanceAdjustment: Float = 0
        var useGPUProcessing = true
        var outputQuality: OutputQuality = .high
    }

    enum OutputQuality {
        case low, medium, high, maximum
        var compressionQuality: Float {
            switch self { case .low: return 0.3; case .medium: return 0.5; case .high: return 0.7; case .maximum: return 1 }
        }
        var bitRate: Int {
            switch self { case .low: return 2_000_000; case .medium: return 5_000_000; case .high: return 10_000_000; case .maximum: return 50_000_000 }
        }
        var resolutionScale: CGFloat { 1 }
        var maxResolution: CGSize? {
            switch self { case .low: return CGSize(width: 1280, height: 720); case .medium: return CGSize(width: 1920, height: 1080); case .high, .maximum: return nil }
        }
        var codec: AVVideoCodecType { self == .maximum ? .hevc : .h264 }
        var exportPreset: String {
            switch self { case .low: return AVAssetExportPreset1280x720; case .medium: return AVAssetExportPreset1920x1080; case .high: return AVAssetExportPresetHighestQuality; case .maximum: return AVAssetExportPresetHEVCHighestQuality }
        }
        var profileLevel: String {
            switch self { case .low: return AVVideoProfileLevelH264BaselineAutoLevel; case .medium: return AVVideoProfileLevelH264MainAutoLevel; case .high: return AVVideoProfileLevelH264HighAutoLevel; case .maximum: return kVTProfileLevel_HEVC_Main10_AutoLevel as String }
        }
        var keyFrameInterval: Int { self == .maximum ? 15 : 30 }
        var description: String {
            switch self { case .low: return "Low (720p max, smaller files)"; case .medium: return "Medium (1080p max)"; case .high: return "High (Original resolution)"; case .maximum: return "Maximum (Original resolution, 10-bit HEVC SDR)" }
        }
        func outputSize(from inputSize: CGSize) -> CGSize {
            guard inputSize.width.isFinite, inputSize.height.isFinite, inputSize.width > 0, inputSize.height > 0 else { return .zero }
            var scale: CGFloat = 1
            if let limit = maxResolution {
                // Apply the landscape cap to the long edge for portrait footage as well.
                scale = min(1, min(max(limit.width, limit.height) / max(inputSize.width, inputSize.height),
                                   min(limit.width, limit.height) / min(inputSize.width, inputSize.height)))
            }
            return CGSize(width: max(2, floor(inputSize.width * scale / 2) * 2),
                          height: max(2, floor(inputSize.height * scale / 2) * 2))
        }
    }

    enum LUTProcessingError: LocalizedError {
        case invalidLUTFile(String), videoProcessingFailed(String), exportFailed(String), insufficientStorage, unsupportedFormat
        var errorDescription: String? {
            switch self {
            case .invalidLUTFile(let message): return "Invalid LUT file: \(message)"
            case .videoProcessingFailed(let message): return "Video processing failed: \(message)"
            case .exportFailed(let message): return "Export failed: \(message)"
            case .insufficientStorage: return "Insufficient storage space for export"
            case .unsupportedFormat: return "Unsupported video format"
            }
        }
    }

    func loadLUTFilters(settings: LUTSettings) throws {
        // Build both first, so a failed selection never leaves a half-updated pipeline.
        let primary = try settings.primaryLUTURL.map(loadLUT)
        let secondary = try settings.secondaryLUTURL.map(loadLUT)
        filterLock.lock()
        primaryLUT = primary
        secondaryLUT = secondary
        filterLock.unlock()
    }

    private func loadLUT(_ url: URL) throws -> LoadedLUT {
        var info = try LUTParsingUtils.parseLUTFile(url)
        if info.is1D { info = try LUTParsingUtils.convert1DTo3D(info) }
        guard let filter = CIFilter(name: "CIColorCube") else {
            throw LUTProcessingError.invalidLUTFile("Could not create color cube filter")
        }
        filter.setValue(info.data, forKey: "inputCubeData")
        filter.setValue(info.dimension, forKey: "inputCubeDimension")
        filter.setValue(false, forKey: "inputExtrapolate")
        return LoadedLUT(filter: filter, info: info)
    }

    func createIdentityFilter() throws -> CIFilter {
        let content = "LUT_3D_SIZE 2\n0 0 0\n1 0 0\n0 1 0\n1 1 0\n0 0 1\n1 0 1\n0 1 1\n1 1 1\n"
        let info = try LUTParsingUtils.parseCubeFile(content)
        guard let filter = CIFilter(name: "CIColorCube") else { throw LUTProcessingError.invalidLUTFile("Could not create identity filter") }
        filter.setValue(info.dimension, forKey: "inputCubeDimension")
        filter.setValue(info.data, forKey: "inputCubeData")
        return filter
    }

    func processImage(_ image: CIImage, settings: LUTSettings) -> CIImage? {
        filterLock.lock()
        defer { filterLock.unlock() }
        var result = image
        if let primaryLUT { result = apply(primaryLUT, to: result, opacity: settings.primaryLUTOpacity) }
        if settings.whiteBalanceAdjustment.isFinite, settings.whiteBalanceAdjustment != 0 {
            let adjustment = min(10, max(-10, settings.whiteBalanceAdjustment))
            result = result.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: CGFloat(6500 + adjustment * 100), y: 0)
            ])
        }
        if let secondaryLUT { result = apply(secondaryLUT, to: result, opacity: settings.secondaryLUTOpacity) }
        return result.cropped(to: image.extent)
    }

    func processImageDirect(_ image: CIImage, settings: LUTSettings) -> CIImage? { processImage(image, settings: settings) }

    private func apply(_ lut: LoadedLUT, to image: CIImage, opacity: Float) -> CIImage {
        let opacity = opacity.isFinite ? min(1, max(0, opacity)) : 1
        guard opacity > 0 else { return image }
        let scale = zip(lut.info.domainMin, lut.info.domainMax).map { 1 / ($1 - $0) }
        let normalized = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: CGFloat(scale[0]), y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: CGFloat(scale[1]), z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(scale[2]), w: 0),
            "inputBiasVector": CIVector(x: CGFloat(-lut.info.domainMin[0] * scale[0]), y: CGFloat(-lut.info.domainMin[1] * scale[1]), z: CGFloat(-lut.info.domainMin[2] * scale[2]), w: 0)
        ])
        lut.filter.setValue(normalized, forKey: kCIInputImageKey)
        guard let output = lut.filter.outputImage else { return image }
        guard opacity < 1 else { return output }
        return image.applyingFilter("CIDissolveTransition", parameters: ["inputTargetImage": output, "inputTime": opacity])
    }

    func cancelProcessing() {
        cancellationLock.lock()
        cancelled = true
        cancellationLock.unlock()
    }

    private func checkCancellation() throws {
        cancellationLock.lock()
        let stopped = cancelled
        cancellationLock.unlock()
        if stopped || Task.isCancelled { throw CancellationError() }
    }

    private func resetCancellation() {
        cancellationLock.lock()
        cancelled = false
        cancellationLock.unlock()
    }

    func processVideo(_ videoURL: URL, settings: LUTSettings, outputURL: URL) async throws {
        resetCancellation()
        try Task.checkCancellation()
        updateProgress(0)
        updateStatus("Starting video processing…")
        // A dedicated pipeline prevents preview changes from changing frames midway through export.
        let pipeline = LUTProcessor()
        try pipeline.loadLUTFilters(settings: settings)
        try await withTaskCancellationHandler {
            try await processVideoFrames(videoURL, settings: settings, outputURL: outputURL, pipeline: pipeline)
        } onCancel: { self.cancelProcessing() }
        await MainActor.run {
            self.processingProgress = 1
            self.processingStatus = "Video processing completed"
        }
    }

    private func processVideoFrames(_ videoURL: URL, settings: LUTSettings, outputURL: URL, pipeline: LUTProcessor) async throws {
        guard videoURL.standardizedFileURL != outputURL.standardizedFileURL,
              !FileManager.default.fileExists(atPath: outputURL.path) else {
            throw LUTProcessingError.exportFailed("The output file already exists. Choose a new filename.")
        }
        let asset = AVURLAsset(url: videoURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw LUTProcessingError.unsupportedFormat }
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let frameRate = try await track.load(.nominalFrameRate)
        let sourceTimeScale = try await track.load(.naturalTimeScale)
        let duration = try await asset.load(.duration)
        let bounds = CGRect(origin: .zero, size: size).applying(transform).standardized
        let imageTransform = Self.displayTransform(for: size, preferredTransform: transform)
        let outputSize = settings.outputQuality.outputSize(from: bounds.size)
        guard outputSize.width > 0, outputSize.height > 0, duration.seconds.isFinite, duration.seconds > 0 else {
            throw LUTProcessingError.videoProcessingFailed("The video has invalid dimensions or duration")
        }
        try checkCancellation()
        let pixelFormat = settings.outputQuality == .maximum ? kCVPixelFormatType_64RGBAHalf : kCVPixelFormatType_32BGRA
        let videoReader = try VideoFrameReader(url: videoURL, asset: asset, track: track, pixelFormat: pixelFormat)
        var audioReader: AVAssetReader?
        defer { videoReader.cancel(); audioReader?.cancelReading() }
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        // The default 600 Hz scale rounds NTSC/VFR timestamps. Preserve the track's
        // rational timing rather than introducing jitter or changing its frame rate.
        if sourceTimeScale > 0 { writer.movieTimeScale = sourceTimeScale }
        var completed = false
        defer {
            if !completed {
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: outputURL)
            }
        }
        var compression: [String: Any] = [AVVideoAverageBitRateKey: settings.outputQuality.bitRate,
                                          AVVideoExpectedSourceFrameRateKey: frameRate.isFinite && frameRate > 0 ? frameRate : 30,
                                          AVVideoMaxKeyFrameIntervalKey: settings.outputQuality.keyFrameInterval]
        if settings.outputQuality.codec == .hevc {
            compression[AVVideoProfileLevelKey] = kVTProfileLevel_HEVC_Main10_AutoLevel as String
        }
        if settings.outputQuality.codec == .h264 {
            compression[AVVideoProfileLevelKey] = settings.outputQuality.profileLevel
            // Baseline profile does not support CABAC entropy coding.
            if settings.outputQuality != .low { compression[AVVideoH264EntropyModeKey] = AVVideoH264EntropyModeCABAC }
        }
        let videoSettings: [String: Any] = [AVVideoCodecKey: settings.outputQuality.codec,
                                           AVVideoWidthKey: Int(outputSize.width), AVVideoHeightKey: Int(outputSize.height),
                                           AVVideoCompressionPropertiesKey: compression,
                                           AVVideoColorPropertiesKey: [
                                            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                                            AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                                            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]]
        guard writer.canApply(outputSettings: videoSettings, forMediaType: .video) else { throw LUTProcessingError.unsupportedFormat }
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        if sourceTimeScale > 0 { videoInput.mediaTimeScale = sourceTimeScale }
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else { throw LUTProcessingError.unsupportedFormat }
        writer.add(videoInput)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
            kCVPixelBufferWidthKey as String: Int(outputSize.width), kCVPixelBufferHeightKey as String: Int(outputSize.height),
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ])
        var audioOutput: AVAssetReaderTrackOutput?
        var audioInput: AVAssetWriterInput?
        if let audio = try await asset.loadTracks(withMediaType: .audio).first {
            // Decode and re-encode so MOV PCM and other non-MP4 audio codecs remain playable.
            let output = AVAssetReaderTrackOutput(track: audio, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM,
                 AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16,
                 AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false])
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
                 AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192000])
            input.expectsMediaDataInRealTime = false
            let reader = try AVAssetReader(asset: asset)
            guard reader.canAdd(output), writer.canAdd(input) else { throw LUTProcessingError.exportFailed("Cannot preserve the video's audio") }
            reader.add(output)
            audioReader = reader
            writer.add(input)
            audioOutput = output
            audioInput = input
        }
        guard writer.startWriting() else { throw LUTProcessingError.exportFailed(writer.error?.localizedDescription ?? "Cannot start writer") }
        writer.startSession(atSourceTime: .zero)
        if let audioReader, !audioReader.startReading() {
            throw LUTProcessingError.videoProcessingFailed(audioReader.error?.localizedDescription ?? "Cannot decode audio")
        }
        var videoFinished = false
        var audioFinished = audioOutput == nil
        var frameCount = 0
        while !videoFinished || !audioFinished {
            try checkCancellation()
            guard writer.status == .writing else { throw LUTProcessingError.exportFailed(writer.error?.localizedDescription ?? "The writer stopped") }
            if let audioReader, audioReader.status == .failed {
                throw LUTProcessingError.videoProcessingFailed(audioReader.error?.localizedDescription ?? "The audio reader failed")
            }
            var advanced = false
            if !videoFinished && videoInput.isReadyForMoreMediaData {
                try autoreleasepool {
                    if let frame = try videoReader.readFrame() {
                        let pixels = frame.pixelBuffer
                        guard let pool = adaptor.pixelBufferPool else {
                            throw LUTProcessingError.videoProcessingFailed("Cannot decode video frame")
                        }
                        let source = CIImage(cvPixelBuffer: pixels).transformed(by: imageTransform)
                        guard let graded = pipeline.processImage(source, settings: settings) else {
                            throw LUTProcessingError.videoProcessingFailed("Cannot apply color settings")
                        }
                        let image = graded.transformed(by: CGAffineTransform(scaleX: outputSize.width / bounds.width, y: outputSize.height / bounds.height))
                        var result: CVPixelBuffer?
                        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &result) == kCVReturnSuccess, let result else {
                            throw LUTProcessingError.videoProcessingFailed("Cannot allocate a video frame")
                        }
                        context.render(image, to: result)
                        let time = frame.presentationTime
                        guard adaptor.append(result, withPresentationTime: time) else {
                            throw LUTProcessingError.exportFailed(writer.error?.localizedDescription ?? "Cannot write video frame")
                        }
                        frameCount += 1
                        if frameCount % 5 == 0 { updateProgress(min(0.99, max(0, time.seconds / duration.seconds))) }
                    } else {
                        videoFinished = true
                        videoInput.markAsFinished()
                    }
                }
                advanced = true
            }
            // Feed both tracks together. Reading all video first can block an interleaved writer;
            // copying audio while its input is busy silently discards samples.
            if !audioFinished, let audioInput, let audioOutput, audioInput.isReadyForMoreMediaData {
                if let sample = audioOutput.copyNextSampleBuffer() {
                    guard audioInput.append(sample) else { throw LUTProcessingError.exportFailed(writer.error?.localizedDescription ?? "Cannot write audio sample") }
                } else {
                    audioFinished = true
                    audioInput.markAsFinished()
                }
                advanced = true
            }
            if !advanced { try await Task.sleep(nanoseconds: 5_000_000) }
        }
        try checkCancellation()
        guard frameCount > 0 else { throw LUTProcessingError.videoProcessingFailed("The video contained no readable frames") }
        await writer.finishWriting()
        try checkCancellation()
        guard writer.status == .completed else { throw LUTProcessingError.exportFailed(writer.error?.localizedDescription ?? "The writer did not finish") }
        completed = true
    }

    func generatePreview(from videoURL: URL, settings: LUTSettings) async throws -> CIImage {
        try await generatePreviewAtTime(from: videoURL, timeSeconds: 0, settings: settings)
    }

    func generatePreviewAtTime(from videoURL: URL, timeSeconds: Double, settings: LUTSettings) async throws -> CIImage {
        try Task.checkCancellation()
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0,
              let track = try await asset.loadTracks(withMediaType: .video).first else { throw LUTProcessingError.unsupportedFormat }
        let frameRate = try await track.load(.nominalFrameRate)
        let minimumFrameDuration = try await track.load(.minFrameDuration).seconds
        let frameInterval = minimumFrameDuration.isFinite && minimumFrameDuration > 0 ? minimumFrameDuration :
            (frameRate.isFinite && frameRate > 0 ? 1 / Double(frameRate) : 1.0 / 30)
        let sourceTimeScale = try await track.load(.naturalTimeScale)
        let requested = timeSeconds.isFinite ? timeSeconds : 0
        let seconds = min(max(0, requested), max(0, duration - frameInterval))
        // CMTime(seconds:) truncates some decimal frame boundaries (e.g. 2.002)
        // one tick early. Round explicitly so scrubbing selects the requested frame.
        let timeScale = sourceTimeScale > 0 ? sourceTimeScale : 60000
        let ticks = (seconds * Double(timeScale)).rounded()
        guard ticks >= 0, ticks < Double(Int64.max) else { throw LUTProcessingError.unsupportedFormat }
        let time = CMTime(value: Int64(ticks), timescale: timeScale)
        let pixelFormat = settings.outputQuality == .maximum ? kCVPixelFormatType_64RGBAHalf : kCVPixelFormatType_32BGRA
        let reader = try VideoFrameReader(url: videoURL, asset: asset, track: track, pixelFormat: pixelFormat, startTime: time)
        defer { reader.cancel() }
        guard let frame = try reader.readFrame() else { throw LUTProcessingError.videoProcessingFailed("No preview frame is available at this time") }
        let pixels = frame.pixelBuffer
        let transform = try await track.load(.preferredTransform)
        let size = try await track.load(.naturalSize)
        let transformed = CIImage(cvPixelBuffer: pixels).transformed(by: Self.displayTransform(for: size, preferredTransform: transform))
        let bounds = transformed.extent
        let scale = min(1, 1280 / max(bounds.width, bounds.height))
        let source = transformed.transformed(by: CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        try Task.checkCancellation()
        // Local filters keep overlapping scrub requests independent.
        let pipeline = LUTProcessor()
        try pipeline.loadLUTFilters(settings: settings)
        return pipeline.processImage(source, settings: settings) ?? source
    }

    private static func displayTransform(for size: CGSize, preferredTransform: CGAffineTransform) -> CGAffineTransform {
        // Track transforms use top-left video coordinates; Core Image uses bottom-left
        // coordinates. Conjugating with vertical flips preserves the intended rotation
        // direction and mirrored orientations, then places the result at the origin.
        let bounds = CGRect(origin: .zero, size: size).applying(preferredTransform).standardized
        let sourceFlip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: size.height)
        let destinationFlip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: bounds.height)
        return sourceFlip.concatenating(preferredTransform)
            .concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
            .concatenating(destinationFlip)
    }

    private func updateStatus(_ message: String) { DispatchQueue.main.async { self.processingStatus = message } }
    private func updateProgress(_ progress: Double) { DispatchQueue.main.async { self.processingProgress = progress } }
    func resetProgress() {
        DispatchQueue.main.async { self.processingProgress = 0; self.processingStatus = "Ready"; self.lastError = nil }
    }
}
