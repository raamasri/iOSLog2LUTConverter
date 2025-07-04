import Foundation
import CoreImage
import CoreVideo
import AVFoundation
import Metal

// MARK: - Custom Video Compositor for LUT Processing
class LUTVideoCompositor: NSObject, AVVideoCompositing {
    
    private let renderContext = CIContext()
    private var primaryLUTFilter: CIFilter?
    private var secondaryLUTFilter: CIFilter?
    private var lutSettings: [String: Any] = [:]
    
    var sourcePixelBufferAttributes: [String : Any]? {
        return [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
    }
    
    var requiredPixelBufferAttributesForRenderContext: [String : Any] {
        return [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
    }
    
    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        // Update render context if needed
    }
    
    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? AVVideoCompositionInstruction,
              let pixelBuffer = request.sourceFrame(byTrackID: instruction.layerInstructions.first?.trackID ?? 0) else {
            request.finish(with: NSError(domain: "LUTVideoCompositor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid request"]))
            return
        }
        
        // Load LUT settings from composition if not already loaded
        if primaryLUTFilter == nil || secondaryLUTFilter == nil {
            loadLUTFiltersFromComposition(request.renderContext.videoComposition)
        }
        
        // Create CIImage from pixel buffer
        let inputImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // Apply LUT processing
        let processedImage = applyLUTProcessing(to: inputImage)
        
        // Render back to pixel buffer
        guard let outputPixelBuffer = request.renderContext.newPixelBuffer() else {
            request.finish(with: NSError(domain: "LUTVideoCompositor", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create output pixel buffer"]))
            return
        }
        
        renderContext.render(processedImage, to: outputPixelBuffer)
        request.finish(withComposedVideoFrame: outputPixelBuffer)
    }
    
    private func loadLUTFiltersFromComposition(_ composition: AVVideoComposition?) {
        guard let composition = composition,
              let settingsData = composition.value(forKey: "lutSettings") as? Data,
              let settings = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(settingsData) as? [String: Any] else {
            print("⚠️ LUTVideoCompositor: Could not load LUT settings from composition")
            return
        }
        
        lutSettings = settings
        
        // Load primary LUT
        if let primaryURLString = settings["primaryLUTURL"] as? String,
           !primaryURLString.isEmpty,
           let primaryURL = URL(string: primaryURLString) {
            do {
                primaryLUTFilter = try createLUTFilter(from: primaryURL)
                print("✅ LUTVideoCompositor: Loaded primary LUT filter")
            } catch {
                print("❌ LUTVideoCompositor: Failed to load primary LUT: \(error)")
            }
        }
        
        // Load secondary LUT
        if let secondaryURLString = settings["secondaryLUTURL"] as? String,
           !secondaryURLString.isEmpty,
           let secondaryURL = URL(string: secondaryURLString) {
            do {
                secondaryLUTFilter = try createLUTFilter(from: secondaryURL)
                print("✅ LUTVideoCompositor: Loaded secondary LUT filter")
            } catch {
                print("❌ LUTVideoCompositor: Failed to load secondary LUT: \(error)")
            }
        }
    }
    
    private func createLUTFilter(from url: URL) throws -> CIFilter {
        print("🎬 LUTVideoCompositor: Creating LUT filter from \(url.lastPathComponent)")
        
        // Parse LUT file using the same logic as LUTProcessor
        let lutInfo = try parseLUTFile(url)
        
        if lutInfo.is1D {
            // Convert 1D LUT to 3D LUT for compatibility with CIColorCube
            let converted3D = try convert1DTo3D(lutInfo)
            
            guard let filter = CIFilter(name: "CIColorCube") else {
                throw NSError(domain: "LUTVideoCompositor", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not create color cube filter"])
            }
            
            filter.setValue(converted3D.data, forKey: "inputCubeData")
            filter.setValue(converted3D.dimension, forKey: "inputCubeDimension")
            filter.setValue(false, forKey: "inputExtrapolate")
            
            print("✅ LUTVideoCompositor: Created 1D->3D LUT filter")
            return filter
        } else {
            // Use CIColorCube for 3D LUTs
            guard let filter = CIFilter(name: "CIColorCube") else {
                throw NSError(domain: "LUTVideoCompositor", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not create color cube filter"])
            }
            
            filter.setValue(lutInfo.data, forKey: "inputCubeData")
            filter.setValue(lutInfo.dimension, forKey: "inputCubeDimension")
            filter.setValue(false, forKey: "inputExtrapolate")
            
            print("✅ LUTVideoCompositor: Created 3D LUT filter")
            return filter
        }
    }
    
    private func applyLUTProcessing(to image: CIImage) -> CIImage {
        var processedImage = image
        
        // Apply primary LUT
        if let primaryFilter = primaryLUTFilter {
            primaryFilter.setValue(processedImage, forKey: kCIInputImageKey)
            if let output = primaryFilter.outputImage {
                processedImage = output
                print("🎨 LUTVideoCompositor: Applied primary LUT")
            }
        }
        
        // Apply secondary LUT with opacity
        if let secondaryFilter = secondaryLUTFilter {
            secondaryFilter.setValue(processedImage, forKey: kCIInputImageKey)
            if let secondaryOutput = secondaryFilter.outputImage {
                let opacity = lutSettings["secondaryLUTOpacity"] as? Float ?? 1.0
                
                // Simple blend based on opacity
                if opacity < 1.0 {
                    let blendFilter = CIFilter(name: "CISourceOverCompositing")
                    blendFilter?.setValue(secondaryOutput, forKey: kCIInputImageKey)
                    blendFilter?.setValue(processedImage, forKey: kCIInputBackgroundImageKey)
                    
                    if let blendedOutput = blendFilter?.outputImage {
                        processedImage = blendedOutput
                    }
                } else {
                    processedImage = secondaryOutput
                }
                print("🎭 LUTVideoCompositor: Applied secondary LUT with opacity \(Int(opacity * 100))%")
            }
        }
        
        return processedImage
    }
    
    // MARK: - LUT Data Structure
    private struct LUTInfo {
        let data: Data
        let is1D: Bool
        let dimension: Int
    }
    
    // MARK: - LUT Parsing Methods (shared with LUTProcessor)
    private func parseLUTFile(_ url: URL) throws -> LUTInfo {
        guard url.pathExtension.lowercased() == "cube" else {
            throw NSError(domain: "LUTVideoCompositor", code: 4, userInfo: [NSLocalizedDescriptionKey: "Only .cube files are supported"])
        }
        
        let content = try String(contentsOf: url, encoding: .utf8)
        return try parseCubeFile(content)
    }
    
    private func parseCubeFile(_ content: String) throws -> LUTInfo {
        let lines = content.components(separatedBy: .newlines)
        var cubeSize = 32
        var lutSize1D = 0
        var cubeData: [Float] = []
        var is1D = false
        
        // First pass: determine LUT type and size
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.hasPrefix("LUT_3D_SIZE") {
                let components = trimmed.components(separatedBy: .whitespaces)
                if components.count > 1, let size = Int(components[1]) {
                    cubeSize = size
                    is1D = false
                }
            } else if trimmed.hasPrefix("LUT_1D_SIZE") {
                let components = trimmed.components(separatedBy: .whitespaces)
                if components.count > 1, let size = Int(components[1]) {
                    lutSize1D = size
                    is1D = true
                }
            }
        }
        
        // Second pass: parse data
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if !trimmed.isEmpty && !trimmed.hasPrefix("#") && !trimmed.hasPrefix("TITLE") && !trimmed.hasPrefix("LUT_") {
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
        
        let data = Data(bytes: cubeData, count: cubeData.count * MemoryLayout<Float>.size)
        return LUTInfo(data: data, is1D: is1D, dimension: is1D ? lutSize1D : cubeSize)
    }
    
    private func convert1DTo3D(_ lutInfo: LUTInfo) throws -> LUTInfo {
        let lutData = lutInfo.data
        let lutSize = lutInfo.dimension
        
        // Create a 3D LUT (32x32x32 is a good standard size)
        let cubeSize = 32
        var cubeData: [Float] = []
        cubeData.reserveCapacity(cubeSize * cubeSize * cubeSize * 3)
        
        // Convert data to float array for easier processing
        let floatArray = lutData.withUnsafeBytes { bytes in
            return Array(bytes.bindMemory(to: Float.self))
        }
        
        // For each position in the 3D cube, interpolate from the 1D LUT
        for b in 0..<cubeSize {
            for g in 0..<cubeSize {
                for r in 0..<cubeSize {
                    // Convert 3D position to normalized RGB values (0.0 to 1.0)
                    let rNorm = Float(r) / Float(cubeSize - 1)
                    let gNorm = Float(g) / Float(cubeSize - 1)
                    let bNorm = Float(b) / Float(cubeSize - 1)
                    
                    // Apply 1D LUT to each channel independently
                    let rOut = interpolate1D(value: rNorm, lutData: floatArray, lutSize: lutSize, channel: 0)
                    let gOut = interpolate1D(value: gNorm, lutData: floatArray, lutSize: lutSize, channel: 1)
                    let bOut = interpolate1D(value: bNorm, lutData: floatArray, lutSize: lutSize, channel: 2)
                    
                    cubeData.append(rOut)
                    cubeData.append(gOut)
                    cubeData.append(bOut)
                }
            }
        }
        
        let convertedData = Data(bytes: cubeData, count: cubeData.count * MemoryLayout<Float>.size)
        return LUTInfo(data: convertedData, is1D: false, dimension: cubeSize)
    }
    
    private func interpolate1D(value: Float, lutData: [Float], lutSize: Int, channel: Int) -> Float {
        // Clamp input value to [0, 1]
        let clampedValue = max(0.0, min(1.0, value))
        
        // Convert to LUT index space
        let lutIndex = clampedValue * Float(lutSize - 1)
        let lowerIndex = Int(floor(lutIndex))
        let upperIndex = min(lowerIndex + 1, lutSize - 1)
        let fraction = lutIndex - Float(lowerIndex)
        
        // Get the values from the LUT (each entry has 3 components: R, G, B)
        let lowerValue = lutData[lowerIndex * 3 + channel]
        let upperValue = lutData[upperIndex * 3 + channel]
        
        // Linear interpolation
        return lowerValue + fraction * (upperValue - lowerValue)
    }
}

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
        var primaryLUTOpacity: Float = 1.0
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
            case .maximum: return 50_000_000 // 50 Mbps - Very high for maximum quality
            }
        }
        
