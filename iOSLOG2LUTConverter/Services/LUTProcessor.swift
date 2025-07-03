import Foundation
import CoreImage
import CoreVideo
import AVFoundation

// MARK: - LUT Processor for iOS (Replaces FFmpeg)
class LUTProcessor: ObservableObject {
    
    // MARK: - Properties
    private let context = CIContext()
    private var primaryLUTFilter: CIFilter?
    private var secondaryLUTFilter: CIFilter?
    
    @Published var isProcessing = false
    @Published var processingProgress: Double = 0.0
    @Published var processingStatus: String = "Ready"
    @Published var lastError: LUTProcessingError?
    
    // MARK: - LUT Processing Settings
    struct LUTSettings {
        var primaryLUTURL: URL?
        var secondaryLUTURL: URL?
        var secondaryLUTOpacity: Float = 1.0
        var whiteBalanceAdjustment: Float = 0.0
        var useGPUProcessing: Bool = true
        var outputQuality: OutputQuality = .high
    }
    
    enum OutputQuality {
        case low, medium, high, maximum
        
        var compressionQuality: Float {
            switch self {
            case .low: return 0.3
            case .medium: return 0.5
            case .high: return 0.7
            case .maximum: return 1.0
            }
        }
        
        var bitRate: Int {
            switch self {
            case .low: return 2_000_000    // 2 Mbps
            case .medium: return 5_000_000 // 5 Mbps
            case .high: return 10_000_000  // 10 Mbps
            case .maximum: return 20_000_000 // 20 Mbps
            }
        }
    }
    
    // MARK: - Error Handling
    enum LUTProcessingError: LocalizedError {
        case invalidLUTFile(String)
        case videoProcessingFailed(String)
        case exportFailed(String)
        case insufficientStorage
        case unsupportedFormat
        
        var errorDescription: String? {
            switch self {
            case .invalidLUTFile(let message):
                return "Invalid LUT file: \(message)"
            case .videoProcessingFailed(let message):
                return "Video processing failed: \(message)"
            case .exportFailed(let message):
                return "Export failed: \(message)"
            case .insufficientStorage:
                return "Insufficient storage space for export"
            case .unsupportedFormat:
                return "Unsupported video format"
            }
        }
    }
    
    // MARK: - LUT Loading
    func loadLUTFilters(settings: LUTSettings) throws {
        // Load Primary LUT
        if let primaryURL = settings.primaryLUTURL {
            primaryLUTFilter = try createLUTFilter(from: primaryURL)
        } else {
            primaryLUTFilter = nil
        }
        
        // Load Secondary LUT
        if let secondaryURL = settings.secondaryLUTURL {
            secondaryLUTFilter = try createLUTFilter(from: secondaryURL)
        } else {
            secondaryLUTFilter = nil
        }
        
        updateStatus("LUT filters loaded successfully")
    }
    
    private func createLUTFilter(from url: URL) throws -> CIFilter {
        guard let filter = CIFilter(name: "CIColorCube") else {
            throw LUTProcessingError.invalidLUTFile("Could not create color cube filter")
        }
        
        // Parse LUT file and create cube data
        let cubeData = try parseLUTFile(url)
        
        // Configure the filter
        filter.setValue(cubeData, forKey: "inputCubeData")
        filter.setValue(32, forKey: "inputCubeDimension") // Standard 32x32x32 cube
        
        return filter
    }
    
    private func parseLUTFile(_ url: URL) throws -> Data {
        guard url.pathExtension.lowercased() == "cube" else {
            throw LUTProcessingError.invalidLUTFile("Only .cube files are supported")
        }
        
        let content = try String(contentsOf: url, encoding: .utf8)
        return try parseCubeFile(content)
    }
    
    private func parseCubeFile(_ content: String) throws -> Data {
        let lines = content.components(separatedBy: .newlines)
        var cubeSize = 32
        var cubeData: [Float] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.hasPrefix("LUT_3D_SIZE") {
                let components = trimmed.components(separatedBy: .whitespaces)
                if components.count > 1, let size = Int(components[1]) {
                    cubeSize = size
                }
            } else if !trimmed.isEmpty && !trimmed.hasPrefix("#") && !trimmed.hasPrefix("TITLE") {
                // Parse RGB values
                let values = trimmed.components(separatedBy: .whitespaces)
                if values.count >= 3 {
                    for i in 0..<3 {
                        if let value = Float(values[i]) {
                            cubeData.append(value)
                        }
                    }
                }
            }
        }
        
        // Validate cube data
        let expectedSize = cubeSize * cubeSize * cubeSize * 3
        guard cubeData.count == expectedSize else {
            throw LUTProcessingError.invalidLUTFile("Invalid cube data size")
        }
        
