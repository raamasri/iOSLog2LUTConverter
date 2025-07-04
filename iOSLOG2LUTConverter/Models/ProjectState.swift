import Foundation
import SwiftUI
import Combine
import AVFoundation
import UIKit

// MARK: - Enhanced ProjectState for iOS Migration
@MainActor
class ProjectState: ObservableObject {
    
    // MARK: - Core Properties (Migrated from macOS)
    @Published var videoURLs: [URL] = []
    @Published var primaryLUTURL: URL?
    @Published var secondaryLUTURL: URL?
    @Published var primaryLUTOpacity: Float = 1.0
    @Published var secondLUTOpacity: Float = 1.0
    @Published var useGPU: Bool = true
    @Published var whiteBalanceValue: Float = 0.0
    
    // MARK: - iOS-Specific Properties
    @Published var isExporting: Bool = false
    @Published var currentProgress: Double = 0.0
    @Published var overallProgress: Double = 0.0
    @Published var exportQuality: ExportQuality = .high
    @Published var shouldOptimizeForBattery: Bool = true
    @Published var isPreviewLoading: Bool = false
    @Published var previewImage: UIImage?
    @Published var rawPreviewImage: UIImage? // Raw preview without LUTs
    @Published var statusMessage: String = "Ready to import videos"
    @Published var showBeforeAfter: Bool = false // Toggle for before/after view
    
    // MARK: - Video Scrubbing Properties
    @Published var currentTime: Double = 0.0 // Current scrub position in seconds
    @Published var videoDuration: Double = 0.0 // Total video duration in seconds
    @Published var isScrubbing: Bool = false // Whether user is actively scrubbing
    
    // MARK: - Background Processing
    @Published var backgroundExportProgress: [String: Double] = [:]
    @Published var canExportInBackground: Bool = false
    
    // MARK: - Recent Projects (iOS Enhancement)
    @Published var recentProjects: [RecentProject] = []
    @Published var favoriteProjects: [FavoriteProject] = []
    
    // MARK: - Debug/Test Mode
    @Published var isDebugMode = false
    
    func enableDebugMode() {
        print("🧪 Debug Mode: Initializing test environment...")
        isDebugMode = true
        
        // Load test video from Resources/testfootage/
        loadTestVideo()
        
        // Auto-select first primary and secondary LUTs
        autoSelectTestLUTs()
        
        updateStatus("Debug mode: Test video and LUTs loaded")
        print("🧪 Debug Mode: Environment ready for testing")
    }
    
    private func loadTestVideo() {
        // Try Apple Log test video first (primary test video)
        if let bundleURL = Bundle.main.url(forResource: "applelogtest", withExtension: "mov", subdirectory: "Resources/testfootage") {
            print("✅ Debug Mode: Loading Apple Log test video from bundle: \(bundleURL.path)")
            addVideoURL(bundleURL)
            return
        }
        
        // Fallback to compatible test video (iOS-friendly 8-bit H.264)
        if let bundleURL = Bundle.main.url(forResource: "test_compatible", withExtension: "mp4", subdirectory: "Resources/testfootage") {
            print("✅ Debug Mode: Loading compatible test video from bundle: \(bundleURL.path)")
            addVideoURL(bundleURL)
            return
        }
        
        // Fallback to original test video
        if let bundleURL = Bundle.main.url(forResource: "test", withExtension: "MP4", subdirectory: "Resources/testfootage") ??
                          Bundle.main.url(forResource: "test", withExtension: "mp4", subdirectory: "Resources/testfootage") {
            print("⚠️ Debug Mode: Loading original test video from bundle: \(bundleURL.path)")
            addVideoURL(bundleURL)
            return
        }
        
        print("❌ Debug Mode: No test video found in bundle")
        print("❌ Tried: applelogtest.mov")
        print("❌ Tried: test_compatible.mp4")
        print("❌ Tried: test.MP4")
    }
    