        /// Resolution scaling factor - 1.0 means original resolution
        var resolutionScale: CGFloat {
            switch self {
            case .low: return 0.5      // Scale to 50% (e.g., 4K -> 1080p, 1080p -> 540p)
            case .medium: return 0.75  // Scale to 75% 
            case .high: return 1.0     // Original resolution
            case .maximum: return 1.0  // Original resolution - preserve everything
            }
        }
        
        /// Maximum resolution limit - nil means no limit
        var maxResolution: CGSize? {
            switch self {
            case .low: return CGSize(width: 1280, height: 720)    // 720p max
            case .medium: return CGSize(width: 1920, height: 1080) // 1080p max
            case .high: return nil     // No limit
            case .maximum: return nil  // No limit - preserve original
            }
        }
        
        /// Video codec to use
        var codec: AVVideoCodecType {
            switch self {
            case .low, .medium: return .h264
            case .high: return .h264
            case .maximum: return .h264 // Use H.264 with highest quality settings instead of HEVC
            }
        }
        
        /// Export preset for AVAssetExportSession
        var exportPreset: String {
            switch self {
            case .low: return AVAssetExportPresetMediumQuality
            case .medium: return AVAssetExportPreset1920x1080
            case .high: return AVAssetExportPresetHighestQuality
            case .maximum: return AVAssetExportPresetPassthrough // Preserve original data
            }
        }
        
        /// H.264/HEVC profile level
        var profileLevel: String {
            switch self {
            case .low: return AVVideoProfileLevelH264BaselineAutoLevel
            case .medium: return AVVideoProfileLevelH264MainAutoLevel
            case .high: return AVVideoProfileLevelH264HighAutoLevel
            case .maximum: return AVVideoProfileLevelH264HighAutoLevel // Use highest H.264 profile
            }
        }
        
        /// Key frame interval
        var keyFrameInterval: Int {
            switch self {
            case .low: return 60       // Less frequent keyframes for smaller files
            case .medium: return 30
            case .high: return 30
            case .maximum: return 15   // More frequent keyframes for maximum quality
            }
        }
        
        /// Quality description for UI
        var description: String {
            switch self {
            case .low: return "Low (Fast, 720p max, smaller files)"
            case .medium: return "Medium (Balanced, 1080p max)"
            case .high: return "High (Original resolution, recommended)"
            case .maximum: return "Max (Original data preserved, largest files)"
            }
        }
        