        return Data(bytes: cubeData, count: cubeData.count * MemoryLayout<Float>.size)
    }
    
    // MARK: - Image Processing
    func processImage(_ image: CIImage, settings: LUTSettings) -> CIImage? {
        var processedImage = image
        
        // Apply white balance adjustment
        if settings.whiteBalanceAdjustment != 0 {
            processedImage = applyWhiteBalanceAdjustment(processedImage, adjustment: settings.whiteBalanceAdjustment)
        }
        
        // Apply primary LUT
        if let primaryFilter = primaryLUTFilter {
            primaryFilter.setValue(processedImage, forKey: kCIInputImageKey)
            if let output = primaryFilter.outputImage {
                processedImage = output
            }
        }
        
        // Apply secondary LUT if available
        if let secondaryFilter = secondaryLUTFilter {
            secondaryFilter.setValue(processedImage, forKey: kCIInputImageKey)
            if let secondaryOutput = secondaryFilter.outputImage {
                // Blend with original based on opacity
                let blendFilter = CIFilter(name: "CIBlendWithAlphaMask")
                blendFilter?.setValue(processedImage, forKey: kCIInputImageKey)
                blendFilter?.setValue(secondaryOutput, forKey: kCIInputBackgroundImageKey)
                
                // Create alpha mask based on opacity
                let alphaMask = createAlphaMask(opacity: settings.secondaryLUTOpacity, size: processedImage.extent.size)
                blendFilter?.setValue(alphaMask, forKey: kCIInputMaskImageKey)
                
                if let blendedOutput = blendFilter?.outputImage {
                    processedImage = blendedOutput
                }
            }
        }
        
        return processedImage
    }
    
    private func applyWhiteBalanceAdjustment(_ image: CIImage, adjustment: Float) -> CIImage {
        guard let filter = CIFilter(name: "CIWhitePointAdjust") else { return image }
        
        // Convert adjustment (-10 to 10) to color temperature
        let baseTemp: Float = 6500 // Base temperature
        let tempAdjustment = adjustment * 100 // Scale adjustment
        let newTemp = baseTemp + tempAdjustment
        
        // Convert temperature to color values
        let colorValue = temperatureToColor(newTemp)
        
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIColor(red: CGFloat(colorValue.r), 
                               green: CGFloat(colorValue.g), 
                               blue: CGFloat(colorValue.b)), forKey: kCIInputColorKey)
        
        return filter.outputImage ?? image
    }
    
    private func temperatureToColor(_ temperature: Float) -> (r: Float, g: Float, b: Float) {
        // Simplified color temperature conversion
        let temp = temperature / 100.0
        
        let red: Float
        let green: Float
        let blue: Float
        
        if temp <= 66 {
            red = 1.0
            green = temp <= 19 ? 0.0 : (99.4708025861 * log(temp - 10) - 161.1195681661) / 255.0
        } else {
            red = (329.698727446 * pow(temp - 60, -0.1332047592)) / 255.0
            green = (288.1221695283 * pow(temp - 60, -0.0755148492)) / 255.0
        }
        
        if temp >= 66 {
            blue = 1.0
        } else if temp <= 19 {
            blue = 0.0
        } else {
            blue = (138.5177312231 * log(temp - 10) - 305.0447927307) / 255.0
        }
        
        return (max(0, min(1, red)), max(0, min(1, green)), max(0, min(1, blue)))
    }
    
    private func createAlphaMask(opacity: Float, size: CGSize) -> CIImage {
        let color = CIColor(red: 0, green: 0, blue: 0, alpha: CGFloat(opacity))
        let colorFilter = CIFilter(name: "CIConstantColorGenerator")
        colorFilter?.setValue(color, forKey: kCIInputColorKey)
        
        let cropFilter = CIFilter(name: "CICrop")
        cropFilter?.setValue(colorFilter?.outputImage, forKey: kCIInputImageKey)
        cropFilter?.setValue(CIVector(cgRect: CGRect(origin: .zero, size: size)), forKey: "inputRectangle")
        
        return cropFilter?.outputImage ?? CIImage()
    }
    
    // MARK: - Video Processing
    func processVideo(_ videoURL: URL, settings: LUTSettings, outputURL: URL) async throws {
        updateStatus("Starting video processing...")
        
        // Load LUT filters
        try loadLUTFilters(settings: settings)
        
        // Set up video composition
        let asset = AVAsset(url: videoURL)
        let composition = try await createVideoComposition(asset: asset, settings: settings)
        
        // Export video
        try await exportVideo(asset: asset, composition: composition, outputURL: outputURL, settings: settings)
        
        updateStatus("Video processing completed")
    }
    
    private func createVideoComposition(asset: AVAsset, settings: LUTSettings) async throws -> AVVideoComposition {
        let composition = AVMutableVideoComposition()
        
        // Get video track
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw LUTProcessingError.videoProcessingFailed("No video track found")
        }
        
        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        
        composition.renderSize = naturalSize
        composition.frameDuration = CMTime(value: 1, timescale: 30) // 30 FPS
        
        // Create video composition instruction
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: try await asset.load(.duration))
        
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        layerInstruction.setTransform(transform, at: .zero)
        
        instruction.layerInstructions = [layerInstruction]
        composition.instructions = [instruction]
        
        // Apply LUT processing
        composition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        
        return composition
    }
    
    private func exportVideo(asset: AVAsset, composition: AVVideoComposition, outputURL: URL, settings: LUTSettings) async throws {
        // Remove existing file if it exists
        try? FileManager.default.removeItem(at: outputURL)
        
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw LUTProcessingError.exportFailed("Could not create export session")
        }
        
        exportSession.videoComposition = composition
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        
        await exportSession.export()
        
        guard exportSession.status == .completed else {
            let error = exportSession.error?.localizedDescription ?? "Unknown error"
            throw LUTProcessingError.exportFailed(error)
        }
    }
    
    // MARK: - Preview Generation
    func generatePreview(from videoURL: URL, settings: LUTSettings) async throws -> CIImage {
        let asset = AVAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        
        let time = CMTime(seconds: 1.0, preferredTimescale: 600)
        let cgImage = try await generator.image(at: time).image
        
        let ciImage = CIImage(cgImage: cgImage)
        return processImage(ciImage, settings: settings) ?? ciImage
    }
    
    // MARK: - Status Management
    private func updateStatus(_ message: String) {
        DispatchQueue.main.async {
            self.processingStatus = message
            print("🎨 LUT Processor: \(message)")
        }
    }
    
    private func updateProgress(_ progress: Double) {
        DispatchQueue.main.async {
            self.processingProgress = progress
        }
    }
    
    func resetProgress() {
        DispatchQueue.main.async {
            self.processingProgress = 0.0
            self.processingStatus = "Ready"
            self.lastError = nil
        }
    }
} 