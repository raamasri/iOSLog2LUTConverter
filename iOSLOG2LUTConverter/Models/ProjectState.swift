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
        // Try both .mp4 and .MP4 extensions
        let testVideoURL = Bundle.main.url(forResource: "test", withExtension: "mp4", subdirectory: "testfootage") ??
                          Bundle.main.url(forResource: "test", withExtension: "MP4", subdirectory: "testfootage")
        
        guard let videoURL = testVideoURL else {
            print("❌ Debug Mode: test video not found in Resources/testfootage/ (tried .mp4 and .MP4)")
            return
        }
        
        print("✅ Debug Mode: Loading test video from \(videoURL.path)")
        addVideoURL(videoURL)
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
        
        // Simplified preview generation - will be enhanced later
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.isPreviewLoading = false
            self.updateStatus("Preview ready - real-time preview coming soon")
            print("✅ ProjectState: Preview placeholder ready")
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