        /// Calculate output size based on input size
        func outputSize(from inputSize: CGSize) -> CGSize {
            var outputSize = CGSize(
                width: inputSize.width * resolutionScale,
                height: inputSize.height * resolutionScale
            )
            
            // Apply maximum resolution limit if set
            if let maxRes = maxResolution {
                if outputSize.width > maxRes.width || outputSize.height > maxRes.height {
                    let scaleX = maxRes.width / outputSize.width
                    let scaleY = maxRes.height / outputSize.height
                    let scale = min(scaleX, scaleY)
                    
                    outputSize = CGSize(
                        width: outputSize.width * scale,
                        height: outputSize.height * scale
                    )
                }
            }
            
            // Ensure even dimensions for video encoding
            outputSize.width = floor(outputSize.width / 2) * 2
            outputSize.height = floor(outputSize.height / 2) * 2
            
            return outputSize
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
        // Parse LUT file and determine if it's 1D or 3D
        let lutInfo = try parseLUTFile(url)
        
        print("🔍 Creating LUT filter from: \(url.lastPathComponent)")
        print("   - Is 1D: \(lutInfo.is1D)")
        print("   - Dimension: \(lutInfo.dimension)")
        print("   - Data size: \(lutInfo.data.count) bytes")
        
        if lutInfo.is1D {
            // Convert 1D LUT to 3D LUT for compatibility with CIColorCube
            let converted3D = try convert1DTo3D(lutInfo)
            
            guard let filter = CIFilter(name: "CIColorCube") else {
                throw LUTProcessingError.invalidLUTFile("Could not create color cube filter")
            }
            
            // Use RGB data directly - CIColorCube expects RGB, not RGBA
            print("🔄 Using converted 1D->3D RGB data format:")
            print("   - RGB float count: \(converted3D.data.count / MemoryLayout<Float>.size)")
            print("   - RGB data size: \(converted3D.data.count) bytes")
            
            // Configure the filter with RGB LUT data
            filter.setValue(converted3D.data, forKey: "inputCubeData")
            filter.setValue(converted3D.dimension, forKey: "inputCubeDimension")
            filter.setValue(false, forKey: "inputExtrapolate")
            return filter
        } else {
            // Use CIColorCube for 3D LUTs
            guard let filter = CIFilter(name: "CIColorCube") else {
                throw LUTProcessingError.invalidLUTFile("Could not create color cube filter")
            }
            
            print("🔧 CIColorCube filter created successfully")
            print("   - Available attributes: \(filter.attributes.keys.sorted())")
            
            // Debug the LUT data before applying
            print("🔍 LUT Filter Debug:")
            print("   - File: \(url.lastPathComponent)")
            print("   - Dimension: \(lutInfo.dimension)")
            print("   - Data size: \(lutInfo.data.count) bytes")
            print("   - Expected RGBA size: \(lutInfo.dimension * lutInfo.dimension * lutInfo.dimension * 4 * 4) bytes")
            
            // Test the data format
            lutInfo.data.withUnsafeBytes { bytes in
                let floats = bytes.bindMemory(to: Float.self)
                let count = min(12, floats.count) // Show more values
                print("   - First \(count) values: \(Array(floats.prefix(count)))")
                if floats.count > 0 {
                    print("   - Value range: [\(floats.min() ?? 0), \(floats.max() ?? 0)]")
                    print("   - Total float count: \(floats.count)")
                    print("   - Expected RGBA float count: \(lutInfo.dimension * lutInfo.dimension * lutInfo.dimension * 4)")
                    
                    // Check for NaN or infinite values
                    let hasNaN = floats.contains { $0.isNaN }
                    let hasInf = floats.contains { $0.isInfinite }
                    print("   - Contains NaN: \(hasNaN)")
                    print("   - Contains Infinite: \(hasInf)")
                    
                    // Check if values are in valid range [0,1]
                    let invalidValues = floats.filter { $0 < 0 || $0 > 1 }
                    if !invalidValues.isEmpty {
                        print("   - ⚠️ Found \(invalidValues.count) values outside [0,1] range")
                        print("   - Invalid samples: \(Array(invalidValues.prefix(5)))")
                    }
                }
            }
            
            // Verify RGBA data format - CIColorCube requires RGBA, not RGB
            let expectedRGBASize = lutInfo.dimension * lutInfo.dimension * lutInfo.dimension * 4 * MemoryLayout<Float>.size
            print("🔄 Using RGBA data format (as required by CIColorCube):")
            print("   - RGBA float count: \(lutInfo.data.count / MemoryLayout<Float>.size)")
            print("   - RGBA data size: \(lutInfo.data.count) bytes")
            print("   - Expected RGBA size: \(expectedRGBASize) bytes")
            
            // Verify the data is actually in RGBA format
            if lutInfo.data.count != expectedRGBASize {
                print("   - ⚠️ WARNING: Data size mismatch! Expected RGBA but got different size")
                print("   - This suggests RGB to RGBA conversion failed")
                throw LUTProcessingError.invalidLUTFile("LUT data is not in expected RGBA format")
            }
            
            // Configure the filter with RGBA LUT data
            filter.setValue(lutInfo.data, forKey: "inputCubeData")
            filter.setValue(lutInfo.dimension, forKey: "inputCubeDimension")
            filter.setValue(false, forKey: "inputExtrapolate") // Disable extrapolation initially
            
            // Test the filter with a simple image to ensure it works
            let testImage = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
            filter.setValue(testImage, forKey: kCIInputImageKey)
            
            print("🧪 Testing LUT filter with gray image...")
            print("   - Test image extent: \(testImage.extent)")
            print("   - Filter name: \(filter.name)")
            print("   - Filter attributes: \(filter.attributes)")
            
            // Check if the filter has the required inputs
            let inputKeys = filter.inputKeys
            print("   - Available input keys: \(inputKeys)")
            
            // Check current filter values
            if let cubeData = filter.value(forKey: "inputCubeData") {
                print("   - inputCubeData is set: \(type(of: cubeData))")
            } else {
                print("   - ❌ inputCubeData is NOT set")
            }
            
            if let cubeDimension = filter.value(forKey: "inputCubeDimension") {
                print("   - inputCubeDimension is set: \(cubeDimension)")
            } else {
                print("   - ❌ inputCubeDimension is NOT set")
            }
            
            // Try to get output image
            guard let testOutput = filter.outputImage else {
                print("   - ❌ Filter has no output image - trying with extrapolate enabled...")
                
                // Try with extrapolation enabled
                filter.setValue(true, forKey: "inputExtrapolate")
                
                guard let testOutputWithExtrapolate = filter.outputImage else {
                    print("   - ❌ Filter still has no output image")
                    print("🔧 Creating identity filter as fallback...")
                    return try createIdentityFilter()
                }
                
                print("   - ✅ Filter works with extrapolation enabled")
                return filter
            }
            
            print("   - ✅ Filter has output image")
            print("   - Output extent: \(testOutput.extent)")
            
            // Simple validation - if we have output, the filter should work
            print("   - ✅ LUT filter test PASSED")
            return filter
        }
    }
    
