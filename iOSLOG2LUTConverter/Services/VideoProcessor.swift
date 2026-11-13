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
    private let sharedCIContext = CIContext(options: [.workingColorSpace: NSNull(), .cacheIntermediates: false])
    private var cancellables = Set<AnyCancellable>()
    private var startTime: Date?
    private var cancellationRequested = false
    private var completedVideos = 0
    private var activeProcessingTask: Task<Void, Error>?
    
    // MARK: - Processing Configuration
    struct ProcessingConfig {
        let videoURLs: [URL]
        let primaryLUTURL: URL?
        let secondaryLUTURL: URL?
        let primaryLUTOpacity: Float
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
            .sink { [weak self] progress in
                guard let self, self.isExporting else { return }
                self.updateOverallProgress(lutProgress: progress)
            }
            .store(in: &cancellables)
        
        lutProcessor.$processingStatus
            .sink { [weak self] status in
                guard let self, self.isExporting else { return }
                self.statusMessage = status
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Main Processing Method
    func processVideos(config: ProcessingConfig) async {
        guard !isExporting else { return }
        guard !config.videoURLs.isEmpty else {
            await handleError(.noVideosSelected)
            return
        }
        
        await startProcessing(config: config)
    }
    
    private func startProcessing(config: ProcessingConfig) async {
        isExporting = true
        cancellationRequested = false
        completedVideos = 0
        exportProgress = 0.0
        currentVideoIndex = 0
        totalVideos = config.videoURLs.count
        exportedVideoURLs = []
        lastError = nil
        startTime = Date()

        // Keep foreground exports awake and ask iOS for its finite grace period if
        // the user switches apps. Expiration cancels the writer and cleans partials.
        let application = UIApplication.shared
        let previousIdleTimerSetting = application.isIdleTimerDisabled
        application.isIdleTimerDisabled = true
        let backgroundTask = application.beginBackgroundTask(withName: "VideoLUTExport") { [weak self] in
            Task { @MainActor in self?.cancelProcessing() }
        }
        defer {
            application.isIdleTimerDisabled = previousIdleTimerSetting
            if backgroundTask != .invalid { application.endBackgroundTask(backgroundTask) }
        }

        do {
            try FileManager.default.createDirectory(at: config.outputDirectory, withIntermediateDirectories: true)
        } catch {
            await handleError(.exportFailed(error.localizedDescription))
            return
        }
        updateStatus("Starting video processing...")
        
        // Create LUT settings
        let lutSettings = LUTProcessor.LUTSettings(
            primaryLUTURL: config.primaryLUTURL,
            secondaryLUTURL: config.secondaryLUTURL,
            primaryLUTOpacity: config.primaryLUTOpacity,
            secondaryLUTOpacity: config.secondaryLUTOpacity,
            whiteBalanceAdjustment: config.whiteBalanceAdjustment,
            useGPUProcessing: config.useGPUProcessing,
            outputQuality: config.outputQuality
        )
        
        // Process each video
        for (index, videoURL) in config.videoURLs.enumerated() {
            guard !cancellationRequested, !Task.isCancelled else {
                await handleError(.cancelled)
                return
            }
            
            currentVideoIndex = index
            updateStatus("Processing video \(index + 1) of \(totalVideos)")
            
            do {
                let outputURL = generateOutputURL(for: videoURL, in: config.outputDirectory, settings: lutSettings)
                var registeredOutput = false
                defer { if !registeredOutput { try? FileManager.default.removeItem(at: outputURL) } }

                let task = Task { try await self.lutProcessor.processVideo(videoURL, settings: lutSettings, outputURL: outputURL) }
                activeProcessingTask = task
                defer { activeProcessingTask = nil }
                try await withTaskCancellationHandler {
                    try await task.value
                } onCancel: { task.cancel() }

                guard !cancellationRequested, !Task.isCancelled else { throw CancellationError() }
                // Verify a completed export exists before presenting it to the user.
                guard FileManager.default.fileExists(atPath: outputURL.path) else {
                    throw ProcessingError.exportFailed("Output file was not created")
                }
                
                let fileAttributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
                let fileSize = (fileAttributes[.size] as? NSNumber)?.int64Value ?? 0
                guard fileSize > 0 else { throw ProcessingError.exportFailed("The output file is empty") }
                let outputAsset = AVURLAsset(url: outputURL)
                let playable = try await outputAsset.load(.isPlayable)
                let videoTracks = try await outputAsset.loadTracks(withMediaType: .video)
                let duration = try await outputAsset.load(.duration).seconds
                guard playable, !videoTracks.isEmpty, duration.isFinite, duration > 0 else {
                    throw ProcessingError.exportFailed("The output file does not contain playable video")
                }
                guard !cancellationRequested, !Task.isCancelled else { throw CancellationError() }

                print("✅ Successfully processed video: \(outputURL.lastPathComponent) (Size: \(fileSize) bytes)")
                exportedVideoURLs.append(outputURL)
                registeredOutput = true
                completedVideos = index + 1
                updateOverallProgress(videoIndex: completedVideos)
                
            } catch {
                print("❌ VideoProcessor: Processing failed for video \(index + 1): \(error.localizedDescription)")
                if error is CancellationError || cancellationRequested || Task.isCancelled {
                    await handleError(.cancelled)
                } else {
                    await handleError(.processingFailed(error.localizedDescription))
                }
                return
            }
        }
        
        await finishProcessing()
    }
    
    // MARK: - Progress Management
    private func updateOverallProgress(videoIndex: Int? = nil, lutProgress: Double = 0.0) {
        guard totalVideos > 0 else { return }
        let finished = videoIndex ?? completedVideos
        let fraction = lutProgress.isFinite ? min(1, max(0, lutProgress)) : 0
        exportProgress = max(exportProgress, min(1, (Double(finished) + fraction) / Double(totalVideos)))
        
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
        // A unique destination protects earlier exports and duplicate source filenames.
        let filename = String(decoding: videoURL.deletingPathExtension().lastPathComponent.utf8.prefix(100), as: UTF8.self)
        return directory.appendingPathComponent("\(filename)_graded_\(UUID().uuidString).mp4")
    }

    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    // MARK: - Preview Generation
    func generatePreview(videoURL: URL, settings: ProcessingConfig) async throws -> UIImage {
        print("🎬 VideoProcessor: Generating preview with enhanced analysis...")
        
        // Analyze video characteristics before processing
        await analyzeVideoForProcessing(videoURL)
        
        let lutSettings = LUTProcessor.LUTSettings(
            primaryLUTURL: settings.primaryLUTURL,
            secondaryLUTURL: settings.secondaryLUTURL,
            primaryLUTOpacity: settings.primaryLUTOpacity,
            secondaryLUTOpacity: settings.secondaryLUTOpacity,
            whiteBalanceAdjustment: settings.whiteBalanceAdjustment,
            useGPUProcessing: settings.useGPUProcessing,
            outputQuality: settings.outputQuality
        )
        
        print("⚙️ Processing Configuration:")
        print("   - GPU Processing: \(settings.useGPUProcessing ? "✅ Enabled" : "❌ Disabled")")
        print("   - Primary LUT: \(settings.primaryLUTURL?.lastPathComponent ?? "None")")
        print("   - Secondary LUT: \(settings.secondaryLUTURL?.lastPathComponent ?? "None")")
        print("   - Secondary Opacity: \(Int(settings.secondaryLUTOpacity * 100))%")
        
        let ciImage = try await lutProcessor.generatePreview(from: videoURL, settings: lutSettings)
        
        guard let cgImage = sharedCIContext.createCGImage(ciImage, from: ciImage.extent) else {
            throw ProcessingError.processingFailed("Could not generate preview image")
        }
        
        print("✅ VideoProcessor: Preview generated successfully")
        return UIImage(cgImage: cgImage)
    }
    
    // MARK: - Time-Specific Preview Generation for Scrubbing
    func generatePreviewAtTime(videoURL: URL, timeSeconds: Double, settings: ProcessingConfig) async throws -> UIImage {
        print("🎬 VideoProcessor: Generating preview at \(timeSeconds)s...")
        
        let lutSettings = LUTProcessor.LUTSettings(
            primaryLUTURL: settings.primaryLUTURL,
            secondaryLUTURL: settings.secondaryLUTURL,
            primaryLUTOpacity: settings.primaryLUTOpacity,
            secondaryLUTOpacity: settings.secondaryLUTOpacity,
            whiteBalanceAdjustment: settings.whiteBalanceAdjustment,
            useGPUProcessing: settings.useGPUProcessing,
            outputQuality: settings.outputQuality
        )
        
        let ciImage = try await lutProcessor.generatePreviewAtTime(from: videoURL, timeSeconds: timeSeconds, settings: lutSettings)
        
        guard let cgImage = sharedCIContext.createCGImage(ciImage, from: ciImage.extent) else {
            throw ProcessingError.processingFailed("Could not generate preview image at \(timeSeconds)s")
        }
        
        print("✅ VideoProcessor: Preview generated at \(timeSeconds)s")
        return UIImage(cgImage: cgImage)
    }
    
    // MARK: - Cancellation
    func cancelProcessing() {
        guard isExporting else { return }
        
        cancellationRequested = true
        activeProcessingTask?.cancel()
        lutProcessor.cancelProcessing()
        updateStatus("Cancelling processing…")
        // Keep isExporting true until the active writer has stopped and removed its partial file.
    }
    
    // MARK: - Error Handling
    private func handleError(_ error: ProcessingError) async {
        lastError = error
        isExporting = false
        updateStatus(error.localizedDescription)
        
        // Reset progress
        exportProgress = 0.0
        currentVideoIndex = 0
        estimatedTimeRemaining = 0
    }
    
    // MARK: - Completion
    private func finishProcessing() async {
        isExporting = false
        estimatedTimeRemaining = 0
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
        if isExporting {
            cancelProcessing()
            return
        }
        completedVideos = 0
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
    
    // MARK: - Video Analysis for Processing
    private func analyzeVideoForProcessing(_ videoURL: URL) async {
        print("🔍 VideoProcessor: Analyzing video for optimal processing...")
        
        do {
            let asset = AVURLAsset(url: videoURL)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            
            guard let videoTrack = tracks.first else {
                print("❌ No video track found")
                return
            }
            
            // Load track properties
            let naturalSize = try await videoTrack.load(.naturalSize)
            let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
            let formatDescriptions = try await videoTrack.load(.formatDescriptions)
            
            print("📊 Video Processing Analysis:")
            print("   - Resolution: \(Int(naturalSize.width))x\(Int(naturalSize.height))")
            print("   - Frame Rate: \(nominalFrameRate) fps")
            
            // Analyze format for processing optimization
            if let formatDesc = formatDescriptions.first {
                let mediaSubType = CMFormatDescriptionGetMediaSubType(formatDesc)
                let fourCC = String(format: "%c%c%c%c", 
                                  (mediaSubType >> 24) & 0xFF,
                                  (mediaSubType >> 16) & 0xFF, 
                                  (mediaSubType >> 8) & 0xFF,
                                  mediaSubType & 0xFF)
                print("   - Codec: \(fourCC)")
                
            }
            
        } catch {
            print("❌ VideoProcessor: Analysis failed - \(error.localizedDescription)")
        }
    }
    
}