    private func autoSelectTestLUTs() {
        // This will be called after LUTManager loads the LUTs
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // Auto-select first available LUTs for testing
            print("🧪 Debug Mode: Auto-selecting test LUTs...")
            self.autoSelectLUTsIfAvailable()
        }
    }
    
    func autoSelectLUTsIfAvailable() {
        // This method will be called from ContentView after LUTManager is loaded
    }
    
    // MARK: - Computed Properties
    var isReadyForPreview: Bool {
        return !videoURLs.isEmpty  // Only need video for preview, LUTs are optional
    }
    
    var isReadyForExport: Bool {
        return isReadyForPreview && !isExporting
    }
    
    var hasSecondaryLUT: Bool {
        return secondaryLUTURL != nil
    }
    
    var opacityPercentage: Int {
        return Int(secondLUTOpacity * 100)
    }
    
    var formattedWhiteBalance: String {
        let baseTemp = 5500
        let tempChange = Int(whiteBalanceValue * 280)
        let finalTemp = baseTemp + tempChange
        return "\(finalTemp)K"
    }
    
    var estimatedExportTime: TimeInterval {
        guard let firstVideo = videoURLs.first else { return 0.0 }
        
        let asset = AVAsset(url: firstVideo)
        let duration = asset.duration.seconds
        
        // Estimate based on duration and device performance
        // iOS devices typically process 1 second of video in 0.5-2 seconds
        let processingMultiplier: Double = useGPU ? 0.5 : 1.5
        return duration * processingMultiplier * Double(videoURLs.count)
    }
    
    var estimatedFileSize: Int64 {
        // Estimate based on video count and quality setting
        let baseSize: Int64 = 100_000_000 // 100MB base estimate
        let qualityMultiplier: Double = {
            switch exportQuality {
            case .low: return 0.5
            case .medium: return 0.8
            case .high: return 1.0
            case .maximum: return 1.5
            }
        }()
        
        return Int64(Double(baseSize) * qualityMultiplier * Double(videoURLs.count))
    }
    
    // MARK: - File Management (Migrated from macOS)
    func addVideoURL(_ url: URL) {
        // For professional video editing, allow replacing videos
        // Clear existing videos first, then add the new one
        if !videoURLs.isEmpty {
            print("🔄 ProjectState: Replacing existing video with new one")
            videoURLs.removeAll()
        }
        
        videoURLs.append(url)
        updateStatus("Added video: \(url.lastPathComponent)")
        print("🎬 ProjectState: Video added - \(url.lastPathComponent)")
        
        // Load video duration for scrubbing
        Task {
            await loadVideoDuration(from: url)
        }
        
        // Force immediate preview generation
        print("🔄 ProjectState: Forcing preview generation after video addition...")
        generatePreview()
    }
    
    // MARK: - Video Scrubbing Methods
    private func loadVideoDuration(from url: URL) async {
        do {
            let asset = AVAsset(url: url)
            let duration = try await asset.load(.duration)
            let durationSeconds = duration.seconds
            
            await MainActor.run {
                self.videoDuration = durationSeconds
                self.currentTime = 0.0 // Reset to beginning
                print("🎬 Video duration loaded: \(durationSeconds) seconds")
            }
        } catch {
            print("❌ Failed to load video duration: \(error.localizedDescription)")
            await MainActor.run {
                self.videoDuration = 0.0
            }
        }
    }
    
    func scrubToTime(_ time: Double) {
        guard videoDuration > 0 else { return }
        
        // Clamp time to valid range
        let clampedTime = max(0.0, min(time, videoDuration))
        currentTime = clampedTime
        
        print("🎯 Scrubbing to time: \(clampedTime)s")
        
        // Generate preview at this specific time
        generatePreviewAtTime(clampedTime)
    }
    
    func generatePreviewAtTime(_ timeSeconds: Double) {
        guard !videoURLs.isEmpty else { return }
        
        print("🎬 Generating preview at \(timeSeconds)s")
        isPreviewLoading = true
        isScrubbing = true
        
        Task {
            do {
                let videoURL = videoURLs[0]
                
                // Generate raw preview at specific time
                let rawPreview = try await generateRawPreviewAtTime(videoURL: videoURL, timeSeconds: timeSeconds)
                
                // Generate LUT-processed preview if LUTs are selected
                if primaryLUTURL != nil || secondaryLUTURL != nil {
                    let videoProcessor = VideoProcessor()
                    
                    let lutOutputQuality: LUTProcessor.OutputQuality = {
                        switch exportQuality {
                        case .low: return .low
                        case .medium: return .medium
                        case .high: return .high
                        case .maximum: return .maximum
                        }
                    }()
                    
                    let settings = VideoProcessor.ProcessingConfig(
                        videoURLs: [videoURL],
                        primaryLUTURL: primaryLUTURL,
                        secondaryLUTURL: secondaryLUTURL,
                        primaryLUTOpacity: Float(primaryLUTOpacity),
                        secondaryLUTOpacity: Float(secondLUTOpacity),
                        whiteBalanceAdjustment: Float(whiteBalanceValue),
                        useGPUProcessing: useGPU,
                        outputQuality: lutOutputQuality,
                        outputDirectory: FileManager.default.temporaryDirectory
                    )
                    
                    let processedPreview = try await videoProcessor.generatePreviewAtTime(
                        videoURL: videoURL, 
                        timeSeconds: timeSeconds, 
                        settings: settings
                    )
                    
                    await MainActor.run {
                        self.rawPreviewImage = rawPreview
                        self.previewImage = processedPreview
                        self.isPreviewLoading = false
                        self.isScrubbing = false
                        print("✅ Preview generated at \(timeSeconds)s with LUTs")
                    }
                } else {
                    await MainActor.run {
                        self.rawPreviewImage = rawPreview
                        self.previewImage = rawPreview
                        self.isPreviewLoading = false
                        self.isScrubbing = false
                        print("✅ Raw preview generated at \(timeSeconds)s")
                    }
                }
                
            } catch {
                await MainActor.run {
                    self.isPreviewLoading = false
                    self.isScrubbing = false
                    print("❌ Failed to generate preview at \(timeSeconds)s: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func generateRawPreviewAtTime(videoURL: URL, timeSeconds: Double) async throws -> UIImage {
        let asset = AVAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        
        let time = CMTime(seconds: timeSeconds, preferredTimescale: 600)
        
        do {
            let result = try await generator.image(at: time)
            let cgImage = result.image
            return UIImage(cgImage: cgImage)
        } catch {
            print("❌ Failed to generate raw preview at \(timeSeconds)s: \(error.localizedDescription)")
            throw error
        }
    }
    
    // MARK: - Debug Methods
    func forcePreviewGeneration() {
        print("🔄 ProjectState: Force preview generation requested")
        print("   - Current state: videoURLs=\(videoURLs.count), primaryLUT=\(primaryLUTURL != nil), secondaryLUT=\(secondaryLUTURL != nil)")
        generatePreview()
    }
    
    func addVideoURLs(_ urls: [URL]) {
        let newURLs = urls.filter { !videoURLs.contains($0) }
        videoURLs.append(contentsOf: newURLs)
        updateStatus("Added \(newURLs.count) video(s)")
    }
    
    func removeVideoURL(_ url: URL) {
        videoURLs.removeAll { $0 == url }
        updateStatus("Removed video: \(url.lastPathComponent)")
    }
    
    func clearVideoURLs() {
        videoURLs.removeAll()
        updateStatus("Cleared all videos")
    }
    
    func setPrimaryLUT(_ url: URL?) {
        primaryLUTURL = url
        if let url = url {
            let lutName = url.deletingPathExtension().lastPathComponent
            updateStatus("Set primary LUT: \(url.lastPathComponent)")
            print("🎨 ===== PRIMARY LUT SELECTED =====")
            print("   - LUT Name: \(lutName)")
            print("   - File: \(url.lastPathComponent)")
            print("   - Path: \(url.path)")
            print("   - Opacity: \(Int(primaryLUTOpacity * 100))%")
            print("🎨 ===================================")
        } else {
            updateStatus("Cleared primary LUT")
            print("🎨 PRIMARY LUT CLEARED")
        }
        
        // Force preview regeneration with explicit logging
        print("🔄 PRIMARY LUT CHANGED: Forcing preview regeneration...")
        generatePreview()
    }
    
    func setSecondaryLUT(_ url: URL?) {
        secondaryLUTURL = url
        if let url = url {
            let lutName = url.deletingPathExtension().lastPathComponent
            updateStatus("Set secondary LUT: \(url.lastPathComponent)")
            print("🎭 ===== SECONDARY LUT SELECTED =====")
            print("   - LUT Name: \(lutName)")
            print("   - File: \(url.lastPathComponent)")
            print("   - Path: \(url.path)")
            print("   - Opacity: \(Int(secondLUTOpacity * 100))%")
            print("🎭 ====================================")
        } else {
            updateStatus("Cleared secondary LUT")
            print("🎭 SECONDARY LUT CLEARED")
        }
        
        // Force preview regeneration with explicit logging
        print("🔄 SECONDARY LUT CHANGED: Forcing preview regeneration...")
        generatePreview()
    }
    
    // MARK: - Progress Management (Migrated from macOS)
    func updateProgress(_ progress: Double) {
        currentProgress = max(0.0, min(1.0, progress))
    }
    
    func updateOverallProgress(_ progress: Double) {
        overallProgress = max(0.0, min(1.0, progress))
    }
    
    func resetProgress() {
        currentProgress = 0.0
        overallProgress = 0.0
        updateStatus("Ready to export")
    }
    
    // MARK: - Export File Naming (Migrated from macOS)
    func generateOutputFileName(for videoURL: URL) -> String {
        let filename = videoURL.deletingPathExtension().lastPathComponent
        let secondaryLUTName = secondaryLUTURL?.deletingPathExtension().lastPathComponent ?? "NoSecondLUT"
        return "\(filename)_converted_\(secondaryLUTName)_\(opacityPercentage)percent.mp4"
    }
    
    // MARK: - Validation (Migrated from macOS)
    func validateConfiguration() -> ValidationResult {
        if videoURLs.isEmpty {
            return .failure("No video files selected")
        }
        
        if primaryLUTURL == nil {
            return .failure("No primary LUT selected")
        }
        
        return .success
    }
    
    // MARK: - iOS-Specific Methods
    func updateStatus(_ message: String) {
        statusMessage = message
        print("📱 Status: \(message)")
    }
    
    func generatePreview() {
        print("🖼️ ProjectState: generatePreview() called")
        print("   - isReadyForPreview: \(isReadyForPreview)")
        print("   - videoURLs count: \(videoURLs.count)")
        print("   - primaryLUTURL: \(primaryLUTURL?.lastPathComponent ?? "nil")")
        print("   - secondaryLUTURL: \(secondaryLUTURL?.lastPathComponent ?? "nil")")
        
        guard isReadyForPreview else { 
            print("❌ ProjectState: Not ready for preview, clearing preview image")
            previewImage = nil
            return 
        }
        
        print("🖼️ ProjectState: Starting preview generation...")
        isPreviewLoading = true
        updateStatus("Generating preview...")
        
        Task {
            do {
                let videoURL = videoURLs[0]
                
                // Comprehensive video analysis for HDR, 10-bit, color space, and Rec. 2020
                print("🔍 Comprehensive Video Analysis:")
                print("   - URL: \(videoURL.path)")
                print("   - File exists: \(FileManager.default.fileExists(atPath: videoURL.path))")
                
                let asset = AVAsset(url: videoURL)
                
                // Load asset properties for debugging
                let duration = try await asset.load(.duration)
                let tracks = try await asset.loadTracks(withMediaType: .video)
                
                print("   - Duration: \(duration.seconds) seconds")
                print("   - Video tracks: \(tracks.count)")
                
                if let videoTrack = tracks.first {
                    let naturalSize = try await videoTrack.load(.naturalSize)
                    let formatDescriptions = try await videoTrack.load(.formatDescriptions)
                    print("   - Resolution: \(naturalSize.width)x\(naturalSize.height)")
                    print("   - Format descriptions: \(formatDescriptions.count)")
                    
                    // Enhanced codec and format analysis
                    if let formatDesc = formatDescriptions.first {
                        let mediaSubType = CMFormatDescriptionGetMediaSubType(formatDesc)
                        let fourCC = String(format: "%c%c%c%c", 
                                          (mediaSubType >> 24) & 0xFF,
                                          (mediaSubType >> 16) & 0xFF, 
                                          (mediaSubType >> 8) & 0xFF,
                                          mediaSubType & 0xFF)
                        print("   - Codec: \(fourCC)")
                        
                        // Analyze pixel format for bit depth and color space
                        let pixelFormat = CMFormatDescriptionGetMediaSubType(formatDesc)
                        analyzePixelFormat(pixelFormat)
                        
                        // Check for HDR metadata
                        analyzeHDRMetadata(formatDesc)
                        
                        // Analyze color space and transfer function
                        analyzeColorSpace(formatDesc)
                    }
                    
                    // Check for Apple Log characteristics
                    analyzeAppleLogCharacteristics(videoTrack)
                }
                
                // Always generate raw preview first
                print("🎬 Generating raw frame preview (no LUTs applied)...")
                let rawPreview = try await generateRawPreview(videoURL: videoURL, duration: duration)
                
                // Use VideoProcessor for LUT-processed preview if LUTs are selected
                if primaryLUTURL != nil || secondaryLUTURL != nil {
                    print("🎨 Generating LUT-processed preview...")
                    let videoProcessor = VideoProcessor()
                    
                    // Convert ExportQuality to LUTProcessor.OutputQuality
                    let lutOutputQuality: LUTProcessor.OutputQuality = {
                        switch exportQuality {
                        case .low: return .low
                        case .medium: return .medium
                        case .high: return .high
                        case .maximum: return .maximum
                        }
                    }()
                    
                    let settings = VideoProcessor.ProcessingConfig(
                        videoURLs: [videoURL],
                        primaryLUTURL: primaryLUTURL,
                        secondaryLUTURL: secondaryLUTURL,
                        primaryLUTOpacity: Float(primaryLUTOpacity),
                        secondaryLUTOpacity: Float(secondLUTOpacity),
                        whiteBalanceAdjustment: Float(whiteBalanceValue),
                        useGPUProcessing: useGPU,
                        outputQuality: lutOutputQuality,
                        outputDirectory: FileManager.default.temporaryDirectory
                    )
                    
                    let processedPreview = try await videoProcessor.generatePreview(videoURL: videoURL, settings: settings)
                    
                    await MainActor.run {
                        self.rawPreviewImage = rawPreview
                        self.previewImage = processedPreview
                        self.isPreviewLoading = false
                        self.updateStatus("LUT preview generated")
                        print("✅ ProjectState: Both raw and LUT-processed previews generated successfully")
                    }
                    return
                } else {
                    // No LUTs selected, use raw preview as main preview
                    await MainActor.run {
                        self.rawPreviewImage = rawPreview
                        self.previewImage = rawPreview
                        self.isPreviewLoading = false
                        self.updateStatus("Raw preview generated")
                        print("✅ ProjectState: Raw preview generated (no LUTs)")
                    }
                    return
                }

                
            } catch {
                await MainActor.run {
                    self.isPreviewLoading = false
                    self.updateStatus("Preview generation failed: \(error.localizedDescription)")
                    print("❌ ProjectState: Preview generation failed: \(error.localizedDescription)")
                    
                    // Create a placeholder image for problematic videos
                    let placeholderImage = self.createPlaceholderImage()
                    self.previewImage = placeholderImage
                    print("📷 Created placeholder image for problematic video")
                }
            }
        }
    }
    
    // MARK: - Raw Preview Generation
    private func generateRawPreview(videoURL: URL, duration: CMTime) async throws -> UIImage {
        let asset = AVAsset(url: videoURL)
        
        // Create multiple generators with different configurations for maximum compatibility
        let generators = [
            createStandardImageGenerator(asset: asset),
            createCompatibilityImageGenerator(asset: asset),
            createLegacyImageGenerator(asset: asset)
        ]
        
        // Try different time positions
        let timePositions = [0.1, 0.5, 1.0, 2.0, duration.seconds * 0.1, duration.seconds * 0.05]
        var lastError: Error?
        
        for (genIndex, generator) in generators.enumerated() {
            print("🎬 Trying generator \(genIndex + 1) of \(generators.count)...")
            
            for (timeIndex, timePosition) in timePositions.enumerated() {
                guard timePosition < duration.seconds && timePosition >= 0 else { continue }
                
                let time = CMTime(seconds: timePosition, preferredTimescale: 600)
                
                do {
                    print("🎬 Generator \(genIndex + 1), Attempt \(timeIndex + 1): Generating raw frame at \(timePosition) seconds...")
                    let result = try await generator.image(at: time)
                    let cgImage = result.image
                    let previewUIImage = UIImage(cgImage: cgImage)
                    
                    print("✅ ProjectState: Raw preview generated successfully at \(timePosition)s with generator \(genIndex + 1)")
                    return previewUIImage
                    
                } catch {
                    print("❌ Generator \(genIndex + 1), Attempt \(timeIndex + 1) failed: \(error.localizedDescription)")
                    lastError = error
                    
                    // Print detailed error info
                    if let nsError = error as NSError? {
                        print("   - Domain: \(nsError.domain)")
                        print("   - Code: \(nsError.code)")
                        print("   - UserInfo: \(nsError.userInfo)")
                    }
                    continue
                }
            }
        }
        
        // If all attempts failed, throw the last error
        throw lastError ?? NSError(domain: "PreviewError", code: -1, userInfo: [NSLocalizedDescriptionKey: "All preview generation attempts failed"])
    }
    
    // MARK: - Enhanced Image Generator Methods for Professional Video Compatibility
    private func createStandardImageGenerator(asset: AVAsset) -> AVAssetImageGenerator {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        return generator
    }
    
    private func createCompatibilityImageGenerator(asset: AVAsset) -> AVAssetImageGenerator {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1.0, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 1.0, preferredTimescale: 600)
        // More aggressive tolerance for difficult formats
        generator.maximumSize = CGSize(width: 1920, height: 1080) // Limit size for compatibility
        return generator
    }
    
    private func createLegacyImageGenerator(asset: AVAsset) -> AVAssetImageGenerator {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceAfter = CMTime(seconds: 2.0, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 2.0, preferredTimescale: 600)
        // Maximum compatibility settings
        generator.maximumSize = CGSize(width: 1280, height: 720) // Even smaller for legacy compatibility
        generator.apertureMode = .cleanAperture
        return generator
    }
    
    func optimizeForBattery() {
        if shouldOptimizeForBattery {
            useGPU = false
            exportQuality = .medium
            updateStatus("Optimized for battery life")
        }
    }
    
    func resetToDefaults() {
        primaryLUTOpacity = 1.0
        secondLUTOpacity = 1.0
        whiteBalanceValue = 0.0
        useGPU = true
        exportQuality = .high
        shouldOptimizeForBattery = true
        updateStatus("Reset to defaults")
    }
    
    // MARK: - Helper Methods
    private func createPlaceholderImage() -> UIImage {
        let size = CGSize(width: 400, height: 300)
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        defer { UIGraphicsEndImageContext() }
        
        let context = UIGraphicsGetCurrentContext()!
        
        // Dark background
        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        
        // Gray border
        context.setStrokeColor(UIColor.gray.cgColor)
        context.setLineWidth(2.0)
        context.stroke(CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1))
        
        // Play icon in center
        let playIconSize: CGFloat = 60
        let playIconRect = CGRect(
            x: (size.width - playIconSize) / 2,
            y: (size.height - playIconSize) / 2,
            width: playIconSize,
            height: playIconSize
        )
        
        context.setFillColor(UIColor.white.cgColor)
        context.beginPath()
        context.move(to: CGPoint(x: playIconRect.minX + 15, y: playIconRect.minY + 10))
        context.addLine(to: CGPoint(x: playIconRect.maxX - 15, y: playIconRect.midY))
        context.addLine(to: CGPoint(x: playIconRect.minX + 15, y: playIconRect.maxY - 10))
        context.closePath()
        context.fillPath()
        
        return UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
    }
    
    // MARK: - Comprehensive Video Analysis Methods
    
    private func analyzePixelFormat(_ pixelFormat: FourCharCode) {
        print("🎨 Pixel Format Analysis:")
        
        let pixelFormatString = String(format: "%c%c%c%c", 
                                     (pixelFormat >> 24) & 0xFF,
                                     (pixelFormat >> 16) & 0xFF, 
                                     (pixelFormat >> 8) & 0xFF,
                                     pixelFormat & 0xFF)
        print("   - Pixel Format: \(pixelFormatString)")
        
        // Analyze bit depth and color space based on pixel format
        switch pixelFormat {
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
             kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            print("   - Bit Depth: 8-bit")
            print("   - Color Sampling: 4:2:0")
            print("   - HDR Support: ❌ No (8-bit limitation)")
            
        case kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
             kCVPixelFormatType_420YpCbCr10BiPlanarFullRange:
            print("   - Bit Depth: ✅ 10-bit (HDR capable)")
            print("   - Color Sampling: 4:2:0")
            print("   - HDR Support: ✅ Yes (10-bit support)")
            print("   - Apple Log Compatible: ✅ Yes")
            
        case kCVPixelFormatType_422YpCbCr8,
             kCVPixelFormatType_422YpCbCr8_yuvs:
            print("   - Bit Depth: 8-bit")
            print("   - Color Sampling: 4:2:2")
            print("   - HDR Support: ❌ No (8-bit limitation)")
            
        case kCVPixelFormatType_422YpCbCr10:
            print("   - Bit Depth: ✅ 10-bit (HDR capable)")
            print("   - Color Sampling: 4:2:2")
            print("   - HDR Support: ✅ Yes (10-bit support)")
            print("   - Apple Log Compatible: ✅ Yes")
            
        case kCVPixelFormatType_444YpCbCr8:
            print("   - Bit Depth: 8-bit")
            print("   - Color Sampling: 4:4:4")
            print("   - HDR Support: ❌ No (8-bit limitation)")
            
        case kCVPixelFormatType_444YpCbCr10:
            print("   - Bit Depth: ✅ 10-bit (HDR capable)")
            print("   - Color Sampling: 4:4:4")
            print("   - HDR Support: ✅ Yes (10-bit support)")
            print("   - Apple Log Compatible: ✅ Yes")
            
        default:
            print("   - Bit Depth: Unknown format")
            print("   - HDR Support: ⚠️ Unknown")
        }
    }
    
    private func analyzeHDRMetadata(_ formatDesc: CMFormatDescription) {
        print("🌈 HDR Metadata Analysis:")
        
        // Check for HDR extensions
        if let extensions = CMFormatDescriptionGetExtensions(formatDesc) as? [String: Any] {
            print("   - Format Extensions Found: \(extensions.keys.joined(separator: ", "))")
            
            // Check for color primaries
            if let colorPrimaries = extensions[kCVImageBufferColorPrimariesKey as String] as? String {
                print("   - Color Primaries: \(colorPrimaries)")
                
                if colorPrimaries == (kCVImageBufferColorPrimaries_ITU_R_2020 as String) {
                    print("   - Color Space: ✅ Rec. 2020 (Wide Color Gamut)")
                    print("   - HDR Ready: ✅ Yes")
                } else if colorPrimaries == (kCVImageBufferColorPrimaries_ITU_R_709_2 as String) {
                    print("   - Color Space: Rec. 709 (Standard)")
                    print("   - HDR Ready: ⚠️ Limited")
                } else if colorPrimaries == (kCVImageBufferColorPrimaries_P3_D65 as String) {
                    print("   - Color Space: Display P3 (Wide Color)")
                    print("   - HDR Ready: ⚠️ Partial")
                } else {
                    print("   - Color Space: \(colorPrimaries ?? "Unknown")")
                }
            } else {
                print("   - Color Primaries: ❌ Not specified")
            }
            
            // Check for transfer function
            if let transferFunction = extensions[kCVImageBufferTransferFunctionKey as String] as? String {
                print("   - Transfer Function: \(transferFunction)")
                
                if transferFunction == (kCVImageBufferTransferFunction_ITU_R_2100_HLG as String) {
                    print("   - HDR Type: ✅ HLG (Hybrid Log-Gamma)")
                } else if transferFunction == (kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String) {
                    print("   - HDR Type: ✅ PQ (Perceptual Quantizer)")
                } else if transferFunction == (kCVImageBufferTransferFunction_ITU_R_709_2 as String) {
                    print("   - HDR Type: ❌ Standard Gamma (SDR)")
                } else {
                    print("   - HDR Type: ⚠️ Unknown (\(transferFunction ?? "Unknown"))")
                }
            } else {
                print("   - Transfer Function: ❌ Not specified")
            }
            
            // Check for YCbCr matrix
            if let ycbcrMatrix = extensions[kCVImageBufferYCbCrMatrixKey as String] as? String {
                print("   - YCbCr Matrix: \(ycbcrMatrix)")
                
                if ycbcrMatrix == (kCVImageBufferYCbCrMatrix_ITU_R_2020 as String) {
                    print("   - Matrix Type: ✅ Rec. 2020")
                } else if ycbcrMatrix == (kCVImageBufferYCbCrMatrix_ITU_R_709_2 as String) {
                    print("   - Matrix Type: Rec. 709")
                } else {
                    print("   - Matrix Type: \(ycbcrMatrix ?? "Unknown")")
                }
            } else {
                print("   - YCbCr Matrix: ❌ Not specified")
            }
            
        } else {
            print("   - HDR Metadata: ❌ No extensions found")
        }
    }
    
    private func analyzeColorSpace(_ formatDesc: CMFormatDescription) {
        print("🎨 Color Space Analysis:")
        
        if let extensions = CMFormatDescriptionGetExtensions(formatDesc) as? [String: Any] {
            
            // Comprehensive color space analysis
            let colorPrimaries = extensions[kCVImageBufferColorPrimariesKey as String] as? String
            let transferFunction = extensions[kCVImageBufferTransferFunctionKey as String] as? String
            let ycbcrMatrix = extensions[kCVImageBufferYCbCrMatrixKey as String] as? String
            
            print("   - Complete Color Profile:")
            print("     • Primaries: \(colorPrimaries ?? "Unspecified")")
            print("     • Transfer: \(transferFunction ?? "Unspecified")")
            print("     • Matrix: \(ycbcrMatrix ?? "Unspecified")")
            
            // Check for Rec. 2020 compatibility
            let isRec2020 = colorPrimaries == (kCVImageBufferColorPrimaries_ITU_R_2020 as String)
            let isRec2020Matrix = ycbcrMatrix == (kCVImageBufferYCbCrMatrix_ITU_R_2020 as String)
            
            if isRec2020 && isRec2020Matrix {
                print("   - Rec. 2020 Support: ✅ Full (Primaries + Matrix)")
            } else if isRec2020 {
                print("   - Rec. 2020 Support: ⚠️ Partial (Primaries only)")
            } else {
                print("   - Rec. 2020 Support: ❌ No")
            }
            
            // Check for wide color gamut
            let hasWideGamut = colorPrimaries == (kCVImageBufferColorPrimaries_ITU_R_2020 as String) ||
                              colorPrimaries == (kCVImageBufferColorPrimaries_P3_D65 as String)
            print("   - Wide Color Gamut: \(hasWideGamut ? "✅ Yes" : "❌ No")")
            
        } else {
            print("   - Color Space: ❌ No metadata available")
        }
    }
    
    private func analyzeAppleLogCharacteristics(_ videoTrack: AVAssetTrack) {
        print("🍎 Apple Log Analysis:")
        
        Task {
            do {
                // Check format descriptions for Apple Log indicators
                let formatDescriptions = try await videoTrack.load(.formatDescriptions)
                
                for formatDesc in formatDescriptions {
                    if let extensions = CMFormatDescriptionGetExtensions(formatDesc) as? [String: Any] {
                        
                        // Check for Apple-specific metadata
                        let hasAppleExtensions = extensions.keys.contains { key in
                            key.lowercased().contains("apple") || 
                            key.lowercased().contains("log") ||
                            key.contains("com.apple")
                        }
                        
                        if hasAppleExtensions {
                            print("   - Apple Metadata: ✅ Found")
                            print("   - Apple Log Likelihood: ✅ High")
                        }
                        
                        // Check transfer function for log characteristics
                        if let transferFunction = extensions[kCVImageBufferTransferFunctionKey as String] as? String {
                            if transferFunction.lowercased().contains("log") {
                                print("   - Log Transfer Function: ✅ Detected")
                                print("   - Apple Log Compatible: ✅ Yes")
                            }
                        }
                        
                        // Check for 10-bit + wide gamut combination (Apple Log requirement)
                        let pixelFormat = CMFormatDescriptionGetMediaSubType(formatDesc)
                        let is10Bit = pixelFormat == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange ||
                                     pixelFormat == kCVPixelFormatType_420YpCbCr10BiPlanarFullRange ||
                                     pixelFormat == kCVPixelFormatType_422YpCbCr10 ||
                                     pixelFormat == kCVPixelFormatType_444YpCbCr10
                        
                        let colorPrimaries = extensions[kCVImageBufferColorPrimariesKey as String] as? String
                        let isWideGamut = colorPrimaries == (kCVImageBufferColorPrimaries_ITU_R_2020 as String) ||
                                         colorPrimaries == (kCVImageBufferColorPrimaries_P3_D65 as String)
                        
                        if is10Bit && isWideGamut {
                            print("   - Technical Requirements: ✅ Met (10-bit + Wide Gamut)")
                            print("   - Apple Log Processing: ✅ Recommended")
                        } else if is10Bit {
                            print("   - Technical Requirements: ⚠️ Partial (10-bit, limited gamut)")
                        } else {
                            print("   - Technical Requirements: ❌ Not met (8-bit)")
                        }
                    }
                }
                
                // Check filename for Apple Log indicators
                if let urlAsset = videoTrack.asset as? AVURLAsset {
                    let filename = urlAsset.url.lastPathComponent.lowercased()
                    if filename.contains("applelog") || filename.contains("apple_log") || filename.contains("log") {
                        print("   - Filename Indicator: ✅ Apple Log detected in filename")
                    }
                }
                
            } catch {
                print("   - Apple Log Analysis: ❌ Failed to analyze (\(error.localizedDescription))")
            }
        }
    }
}

// MARK: - Supporting Types
enum ExportQuality: String, CaseIterable, Codable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case maximum = "Maximum"
    
    var description: String {
        switch self {
        case .low: return "Low (Fast, 720p max, smaller files)"
        case .medium: return "Medium (Balanced, 1080p max)"
        case .high: return "High (Original resolution, recommended)"
        case .maximum: return "Max (Original data preserved, largest files)"
        }
    }
}

enum ValidationResult {
    case success
    case failure(String)
    
    var isValid: Bool {
        switch self {
        case .success: return true
        case .failure: return false
        }
    }
    
    var errorMessage: String? {
        switch self {
        case .success: return nil
        case .failure(let message): return message
        }
    }
}

// MARK: - Recent Projects (iOS Enhancement)
struct RecentProject: Identifiable, Codable {
    let id = UUID()
    let name: String
    let videoCount: Int
    let lutName: String
    let createdAt: Date
    let thumbnailData: Data?
}

struct FavoriteProject: Identifiable, Codable {
    let id = UUID()
    let name: String
    let videoURLs: [URL]
    let primaryLUTURL: URL
    let secondaryLUTURL: URL?
    let settings: ProjectSettings
}

struct ProjectSettings: Codable {
    let opacity: Float
    let whiteBalance: Float
    let useGPU: Bool
    let quality: ExportQuality
}

// MARK: - Extensions  
// Note: LUTProcessor.OutputQuality extension will be added when LUTProcessor is imported 