    func createIdentityFilter() throws -> CIFilter {
        print("🔧 Creating identity filter as fallback...")
        
        guard let filter = CIFilter(name: "CIColorCube") else {
            throw LUTProcessingError.invalidLUTFile("Could not create identity filter")
        }
        
        // Create a simple identity LUT (32x32x32) in RGBA format
        let cubeSize = 32
        var cubeData: [Float] = []
        cubeData.reserveCapacity(cubeSize * cubeSize * cubeSize * 4)
        
        for b in 0..<cubeSize {
            for g in 0..<cubeSize {
                for r in 0..<cubeSize {
                    cubeData.append(Float(r) / Float(cubeSize - 1))
                    cubeData.append(Float(g) / Float(cubeSize - 1))
                    cubeData.append(Float(b) / Float(cubeSize - 1))
                    cubeData.append(1.0) // Add alpha channel
                }
            }
        }
        
        let data = Data(bytes: cubeData, count: cubeData.count * MemoryLayout<Float>.size)
        filter.setValue(data, forKey: "inputCubeData")
        filter.setValue(cubeSize, forKey: "inputCubeDimension")
        filter.setValue(false, forKey: "inputExtrapolate")
        
        print("⚠️ Using identity filter (no color change) with RGBA format")
        return filter
    }
    
    // MARK: - LUT Data Structure
    struct LUTInfo {
        let data: Data
        let is1D: Bool
        let dimension: Int
    }
    
    private func parseLUTFile(_ url: URL) throws -> LUTInfo {
        guard url.pathExtension.lowercased() == "cube" else {
            throw LUTProcessingError.invalidLUTFile("Only .cube files are supported")
        }
        
        let content = try String(contentsOf: url, encoding: .utf8)
        return try parseCubeFile(content)
    }
    
    private func parseCubeFile(_ content: String) throws -> LUTInfo {
        let lines = content.components(separatedBy: .newlines)
        var cubeSize = 32
        var lutSize1D = 0
        var cubeData: [Float] = []
        var is1D = false
        
        // First pass: determine LUT type and size
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.hasPrefix("LUT_3D_SIZE") {
                let components = trimmed.components(separatedBy: .whitespaces)
                if components.count > 1, let size = Int(components[1]) {
                    cubeSize = size
                    is1D = false
                }
            } else if trimmed.hasPrefix("LUT_1D_SIZE") {
                let components = trimmed.components(separatedBy: .whitespaces)
                if components.count > 1, let size = Int(components[1]) {
                    lutSize1D = size
                    is1D = true
                }
            }
        }
        
        // Second pass: parse data
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if !trimmed.isEmpty && !trimmed.hasPrefix("#") && !trimmed.hasPrefix("TITLE") && !trimmed.hasPrefix("LUT_") {
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
        
        // Validate data based on LUT type
        if is1D {
            let expectedSize = lutSize1D * 3
            print("🔍 LUT Parsing: 1D LUT detected - Size: \(lutSize1D), Expected: \(expectedSize), Actual: \(cubeData.count)")
            guard cubeData.count == expectedSize else {
                throw LUTProcessingError.invalidLUTFile("Invalid 1D LUT data size - Expected: \(expectedSize), Got: \(cubeData.count)")
            }
        } else {
            let expectedSize = cubeSize * cubeSize * cubeSize * 3
            print("🔍 LUT Parsing: 3D LUT detected - Size: \(cubeSize), Expected: \(expectedSize), Actual: \(cubeData.count)")
            guard cubeData.count == expectedSize else {
                throw LUTProcessingError.invalidLUTFile("Invalid 3D LUT data size - Expected: \(expectedSize), Got: \(cubeData.count)")
            }
        }
        
        // Convert RGB to RGBA format (required by CIColorCube)
        var rgbaData: [Float] = []
        rgbaData.reserveCapacity(cubeData.count / 3 * 4) // RGB to RGBA conversion
        
        for i in stride(from: 0, to: cubeData.count, by: 3) {
            rgbaData.append(cubeData[i])     // R
            rgbaData.append(cubeData[i + 1]) // G
            rgbaData.append(cubeData[i + 2]) // B
            rgbaData.append(1.0)             // A (alpha = 1.0)
        }
        
        print("✅ Converted RGB to RGBA format: \(rgbaData.count) values")
        
        let data = Data(bytes: rgbaData, count: rgbaData.count * MemoryLayout<Float>.size)
        return LUTInfo(data: data, is1D: is1D, dimension: is1D ? lutSize1D : cubeSize)
    }
    
    // MARK: - 1D to 3D LUT Conversion
    private func convert1DTo3D(_ lutInfo: LUTInfo) throws -> LUTInfo {
        print("🔄 Converting 1D LUT to 3D LUT for Core Image compatibility...")
        
        // Extract the 1D LUT data
        let lutData = lutInfo.data
        let lutSize = lutInfo.dimension
        
        // Create a 3D LUT (32x32x32 is a good standard size)
        let cubeSize = 32
        var cubeData: [Float] = []
        cubeData.reserveCapacity(cubeSize * cubeSize * cubeSize * 4) // RGBA format
        
        // Convert data to float array for easier processing
        let floatArray = lutData.withUnsafeBytes { bytes in
            return Array(bytes.bindMemory(to: Float.self))
        }
        
        // For each position in the 3D cube, interpolate from the 1D LUT
        for b in 0..<cubeSize {
            for g in 0..<cubeSize {
                for r in 0..<cubeSize {
                    // Convert 3D position to normalized RGB values (0.0 to 1.0)
                    let rNorm = Float(r) / Float(cubeSize - 1)
                    let gNorm = Float(g) / Float(cubeSize - 1)
                    let bNorm = Float(b) / Float(cubeSize - 1)
                    
                    // Apply 1D LUT to each channel independently
                    let rOut = interpolate1D(value: rNorm, lutData: floatArray, lutSize: lutSize, channel: 0)
                    let gOut = interpolate1D(value: gNorm, lutData: floatArray, lutSize: lutSize, channel: 1)
                    let bOut = interpolate1D(value: bNorm, lutData: floatArray, lutSize: lutSize, channel: 2)
                    
                    cubeData.append(rOut)
                    cubeData.append(gOut)
                    cubeData.append(bOut)
                    cubeData.append(1.0) // Add alpha channel for RGBA format
                }
            }
        }
        
        let convertedData = Data(bytes: cubeData, count: cubeData.count * MemoryLayout<Float>.size)
        print("✅ Successfully converted 1D LUT (\(lutSize) entries) to 3D LUT (\(cubeSize)³) in RGBA format")
        
        return LUTInfo(data: convertedData, is1D: false, dimension: cubeSize)
    }
    
