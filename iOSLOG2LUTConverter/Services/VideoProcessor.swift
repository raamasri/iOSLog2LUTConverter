import Foundation
import AVFoundation
import UIKit
import Combine

// MARK: - Main Video Processor (iOS Migration from FFmpeg)
@MainActor
class VideoProcessor: ObservableObject {
    
    // MARK: - Published Properties
    @Published var isExporting = false
    @Published var exportProgress: Double = 0.0
    @Published var currentVideoIndex = 0
    @Published var totalVideos = 0
    @Published var statusMessage = "Ready to process videos"
    @Published var estimatedTimeRemaining: TimeInterval = 0
    @Published var exportedVideoURLs: [URL] = []
    @Published var lastError: ProcessingError?
    
    // MARK: - Private Properties
    private let lutProcessor = LUTProcessor()
    private var cancellables = Set<AnyCancellable>()
    private var startTime: Date?
    
    // MARK: - Processing Configuration
    struct ProcessingConfig {
        let videoURLs: [URL]
        let primaryLUTURL: URL?
        let secondaryLUTURL: URL?
        let secondaryLUTOpacity: Float
        let whiteBalanceAdjustment: Float
        let useGPUProcessing: Bool
        let outputQuality: LUTProcessor.OutputQuality
        let outputDirectory: URL
    }
    
    // MARK: - Error Handling
    enum ProcessingError: LocalizedError {
        case noVideosSelected
        case noLUTSelected
        case processingFailed(String)
        case exportFailed(String)
        case cancelled
        
        var errorDescription: String? {
            switch self {
            case .noVideosSelected:
                return "No videos selected for processing"
            case .noLUTSelected:
                return "No LUT selected"
            case .processingFailed(let message):
                return "Processing failed: \(message)"
            case .exportFailed(let message):
                return "Export failed: \(message)"
            case .cancelled:
                return "Processing cancelled"
            }
        }
    }
    
    // MARK: - Initialization
    init() {
        setupSubscriptions()
    }
    
    private func setupSubscriptions() {
        // Subscribe to LUT processor updates
        lutProcessor.$processingProgress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                self?.updateOverallProgress(lutProgress: progress)
            }
            .store(in: &cancellables)
        
        lutProcessor.$processingStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.statusMessage = status
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Main Processing Method
    func processVideos(config: ProcessingConfig) async {
        guard !config.videoURLs.isEmpty else {
            await handleError(.noVideosSelected)
            return
        }
        
        guard config.primaryLUTURL != nil else {
            await handleError(.noLUTSelected)
            return
        }
        
        await startProcessing(config: config)
    }
    
    private func startProcessing(config: ProcessingConfig) async {
        isExporting = true
        exportProgress = 0.0
        currentVideoIndex = 0
        totalVideos = config.videoURLs.count
        exportedVideoURLs = []
        lastError = nil
        startTime = Date()
        
        updateStatus("Starting video processing...")
        
        // Create LUT settings
        let lutSettings = LUTProcessor.LUTSettings(
            primaryLUTURL: config.primaryLUTURL,
            secondaryLUTURL: config.secondaryLUTURL,
            secondaryLUTOpacity: config.secondaryLUTOpacity,
            whiteBalanceAdjustment: config.whiteBalanceAdjustment,
            useGPUProcessing: config.useGPUProcessing,
            outputQuality: config.outputQuality
        )
        
        // Process each video
        for (index, videoURL) in config.videoURLs.enumerated() {
            guard isExporting else { // Check if cancelled
                await handleError(.cancelled)
                return
            }
            
            currentVideoIndex = index
            updateStatus("Processing video \(index + 1) of \(totalVideos)")
            
            do {
                let outputURL = generateOutputURL(for: videoURL, in: config.outputDirectory, settings: lutSettings)
                try await lutProcessor.processVideo(videoURL, settings: lutSettings, outputURL: outputURL)
                
                exportedVideoURLs.append(outputURL)
                updateOverallProgress(videoIndex: index + 1)
                
            } catch {
                await handleError(.processingFailed(error.localizedDescription))
                return
            }
        }
        
        await finishProcessing()
    }
    
