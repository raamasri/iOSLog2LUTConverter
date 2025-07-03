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
    @Published var statusMessage: String = "Ready to import videos"
    
    // MARK: - Background Processing
    @Published var backgroundExportProgress: [String: Double] = [:]
    @Published var canExportInBackground: Bool = false
    
    // MARK: - Recent Projects (iOS Enhancement)
    @Published var recentProjects: [RecentProject] = []
    @Published var favoriteProjects: [FavoriteProject] = []
    
    // MARK: - Debug/Test Mode
    @Published var isDebugMode = false
    private var debugModeEnabled: Bool {
        // Enable debug mode with a triple tap or set this to true for testing
        return true  // Set to false for production
    }
    
    func enableDebugMode() {
        guard debugModeEnabled else { return }
        
        print("🧪 Debug Mode: Initializing test environment...")
        isDebugMode = true
        
        // Load test video from Resources/testfootage/test.mp4
        loadTestVideo()
        
        // Auto-select first primary and secondary LUTs
        autoSelectTestLUTs()
        
        updateStatus("Debug mode: Test video and LUTs loaded")
        print("🧪 Debug Mode: Environment ready for testing")
    }
    
    private func loadTestVideo() {
        // Try compatible test video first (iOS-friendly 8-bit H.264)
        let compatibleVideoPath = "/Users/raamasrivatsan/xcode/iOSLOG2LUTConverter/iOSLOG2LUTConverter/Resources/testfootage/test_compatible.mp4"
        let compatibleVideoURL = URL(fileURLWithPath: compatibleVideoPath)
        
        if FileManager.default.fileExists(atPath: compatibleVideoPath) {
            print("✅ Debug Mode: Loading compatible test video from \(compatibleVideoURL.path)")
            addVideoURL(compatibleVideoURL)
            return
        }
        
        // Fallback to original video (may have compatibility issues)
        let testVideoPath = "/Users/raamasrivatsan/xcode/iOSLOG2LUTConverter/iOSLOG2LUTConverter/Resources/testfootage/test.MP4"
        let testVideoURL = URL(fileURLWithPath: testVideoPath)
        
        if FileManager.default.fileExists(atPath: testVideoPath) {
            print("⚠️ Debug Mode: Loading original test video (may have compatibility issues) from \(testVideoURL.path)")
            addVideoURL(testVideoURL)
        } else {
            // Try bundle resource as fallback
            if let bundleURL = Bundle.main.url(forResource: "test_compatible", withExtension: "mp4", subdirectory: "Resources/testfootage") ??
                              Bundle.main.url(forResource: "test", withExtension: "MP4", subdirectory: "Resources/testfootage") ??
                              Bundle.main.url(forResource: "test", withExtension: "mp4", subdirectory: "Resources/testfootage") {
                print("✅ Debug Mode: Loading test video from bundle: \(bundleURL.path)")
                addVideoURL(bundleURL)
            } else {
                print("❌ Debug Mode: No test video found")
                print("❌ Tried: \(compatibleVideoPath)")
                print("❌ Tried: \(testVideoPath)")
                print("❌ Also not found in bundle Resources/testfootage/")
            }
        }
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
        return !videoURLs.isEmpty && primaryLUTURL != nil
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
        if !videoURLs.contains(url) {
            videoURLs.append(url)
            updateStatus("Added video: \(url.lastPathComponent)")
        }
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
            updateStatus("Set primary LUT: \(url.lastPathComponent)")
        } else {
            updateStatus("Cleared primary LUT")
        }
        generatePreview()
    }
    
    func setSecondaryLUT(_ url: URL?) {
        secondaryLUTURL = url
        if let url = url {
            updateStatus("Set secondary LUT: \(url.lastPathComponent)")
        } else {
            updateStatus("Cleared secondary LUT")
        }
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
        guard isReadyForPreview else { 
            previewImage = nil
            return 
        }
        
        print("🖼️ ProjectState: Generating preview...")
        isPreviewLoading = true
        updateStatus("Generating preview...")
        
        Task {
            do {
                let videoURL = videoURLs[0]
                
                // Detailed video analysis for debugging
                print("🔍 Video Analysis:")
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
                    
                    if let formatDesc = formatDescriptions.first {
                        let mediaSubType = CMFormatDescriptionGetMediaSubType(formatDesc)
                        let fourCC = String(format: "%c%c%c%c", 
                                          (mediaSubType >> 24) & 0xFF,
                                          (mediaSubType >> 16) & 0xFF, 
                                          (mediaSubType >> 8) & 0xFF,
                                          mediaSubType & 0xFF)
                        print("   - Codec: \(fourCC)")
                    }
                }
                
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
                generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
                
                // Try different strategies for problematic videos
                let timePositions = [0.1, 0.5, 1.0, 2.0, duration.seconds * 0.1]
                var lastError: Error?
                
                for (index, timePosition) in timePositions.enumerated() {
                    guard timePosition < duration.seconds && timePosition >= 0 else { continue }
                    
                    let time = CMTime(seconds: timePosition, preferredTimescale: 600)
                    
                    do {
                        print("🎬 Attempt \(index + 1): Generating image at \(timePosition) seconds...")
                        let result = try await generator.image(at: time)
                        let cgImage = result.image
                        let previewUIImage = UIImage(cgImage: cgImage)
                        
                        await MainActor.run {
                            self.previewImage = previewUIImage
                            self.isPreviewLoading = false
                            self.updateStatus("Preview generated at \(String(format: "%.1f", timePosition))s")
                            print("✅ ProjectState: Preview generated successfully at \(timePosition)s")
                        }
                        return // Success, exit
                        
                    } catch {
                        print("❌ Attempt \(index + 1) failed: \(error.localizedDescription)")
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
                
                // If all attempts failed, throw the last error
                throw lastError ?? NSError(domain: "PreviewError", code: -1, userInfo: [NSLocalizedDescriptionKey: "All preview generation attempts failed"])
                
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
}

// MARK: - Supporting Types
enum ExportQuality: String, CaseIterable, Codable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case maximum = "Maximum"
    
    var description: String {
        switch self {
        case .low: return "Low (Fast, smaller file)"
        case .medium: return "Medium (Balanced)"
        case .high: return "High (Recommended)"
        case .maximum: return "Maximum (Slow, largest file)"
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