    private func interpolate1D(value: Float, lutData: [Float], lutSize: Int, channel: Int) -> Float {
        // Clamp input value to [0, 1]
        let clampedValue = max(0.0, min(1.0, value))
        
        // Convert to LUT index space
        let lutIndex = clampedValue * Float(lutSize - 1)
        let lowerIndex = Int(floor(lutIndex))
        let upperIndex = min(lowerIndex + 1, lutSize - 1)
        let fraction = lutIndex - Float(lowerIndex)
        
        // Get the values from the LUT (each entry has 3 components: R, G, B)
        let lowerValue = lutData[lowerIndex * 3 + channel]
        let upperValue = lutData[upperIndex * 3 + channel]
        
        // Linear interpolation
        return lowerValue + fraction * (upperValue - lowerValue)
    }
    
    // MARK: - Image Processing
    func processImage(_ image: CIImage, settings: LUTSettings) -> CIImage? {
        var processedImage = image
        
        print("🎨 LUT Processor: Starting image processing...")
        print("   - Input image extent: \(image.extent)")
        print("   - Primary LUT: \(primaryLUTFilter != nil ? "✅ Loaded" : "❌ Not loaded")")
        print("   - Secondary LUT: \(secondaryLUTFilter != nil ? "✅ Loaded" : "❌ Not loaded")")
        print("   - Processing order: Original → Primary LUT → White Balance → Secondary LUT")
        
        // Apply primary LUT with opacity support
        if let primaryFilter = primaryLUTFilter {
            primaryFilter.setValue(processedImage, forKey: kCIInputImageKey)
            if let primaryOutput = primaryFilter.outputImage {
                // Handle primary LUT opacity using proper blending
                if settings.primaryLUTOpacity < 1.0 {
                    // Use CISourceOverCompositing for proper opacity blending
                    if let blendFilter = CIFilter(name: "CISourceOverCompositing") {
                        // First, apply opacity to the LUT output using CIColorMatrix
                        if let opacityFilter = CIFilter(name: "CIColorMatrix") {
                            opacityFilter.setValue(primaryOutput, forKey: kCIInputImageKey)
                            opacityFilter.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
                            opacityFilter.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
                            opacityFilter.setValue(CIVector(x: 0, y: 0, z: 1, w: 0), forKey: "inputBVector")
                            opacityFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: CGFloat(settings.primaryLUTOpacity)), forKey: "inputAVector")
                            opacityFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBiasVector")
                            
                            if let opacityOutput = opacityFilter.outputImage {
                                // Now blend the opacity-adjusted LUT output over the original
                                blendFilter.setValue(opacityOutput, forKey: kCIInputImageKey)
                                blendFilter.setValue(processedImage, forKey: kCIInputBackgroundImageKey)
                                
                                if let blendedOutput = blendFilter.outputImage {
                                    processedImage = blendedOutput
                                    print("   - ✅ Primary LUT applied with \(Int(settings.primaryLUTOpacity * 100))% opacity")
                                } else {
                                    processedImage = primaryOutput
                                    print("   - ❌ Primary LUT blend failed, using full opacity")
                                }
                            } else {
                                processedImage = primaryOutput
                                print("   - ❌ Primary LUT opacity adjustment failed, using full opacity")
                            }
                        } else {
                            processedImage = primaryOutput
                            print("   - ❌ Could not create opacity filter for primary LUT, using full opacity")
                        }
                    } else {
                        processedImage = primaryOutput
                        print("   - ❌ Could not create blend filter for primary LUT, using full opacity")
                    }
                } else {
                    processedImage = primaryOutput
                    print("   - ✅ Primary LUT applied successfully")
                }
            } else {
                print("   - ❌ Primary LUT failed to generate output")
            }
        } else {
            print("   - ⚠️ No primary LUT to apply")
        }
        
        // Apply white balance adjustment after primary LUT
        if settings.whiteBalanceAdjustment != 0 {
            processedImage = applyWhiteBalanceAdjustment(processedImage, adjustment: settings.whiteBalanceAdjustment)
            let baseTemp = 5500
            let tempChange = Int(settings.whiteBalanceAdjustment * 280)
            let finalTemp = baseTemp + tempChange
            print("   - ✅ White balance applied: \(settings.whiteBalanceAdjustment) (\(finalTemp)K)")
        }
        
        // Apply secondary LUT with proper chaining and opacity support
        if let secondaryFilter = secondaryLUTFilter {
            secondaryFilter.setValue(processedImage, forKey: kCIInputImageKey)
            if let secondaryOutput = secondaryFilter.outputImage {
                // Handle opacity blending
                if settings.secondaryLUTOpacity < 1.0 {
                    // Use CISourceOverCompositing for proper opacity blending
                    if let blendFilter = CIFilter(name: "CISourceOverCompositing") {
                        // First, apply opacity to the LUT output using CIColorMatrix
                        if let opacityFilter = CIFilter(name: "CIColorMatrix") {
                            opacityFilter.setValue(secondaryOutput, forKey: kCIInputImageKey)
                            opacityFilter.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
                            opacityFilter.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
                            opacityFilter.setValue(CIVector(x: 0, y: 0, z: 1, w: 0), forKey: "inputBVector")
                            opacityFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: CGFloat(settings.secondaryLUTOpacity)), forKey: "inputAVector")
                            opacityFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBiasVector")
                            
                            if let opacityOutput = opacityFilter.outputImage {
                                // Now blend the opacity-adjusted LUT output over the original
                                blendFilter.setValue(opacityOutput, forKey: kCIInputImageKey)
                                blendFilter.setValue(processedImage, forKey: kCIInputBackgroundImageKey)
                                
                                if let blendedOutput = blendFilter.outputImage {
                                    processedImage = blendedOutput
                                    print("   - ✅ Secondary LUT applied with \(Int(settings.secondaryLUTOpacity * 100))% opacity")
                                } else {
                                    print("   - ❌ Secondary LUT blend failed, using full opacity")
                                    processedImage = secondaryOutput
                                }
                            } else {
                                print("   - ❌ Secondary LUT opacity adjustment failed, using full opacity")
                                processedImage = secondaryOutput
                            }
                        } else {
                            print("   - ❌ Could not create opacity filter for secondary LUT, using full opacity")
                            processedImage = secondaryOutput
                        }
                    } else {
                        print("   - ❌ Could not create blend filter for secondary LUT, using full opacity")
                        processedImage = secondaryOutput
                    }
                } else {
                    // Full opacity - use secondary output directly
                    processedImage = secondaryOutput
                    print("   - ✅ Secondary LUT applied at 100% opacity")
                }
            } else {
                print("   - ❌ Secondary LUT failed to generate output")
            }
        } else {
            print("   - ⚠️ No secondary LUT to apply")
        }
        
        print("🎨 LUT Processor: Image processing completed")
        print("   - Output image extent: \(processedImage.extent)")
        
        return processedImage
    }
    
    // MARK: - Simplified Image Processing (Direct LUT Application)
    func processImageDirect(_ image: CIImage, settings: LUTSettings) -> CIImage? {
        var processedImage = image
        
        print("🎨 LUT Processor (Direct): Starting image processing...")
        print("   - Input image extent: \(image.extent)")
        print("   - Primary LUT: \(primaryLUTFilter != nil ? "✅ Loaded" : "❌ Not loaded")")
        print("   - Secondary LUT: \(secondaryLUTFilter != nil ? "✅ Loaded" : "❌ Not loaded")")
        print("   - Processing order: Original → Primary LUT → White Balance → Secondary LUT")
        
        // Apply primary LUT directly with opacity support
        if let primaryFilter = primaryLUTFilter {
            primaryFilter.setValue(processedImage, forKey: kCIInputImageKey)
            if let primaryOutput = primaryFilter.outputImage {
                // Handle primary LUT opacity
                if settings.primaryLUTOpacity < 1.0 {
                    // Use CISourceOverCompositing for proper opacity blending
                    if let blendFilter = CIFilter(name: "CISourceOverCompositing") {
                        // First, apply opacity to the LUT output using CIColorMatrix
                        if let opacityFilter = CIFilter(name: "CIColorMatrix") {
                            opacityFilter.setValue(primaryOutput, forKey: kCIInputImageKey)
                            opacityFilter.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
                            opacityFilter.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
                            opacityFilter.setValue(CIVector(x: 0, y: 0, z: 1, w: 0), forKey: "inputBVector")
                            opacityFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: CGFloat(settings.primaryLUTOpacity)), forKey: "inputAVector")
                            opacityFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBiasVector")
                            
                            if let opacityOutput = opacityFilter.outputImage {
                                // Now blend the opacity-adjusted LUT output over the original
                                blendFilter.setValue(opacityOutput, forKey: kCIInputImageKey)
                                blendFilter.setValue(processedImage, forKey: kCIInputBackgroundImageKey)
                                
                                if let blendedOutput = blendFilter.outputImage {
                                    processedImage = blendedOutput
                                    print("   - ✅ Primary LUT applied with \(Int(settings.primaryLUTOpacity * 100))% opacity (direct)")
                                } else {
                                    processedImage = primaryOutput
                                    print("   - ❌ Primary LUT blend failed, using full opacity (direct)")
                                }
                            } else {
                                processedImage = primaryOutput
                                print("   - ❌ Primary LUT opacity adjustment failed, using full opacity (direct)")
                            }
                        } else {
                            processedImage = primaryOutput
                            print("   - ❌ Could not create opacity filter for primary LUT, using full opacity (direct)")
                        }
                    } else {
                        processedImage = primaryOutput
                        print("   - ❌ Could not create blend filter for primary LUT, using full opacity (direct)")
                    }
                } else {
                    processedImage = primaryOutput
                    print("   - ✅ Primary LUT applied successfully (direct)")
                }
            } else {
                print("   - ❌ Primary LUT failed to generate output")
            }
        }
        
        // Apply white balance adjustment after primary LUT
        if settings.whiteBalanceAdjustment != 0 {
            processedImage = applyWhiteBalanceAdjustment(processedImage, adjustment: settings.whiteBalanceAdjustment)
            let baseTemp = 5500
            let tempChange = Int(settings.whiteBalanceAdjustment * 280)
            let finalTemp = baseTemp + tempChange
            print("   - ✅ White balance applied: \(settings.whiteBalanceAdjustment) (\(finalTemp)K) (direct)")
        }
        
        // Apply secondary LUT directly with opacity support
        if let secondaryFilter = secondaryLUTFilter {
            secondaryFilter.setValue(processedImage, forKey: kCIInputImageKey)
            if let secondaryOutput = secondaryFilter.outputImage {
                if settings.secondaryLUTOpacity >= 1.0 {
                    // Full opacity - use secondary output directly
                    processedImage = secondaryOutput
                    print("   - ✅ Secondary LUT applied at 100% opacity (direct)")
                } else {
                    // Use CISourceOverCompositing for proper opacity blending
                    if let blendFilter = CIFilter(name: "CISourceOverCompositing") {
                        // First, apply opacity to the LUT output using CIColorMatrix
                        if let opacityFilter = CIFilter(name: "CIColorMatrix") {
                            opacityFilter.setValue(secondaryOutput, forKey: kCIInputImageKey)
                            opacityFilter.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
                            opacityFilter.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
                            opacityFilter.setValue(CIVector(x: 0, y: 0, z: 1, w: 0), forKey: "inputBVector")
                            opacityFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: CGFloat(settings.secondaryLUTOpacity)), forKey: "inputAVector")
                            opacityFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBiasVector")
                            
                            if let opacityOutput = opacityFilter.outputImage {
                                // Now blend the opacity-adjusted LUT output over the original
                                blendFilter.setValue(opacityOutput, forKey: kCIInputImageKey)
                                blendFilter.setValue(processedImage, forKey: kCIInputBackgroundImageKey)
                                
                                if let blendedOutput = blendFilter.outputImage {
                                    processedImage = blendedOutput
                                    print("   - ✅ Secondary LUT applied with \(Int(settings.secondaryLUTOpacity * 100))% opacity (direct)")
                                } else {
                                    print("   - ❌ Secondary LUT blend failed, using primary only")
                                }
                            } else {
                                print("   - ❌ Secondary LUT opacity adjustment failed, using primary only")
                            }
                        } else {
                            print("   - ❌ Could not create opacity filter for secondary LUT, using primary only")
                        }
                    } else {
                        print("   - ❌ Could not create blend filter for secondary LUT, using primary only")
                    }
                }
            } else {
                print("   - ❌ Secondary LUT failed to generate output")
            }
        }
        
        print("🎨 LUT Processor (Direct): Image processing completed")
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
        
        // Load LUT filters FIRST - this is critical
        try loadLUTFilters(settings: settings)
        print("🎨 LUT Processor: LUT filters loaded successfully")
        
        // Use direct frame-by-frame processing for guaranteed LUT application
        try await processVideoFrameByFrame(videoURL: videoURL, outputURL: outputURL, settings: settings)
        
        updateStatus("Video processing completed")
    }
    
    private func processVideoFrameByFrame(videoURL: URL, outputURL: URL, settings: LUTSettings) async throws {
        let asset = AVAsset(url: videoURL)
        
        // Remove existing output file
        try? FileManager.default.removeItem(at: outputURL)
        
        // Set up asset reader
        let assetReader = try AVAssetReader(asset: asset)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw LUTProcessingError.videoProcessingFailed("No video track found")
        }
        
        let naturalSize = try await videoTrack.load(.naturalSize)
        let outputSize = settings.outputQuality.outputSize(from: naturalSize)
        
        print("🎬 Processing video: \(Int(naturalSize.width))x\(Int(naturalSize.height)) → \(Int(outputSize.width))x\(Int(outputSize.height))")
        print("📊 Quality: \(settings.outputQuality)")
        print("📊 Codec: \(settings.outputQuality.codec.rawValue)")
        print("📊 Bitrate: \(settings.outputQuality.bitRate / 1_000_000)Mbps")
        
        let readerOutputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        
        let assetReaderOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: readerOutputSettings)
        assetReader.add(assetReaderOutput)
        
        // Set up asset writer with enhanced quality settings
        let assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        
        // Create base compression properties
        var compressionProperties: [String: Any] = [
            AVVideoAverageBitRateKey: settings.outputQuality.bitRate,
            AVVideoProfileLevelKey: settings.outputQuality.profileLevel,
            AVVideoH264EntropyModeKey: AVVideoH264EntropyModeCABAC,
            AVVideoExpectedSourceFrameRateKey: 30,
            AVVideoMaxKeyFrameIntervalKey: settings.outputQuality.keyFrameInterval,
            AVVideoQualityKey: settings.outputQuality.compressionQuality
        ]
        
        // Add wide color properties only for maximum quality to avoid codec compatibility issues
        if settings.outputQuality == .maximum {
            compressionProperties[AVVideoAllowWideColorKey] = true
            compressionProperties[AVVideoColorPrimariesKey] = AVVideoColorPrimaries_ITU_R_2020
        }
        
        let writerInputSettings: [String: Any] = [
            AVVideoCodecKey: settings.outputQuality.codec,
            AVVideoWidthKey: outputSize.width,
            AVVideoHeightKey: outputSize.height,
            AVVideoCompressionPropertiesKey: compressionProperties
        ]
        
        let assetWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: writerInputSettings)
        assetWriterInput.expectsMediaDataInRealTime = false
        
        // Enhanced pixel buffer attributes
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(outputSize.width),
            kCVPixelBufferHeightKey as String: Int(outputSize.height),
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: assetWriterInput,
            sourcePixelBufferAttributes: pixelBufferAttributes
        )
        
        assetWriter.add(assetWriterInput)
        
        // Start reading and writing
        guard assetReader.startReading() else {
            let error = assetReader.error?.localizedDescription ?? "Unknown reader error"
            throw LUTProcessingError.videoProcessingFailed("Could not start reading asset: \(error)")
        }
        
        guard assetWriter.startWriting() else {
            let error = assetWriter.error?.localizedDescription ?? "Unknown writer error"
            throw LUTProcessingError.exportFailed("Could not start writing asset: \(error)")
        }
        
        assetWriter.startSession(atSourceTime: .zero)
        
        let duration = try await asset.load(.duration)
        var frameCount = 0
        let totalFrames = Int(duration.seconds * 30) // Estimate based on 30fps
        
        print("🎬 Starting frame-by-frame processing for \(totalFrames) frames...")
        
        // Process frames with better error handling and memory management
        var shouldContinue = true
        while assetReader.status == .reading && shouldContinue {
            autoreleasepool {
                if assetWriterInput.isReadyForMoreMediaData {
                    if let sampleBuffer = assetReaderOutput.copyNextSampleBuffer() {
                        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
                        
                        // Apply LUT processing to this frame
                        let inputImage = CIImage(cvPixelBuffer: pixelBuffer)
                        let processedImage = processImage(inputImage, settings: settings) ?? inputImage
                        
                        // Scale image to output size if needed
                        let finalImage: CIImage
                        if outputSize != naturalSize {
                            let scaleX = outputSize.width / naturalSize.width
                            let scaleY = outputSize.height / naturalSize.height
                            finalImage = processedImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
                        } else {
                            finalImage = processedImage
                        }
                        
                        // Create output pixel buffer with better error handling
                        var outputPixelBuffer: CVPixelBuffer?
                        let poolStatus = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferAdaptor.pixelBufferPool!, &outputPixelBuffer)
                        
                        if poolStatus != kCVReturnSuccess {
                            print("❌ Failed to create pixel buffer from pool: \(poolStatus)")
                            return
                        }
                        
                        guard let finalPixelBuffer = outputPixelBuffer else {
                            print("❌ Created pixel buffer is nil")
                            return
                        }
                        
                        // Render processed image to output buffer
                        context.render(finalImage, to: finalPixelBuffer)
                        
                        // Get presentation time
                        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                        
                        // Append to writer with error checking
                        let appendSuccess = pixelBufferAdaptor.append(finalPixelBuffer, withPresentationTime: presentationTime)
                        if !appendSuccess {
                            print("❌ Failed to append pixel buffer at frame \(frameCount)")
                            if let writerError = assetWriter.error {
                                print("❌ Writer error: \(writerError.localizedDescription)")
                            }
                        }
                        
                        frameCount += 1
                        if frameCount % 30 == 0 { // Update progress every 30 frames
                            let progress = Double(frameCount) / Double(totalFrames)
                            updateProgress(min(0.9, progress)) // Cap at 90% until completion
                            print("🎬 Processed frame \(frameCount)/\(totalFrames) (\(Int(progress * 100))%)")
                        }
                        
                        // Force memory cleanup for 4K processing
                        if frameCount % 60 == 0 {
                            CFRunLoopRunInMode(.defaultMode, 0, false)
                        }
                    } else {
                        // No more frames
                        shouldContinue = false
                    }
                } else {
                    // Wait a bit for the writer to be ready
                    Thread.sleep(forTimeInterval: 0.01) // 10ms
                }
            }
        }
        
        print("🎬 Finished processing \(frameCount) frames")
        
        // Check for reader errors
        if assetReader.status == .failed {
            let error = assetReader.error?.localizedDescription ?? "Unknown reader error"
            throw LUTProcessingError.videoProcessingFailed("Asset reader failed: \(error)")
        }
        
        // Finish writing
        assetWriterInput.markAsFinished()
        await assetWriter.finishWriting()
        
        updateProgress(1.0)
        
        // Check final status
        if assetWriter.status == .failed {
            let error = assetWriter.error?.localizedDescription ?? "Unknown writer error"
            throw LUTProcessingError.exportFailed("Asset writer failed: \(error)")
        } else if assetWriter.status != .completed {
            throw LUTProcessingError.exportFailed("Asset writer finished with unexpected status: \(assetWriter.status.rawValue)")
        }
        
        print("✅ LUT Processor: Frame-by-frame processing completed successfully")
    }
    
    private func createVideoComposition(asset: AVAsset, settings: LUTSettings) async throws -> AVVideoComposition {
        let composition = AVMutableVideoComposition()
        
        // Get video track
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw LUTProcessingError.videoProcessingFailed("No video track found")
        }
        
        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let frameRate = try await videoTrack.load(.nominalFrameRate)
        
        composition.renderSize = naturalSize
        composition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        
        // Create video composition instruction
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: try await asset.load(.duration))
        
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        layerInstruction.setTransform(transform, at: .zero)
        
        instruction.layerInstructions = [layerInstruction]
        composition.instructions = [instruction]
        
        // CRITICAL: Apply LUT processing to each frame
        composition.customVideoCompositorClass = LUTVideoCompositor.self
        
        // Store settings in the composition for the compositor to use
        let settingsData = try NSKeyedArchiver.archivedData(withRootObject: [
            "primaryLUTURL": settings.primaryLUTURL?.absoluteString ?? "",
            "secondaryLUTURL": settings.secondaryLUTURL?.absoluteString ?? "",
            "secondaryLUTOpacity": settings.secondaryLUTOpacity,
            "whiteBalanceAdjustment": settings.whiteBalanceAdjustment,
            "useGPUProcessing": settings.useGPUProcessing
        ], requiringSecureCoding: false)
        
        composition.setValue(settingsData, forKey: "lutSettings")
        
        // Apply LUT processing
        composition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        
        return composition
    }
    
    private func exportVideo(asset: AVAsset, composition: AVVideoComposition, outputURL: URL, settings: LUTSettings) async throws {
        // Remove existing file if it exists
        try? FileManager.default.removeItem(at: outputURL)
        
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: settings.outputQuality.exportPreset) else {
            throw LUTProcessingError.exportFailed("Could not create export session")
        }
        
        exportSession.videoComposition = composition
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = settings.outputQuality != .maximum // Only optimize for non-maximum quality
        
        // For maximum quality, preserve metadata
        if settings.outputQuality == .maximum {
            exportSession.metadataItemFilter = AVMetadataItemFilter.forSharing()
        }
        
        await exportSession.export()
        
        guard exportSession.status == .completed else {
            let error = exportSession.error?.localizedDescription ?? "Unknown error"
            throw LUTProcessingError.exportFailed(error)
        }
    }
    
    // MARK: - Preview Generation
    func generatePreview(from videoURL: URL, settings: LUTSettings) async throws -> CIImage {
        print("🎨 LUT Processor: Starting preview generation...")
        
        // CRITICAL: Load LUT filters before processing
        try loadLUTFilters(settings: settings)
        print("✅ LUT filters loaded for preview generation")
        
        let asset = AVAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        
        let time = CMTime(seconds: 1.0, preferredTimescale: 600)
        let cgImage = try await generator.image(at: time).image
        
        let ciImage = CIImage(cgImage: cgImage)
        print("🎨 Applying LUT processing to preview image...")
        
        // Apply LUT processing using simplified direct method
        let processedImage = processImageDirect(ciImage, settings: settings)
        
        if processedImage != nil {
            print("✅ LUT processing applied successfully to preview")
        } else {
            print("⚠️ LUT processing returned nil, using original image")
        }
        
        return processedImage ?? ciImage
    }
    
    // MARK: - Time-Specific Preview Generation for Scrubbing
    func generatePreviewAtTime(from videoURL: URL, timeSeconds: Double, settings: LUTSettings) async throws -> CIImage {
        print("🎨 LUT Processor: Starting preview generation at \(timeSeconds)s...")
        
        // CRITICAL: Load LUT filters before processing
        try loadLUTFilters(settings: settings)
        print("✅ LUT filters loaded for preview generation at \(timeSeconds)s")
        
        let asset = AVAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        
        let time = CMTime(seconds: timeSeconds, preferredTimescale: 600)
        let cgImage = try await generator.image(at: time).image
        
        let ciImage = CIImage(cgImage: cgImage)
        print("🎨 Applying LUT processing to preview image at \(timeSeconds)s...")
        
        // Apply LUT processing using simplified direct method
        let processedImage = processImageDirect(ciImage, settings: settings)
        
        if processedImage != nil {
            print("✅ LUT processing applied successfully to preview at \(timeSeconds)s")
        } else {
            print("⚠️ LUT processing returned nil at \(timeSeconds)s, using original image")
        }
        
        return processedImage ?? ciImage
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