    // MARK: - Progress Management
    private func updateOverallProgress(videoIndex: Int? = nil, lutProgress: Double = 0.0) {
        let videoProgress = Double(videoIndex ?? currentVideoIndex) / Double(totalVideos)
        let currentVideoProgress = lutProgress / Double(totalVideos)
        
        exportProgress = min(1.0, videoProgress + currentVideoProgress)
        
        // Update estimated time remaining
        if let startTime = startTime, exportProgress > 0 {
            let elapsedTime = Date().timeIntervalSince(startTime)
            let estimatedTotalTime = elapsedTime / exportProgress
            estimatedTimeRemaining = max(0, estimatedTotalTime - elapsedTime)
        }
    }
    
    private func updateStatus(_ message: String) {
        statusMessage = message
        print("📹 Video Processor: \(message)")
    }
    
    // MARK: - File Management
    private func generateOutputURL(for videoURL: URL, in directory: URL, settings: LUTProcessor.LUTSettings) -> URL {
        let filename = videoURL.deletingPathExtension().lastPathComponent
        let primaryLUTName = settings.primaryLUTURL?.deletingPathExtension().lastPathComponent ?? "NoLUT"
        let secondaryLUTName = settings.secondaryLUTURL?.deletingPathExtension().lastPathComponent ?? "NoSecondLUT"
        let opacityPercent = Int(settings.secondaryLUTOpacity * 100)
        
        let outputFilename = "\(filename)_\(primaryLUTName)_\(secondaryLUTName)_\(opacityPercent)percent.mp4"
        
        return directory.appendingPathComponent(outputFilename)
    }
    
    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    // MARK: - Preview Generation
    func generatePreview(videoURL: URL, settings: ProcessingConfig) async throws -> UIImage {
        let lutSettings = LUTProcessor.LUTSettings(
            primaryLUTURL: settings.primaryLUTURL,
            secondaryLUTURL: settings.secondaryLUTURL,
            secondaryLUTOpacity: settings.secondaryLUTOpacity,
            whiteBalanceAdjustment: settings.whiteBalanceAdjustment,
            useGPUProcessing: settings.useGPUProcessing,
            outputQuality: settings.outputQuality
        )
        
        let ciImage = try await lutProcessor.generatePreview(from: videoURL, settings: lutSettings)
        
        // Convert CIImage to UIImage
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            throw ProcessingError.processingFailed("Could not generate preview image")
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    // MARK: - Cancellation
    func cancelProcessing() {
        guard isExporting else { return }
        
        isExporting = false
        updateStatus("Cancelling processing...")
        
        // Clean up any in-progress exports
        Task {
            await handleError(.cancelled)
        }
    }
    
    // MARK: - Error Handling
    private func handleError(_ error: ProcessingError) async {
        lastError = error
        isExporting = false
        updateStatus(error.localizedDescription ?? "Unknown error")
        
        // Reset progress
        exportProgress = 0.0
        currentVideoIndex = 0
        estimatedTimeRemaining = 0
    }
    
    // MARK: - Completion
    private func finishProcessing() async {
        isExporting = false
        exportProgress = 1.0
        
        let processingTime = startTime.map { Date().timeIntervalSince($0) } ?? 0
        updateStatus("Processing completed in \(Int(processingTime)) seconds")
        
        // Show completion notification
        await showCompletionNotification()
    }
    
    private func showCompletionNotification() async {
        // Request notification permission and show completion
        // This would be implemented based on app requirements
        print("🎉 Video processing completed! \(exportedVideoURLs.count) videos exported.")
    }
    
    // MARK: - Utility Methods
    func resetProcessor() {
        isExporting = false
        exportProgress = 0.0
        currentVideoIndex = 0
        totalVideos = 0
        statusMessage = "Ready to process videos"
        estimatedTimeRemaining = 0
        exportedVideoURLs = []
        lastError = nil
        startTime = nil
        
        lutProcessor.resetProgress()
    }
    
    func getFormattedTimeRemaining() -> String {
        guard estimatedTimeRemaining > 0 else { return "" }
        
        let hours = Int(estimatedTimeRemaining) / 3600
        let minutes = Int(estimatedTimeRemaining) % 3600 / 60
        let seconds = Int(estimatedTimeRemaining) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    func getProcessingStatusDescription() -> String {
        guard isExporting else { return statusMessage }
        
        let progressPercent = Int(exportProgress * 100)
        let timeRemaining = getFormattedTimeRemaining()
        
        if !timeRemaining.isEmpty {
            return "\(statusMessage) (\(progressPercent)% - \(timeRemaining) remaining)"
        } else {
            return "\(statusMessage) (\(progressPercent)%)"
        }
    }
} 