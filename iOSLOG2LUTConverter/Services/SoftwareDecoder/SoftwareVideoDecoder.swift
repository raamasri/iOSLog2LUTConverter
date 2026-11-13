#if os(iOS) && ENABLE_SOFTWARE_VIDEO_DECODER
import Foundation
import CoreMedia
import CoreVideo

struct SoftwareVideoFrame {
    let pixelBuffer: CVPixelBuffer
    let presentationTime: CMTime
}

/// The fallback for H.264 profiles unavailable from the platform's native decoder.
/// Instances are used serially by the video processor; separate instances serve previews.
final class SoftwareVideoDecoder {
    private let implementation: FFmpegVideoDecoder

    init(url: URL, pixelFormat: OSType) throws {
        try Task.checkCancellation()
        implementation = try FFmpegVideoDecoder(url: url, pixelFormat: pixelFormat)
    }

    func seek(to time: CMTime) throws {
        try Task.checkCancellation()
        try implementation.seek(to: time)
    }

    func readFrame() throws -> SoftwareVideoFrame? {
        try Task.checkCancellation()
        guard let frame = implementation.readFrame() else {
            if let error = implementation.lastError { throw error }
            return nil
        }
        try Task.checkCancellation()
        return SoftwareVideoFrame(pixelBuffer: frame.pixelBuffer, presentationTime: frame.presentationTime)
    }
}
#endif
