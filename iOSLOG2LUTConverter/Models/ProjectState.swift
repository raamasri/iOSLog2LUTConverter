import Foundation
import SwiftUI
import Combine
import AVFoundation
import UIKit

// MARK: - Enhanced ProjectState for iOS Migration
@MainActor
class ProjectState: ObservableObject {
    
    // MARK: - Core Properties (Migrated from macOS)
    @Published var videoURLs: [URL] = [] {
        didSet { if !batchMode, videoURLs != oldValue { invalidateCompletedExports() } }
    }
    @Published var primaryLUTURL: URL? {
        didSet { if primaryLUTURL != oldValue { invalidateCompletedExports() } }
    }
    @Published var secondaryLUTURL: URL? {
        didSet { if secondaryLUTURL != oldValue { invalidateCompletedExports() } }
    }
    @Published var primaryLUTOpacity: Float = 1.0 {
        didSet { if primaryLUTOpacity != oldValue { invalidateCompletedExports() } }
    }
    @Published var secondLUTOpacity: Float = 1.0 {
        didSet { if secondLUTOpacity != oldValue { invalidateCompletedExports() } }
    }
    @Published var whiteBalanceValue: Float = 0.0 {
        didSet { if whiteBalanceValue != oldValue { invalidateCompletedExports() } }
    }
    
    // GPU processing is always enabled (no user toggle)
    var useGPU: Bool { return true }
    
    /// A completed export describes one exact media/grade configuration.
    @Published private(set) var exportConfigurationVersion: Int = 0

    // MARK: - iOS-Specific Properties
    @Published var isExporting: Bool = false
    @Published var currentProgress: Double = 0.0
    @Published var overallProgress: Double = 0.0
    @Published var exportQuality: ExportQuality = .high {
        didSet { if exportQuality != oldValue { invalidateCompletedExports() } }
    }
    @Published var shouldOptimizeForBattery: Bool = true
    @Published var isPreviewLoading: Bool = false
    @Published var previewImage: UIImage?
    @Published var rawPreviewImage: UIImage? // Raw preview without LUTs
    @Published var previewError: String?
    @Published var statusMessage: String = "Ready to import videos"
    
    // MARK: - Verbose Logging Properties
    @Published var verboseLog: [LogEntry] = []
    @Published var showVerboseLog: Bool = true // Toggle for showing/hiding verbose log
    private let maxLogEntries: Int = 100 // Maximum number of log entries to keep
    
    // Log Entry Structure
    struct LogEntry: Identifiable, Equatable {
        let id = UUID()
        let timestamp: Date
        let level: LogLevel
        let category: LogCategory
        let message: String
        
        enum LogLevel: String, CaseIterable {
            case info = "INFO"
            case success = "SUCCESS"
            case warning = "WARNING"
            case error = "ERROR"
            case debug = "DEBUG"
            
            var icon: String {
                switch self {
                case .info: return "info.circle"
                case .success: return "checkmark.circle"
                case .warning: return "exclamationmark.triangle"
                case .error: return "xmark.circle"
                case .debug: return "ladybug"
                }
            }
            
            var color: Color {
                switch self {
                case .info: return .blue
                case .success: return .green
                case .warning: return .orange
                case .error: return .red
                case .debug: return .purple
                }
            }
        }
        
        enum LogCategory: String, CaseIterable {
            case system = "SYSTEM"
            case video = "VIDEO"
            case lut = "LUT"
            case export = "EXPORT"
            case preview = "PREVIEW"
            case batch = "BATCH"
            case gpu = "GPU"
            case debug = "DEBUG"
        }
        
        private static let timestampFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.timeStyle = .medium
            formatter.dateStyle = .none
            return formatter
        }()
        
        var formattedTimestamp: String {
            Self.timestampFormatter.string(from: timestamp)
        }
    }
    
    // MARK: - Video Scrubbing Properties
    @Published var currentTime: Double = 0.0 // Current scrub position in seconds
    @Published var videoDuration: Double = 0.0 // Total video duration in seconds
    @Published var isScrubbing: Bool = false // True when actively scrubbing timeline
    
    // MARK: - Before/After Comparison Properties
    @Published var showBeforeAfter: Bool = false // Toggle for before/after view
    @Published var beforeAfterMode: BeforeAfterMode = .sideBySide // Comparison display mode
    @Published var beforeAfterSplit: Double = 0.5 // Split position for overlay mode (0.0 to 1.0)
    
    // MARK: - Batch Processing Properties
    @Published var batchMode: Bool = false // Toggle for batch processing mode
    @Published var batchQueue: [BatchVideoItem] = [] // Queue of videos to process
    @Published var currentBatchIndex: Int = 0 // Currently processing video index
    @Published var batchProgress: Double = 0.0 // Overall batch progress (0.0 to 1.0)
    @Published var isBatchProcessing: Bool = false // True when batch processing is active
    @Published var batchProcessingStatus: String = "" // Status message for batch processing
    @Published var selectedBatchVideoIndex: Int = 0 // Currently selected video for preview in batch mode
    @Published var batchExportedVideoURLs: [URL] = [] // URLs of exported videos from batch processing
    
    // MARK: - Batch Processing Data Models
    struct BatchVideoItem: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        let name: String
        var status: BatchVideoStatus = .pending
        var progress: Double = 0.0
        var outputURL: URL?
        var errorMessage: String?
        
        enum BatchVideoStatus {
            case pending
            case processing
            case completed
            case failed
        }
    }
    
    enum BeforeAfterMode: String, CaseIterable {
        case sideBySide = "side_by_side"
        case verticalSplit = "vertical_split"
        case toggle = "toggle"
        
        var displayName: String {
            switch self {
            case .sideBySide: return "Side by Side"
            case .verticalSplit: return "Top/Bottom Split"
            case .toggle: return "A/B Toggle"
            }
        }
        
        var icon: String {
            switch self {
            case .sideBySide: return "rectangle.split.2x1"
            case .verticalSplit: return "rectangle.split.1x2"
            case .toggle: return "arrow.left.arrow.right"
            }
        }
    }
    
    // MARK: - Background Processing
    @Published var backgroundExportProgress: [String: Double] = [:]
    @Published var canExportInBackground: Bool = false
    
    // MARK: - Recent Projects (iOS Enhancement)
    @Published var recentProjects: [RecentProject] = []
    
    // MARK: - Debug/Test Mode
    @Published var isDebugMode = false
    
    // MARK: - Service Dependencies
    private let videoProcessor = VideoProcessor()
    private let previewProcessor = VideoProcessor()
    private var previewTask: Task<Void, Never>?
    private var durationTask: Task<Void, Never>?
    private var previewGeneration = UUID()
    private var batchCancellationRequested = false
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Verbose Logging Methods
    func log(_ message: String, level: LogEntry.LogLevel = .info, category: LogEntry.LogCategory = .system) {
        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            category: category,
            message: message
        )
        
        // Add to verbose log
        verboseLog.append(entry)
        
        // Keep only the last maxLogEntries
        if verboseLog.count > maxLogEntries {
            verboseLog.removeFirst()
        }
        
        // Also print to console for debugging
        let timestamp = entry.formattedTimestamp
        print("[\(timestamp)] [\(level.rawValue)] [\(category.rawValue)] \(message)")
        
        // Update status message with the latest log entry
        statusMessage = message
    }
    
    func clearLog() {
        verboseLog.removeAll()
        log("Log cleared", level: .info, category: .system)
    }
    
    func logVideoOperation(_ message: String, level: LogEntry.LogLevel = .info) {
        log(message, level: level, category: .video)
    }
    
    func logLUTOperation(_ message: String, level: LogEntry.LogLevel = .info) {
        log(message, level: level, category: .lut)
    }
    
    func logExportOperation(_ message: String, level: LogEntry.LogLevel = .info) {
        log(message, level: level, category: .export)
    }
    
    func logPreviewOperation(_ message: String, level: LogEntry.LogLevel = .info) {
        log(message, level: level, category: .preview)
    }
    
    func logBatchOperation(_ message: String, level: LogEntry.LogLevel = .info) {
        log(message, level: level, category: .batch)
    }
    
    func logGPUOperation(_ message: String, level: LogEntry.LogLevel = .info) {
        log(message, level: level, category: .gpu)
    }
    
    func enableDebugMode() {
        guard !isExporting, !isBatchProcessing else { return }
        isDebugMode = true
        let candidates = [("applelogtest", "mov"), ("test_compatible", "mp4"), ("test", "MP4"), ("test", "mp4")]
        for (name, ext) in candidates {
            let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources/testfootage")
                ?? Bundle.main.url(forResource: name, withExtension: ext)
            if let url {
                addVideoURL(url)
                updateStatus("Debug mode: loaded \(url.lastPathComponent)")
                return
            }
        }
        if videoURLs.isEmpty {
            log("Debug mode enabled. No test footage is bundled; import a video to continue.", level: .warning, category: .debug)
        } else {
            log("Debug mode enabled using the current video.", category: .debug)
        }
    }

    // MARK: - Project Management Support Methods
    // Note: setPrimaryLUT and setSecondaryLUT methods are defined later in the file with enhanced logging
    
    func resetToDefaults() {
        guard !isExporting, !isBatchProcessing else { return }
        primaryLUTOpacity = 1.0
        secondLUTOpacity = 1.0
        whiteBalanceValue = 0.0
        exportQuality = .high
        shouldOptimizeForBattery = true
        log("Project settings reset to defaults", level: .info, category: .system)
    }
    
    // MARK: - Computed Properties
    var isReadyForPreview: Bool {
        return !videoURLs.isEmpty  // Only need video for preview, LUTs are optional
    }
    
    var isReadyForExport: Bool {
        return isReadyForPreview && !isExporting && !isBatchProcessing
    }
    
    var hasSecondaryLUT: Bool {
        return secondaryLUTURL != nil
    }
    
    var opacityPercentage: Int {
        return Int(secondLUTOpacity * 100)
    }
    
    var formattedWhiteBalance: String {
        let baseTemp = 6500
        let tempChange = Int(whiteBalanceValue * 100)
        let finalTemp = baseTemp + tempChange
        return "\(finalTemp)K"
    }
    
    var estimatedExportTime: TimeInterval {
        guard !videoURLs.isEmpty else { return 0.0 }
        
        // Use async duration loading, but for estimates we'll use a default
        // This is just an estimate, so we can use a reasonable default
        let estimatedDuration: Double = 30.0 // Default estimate
        
        // Estimate based on duration and device performance
        // iOS devices typically process 1 second of video in 0.5-2 seconds
        let processingMultiplier: Double = useGPU ? 0.5 : 1.5
        return estimatedDuration * processingMultiplier * Double(videoURLs.count)
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
        guard !isExporting, !isBatchProcessing else { return }
        videoURLs = [url]
        resetPreviewState()
        logVideoOperation("Added video: \(url.lastPathComponent)", level: .success)
        loadSelectedVideoDuration(url)
        generatePreview()
    }

    /// Restore project media through the same path as a fresh import.
    func replaceProjectVideos(_ urls: [URL]) {
        guard !isExporting, !isBatchProcessing else { return }
        clearBatchQueue()
        batchMode = urls.count > 1
        if batchMode {
            addVideosToBatch(urls)
        } else if let url = urls.first {
            addVideoURL(url)
        }
    }

    private func loadSelectedVideoDuration(_ url: URL) {
        durationTask?.cancel()
        durationTask = Task { [weak self] in
            do {
                let asset = AVURLAsset(url: url)
                let duration = try await asset.load(.duration).seconds
                guard !Task.isCancelled, let self, self.videoURLs.first == url else { return }
                guard duration.isFinite, duration > 0 else {
                    self.logVideoOperation("The video has no playable duration", level: .error)
                    return
                }
                self.videoDuration = duration
            } catch {
                guard !Task.isCancelled, let self, self.videoURLs.first == url else { return }
                self.logVideoOperation("Could not read video duration: \(error.localizedDescription)", level: .error)
            }
        }
    }

    private func resetPreviewState() {
        scrubTask?.cancel()
        previewTask?.cancel()
        durationTask?.cancel()
        previewGeneration = UUID()
        previewImage = nil
        rawPreviewImage = nil
        previewError = nil
        videoDuration = 0
        currentTime = 0
        isPreviewLoading = false
        isScrubbing = false
    }

    // MARK: - Video Scrubbing Methods
    private var scrubTask: Task<Void, Never>?
    
    func scrubToTime(_ time: Double) {
        guard videoDuration > 0, time.isFinite else { return }
        // The exact duration is past the last sample in many video containers.
        let clampedTime = max(0, min(time, max(0, videoDuration - 1.0 / 600)))
        currentTime = clampedTime
        previewTask?.cancel()
        previewGeneration = UUID()
        isScrubbing = true
        scrubTask?.cancel()
        scrubTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            self?.generatePreviewAtTime(clampedTime)
        }
    }

    func generatePreviewAtTime(_ timeSeconds: Double) {
        guard let videoURL = videoURLs.first, timeSeconds.isFinite else { return }
        scrubTask?.cancel()
        previewTask?.cancel()
        let generation = UUID()
        previewGeneration = generation
        let time = max(0, videoDuration > 0
            ? min(timeSeconds, max(0, videoDuration - 1.0 / 600)) : timeSeconds)
        currentTime = time
        isPreviewLoading = true
        previewError = nil

        // Snapshot settings before awaiting. A superseded render must never replace
        // the image for a newer video, timeline position, or grade.
        let rawConfig = VideoProcessor.ProcessingConfig(
            videoURLs: [videoURL], primaryLUTURL: nil, secondaryLUTURL: nil,
            primaryLUTOpacity: 1, secondaryLUTOpacity: 1, whiteBalanceAdjustment: 0,
            useGPUProcessing: useGPU, outputQuality: .medium,
            outputDirectory: FileManager.default.temporaryDirectory)
        let gradedConfig = VideoProcessor.ProcessingConfig(
            videoURLs: [videoURL], primaryLUTURL: primaryLUTURL, secondaryLUTURL: secondaryLUTURL,
            primaryLUTOpacity: primaryLUTOpacity, secondaryLUTOpacity: secondLUTOpacity,
            whiteBalanceAdjustment: whiteBalanceValue, useGPUProcessing: useGPU,
            outputQuality: .medium, outputDirectory: FileManager.default.temporaryDirectory)
        let needsGrade = primaryLUTURL != nil || secondaryLUTURL != nil || whiteBalanceValue != 0

        previewTask = Task { [weak self] in
            guard let self else { return }
            do {
                let raw = try await self.previewProcessor.generatePreviewAtTime(
                    videoURL: videoURL, timeSeconds: time, settings: rawConfig)
                try Task.checkCancellation()
                let graded: UIImage
                if needsGrade {
                    graded = try await self.previewProcessor.generatePreviewAtTime(
                        videoURL: videoURL, timeSeconds: time, settings: gradedConfig)
                } else {
                    graded = raw
                }
                guard !Task.isCancelled, self.previewGeneration == generation else { return }
                self.rawPreviewImage = raw
                self.previewImage = graded
                self.isPreviewLoading = false
                self.isScrubbing = false
            } catch {
                guard !Task.isCancelled, self.previewGeneration == generation else { return }
                self.previewImage = nil
                self.rawPreviewImage = nil
                self.previewError = error.localizedDescription
                self.isPreviewLoading = false
                self.isScrubbing = false
                self.logPreviewOperation("Preview failed: \(error.localizedDescription)", level: .error)
            }
        }
    }

    // MARK: - Debug Methods
    func forcePreviewGeneration() {
        print("🔄 ProjectState: Force preview generation requested")
        print("   - Current state: videoURLs=\(videoURLs.count), primaryLUT=\(primaryLUTURL != nil), secondaryLUT=\(secondaryLUTURL != nil)")
        generatePreview()
    }
    
    func addVideoURLs(_ urls: [URL]) {
        guard !isExporting, !isBatchProcessing else { return }
        if batchMode {
            addVideosToBatch(urls)
        } else if let url = urls.first {
            addVideoURL(url)
        }
    }

    func removeVideoURL(_ url: URL) {
        guard !isExporting, !isBatchProcessing else { return }
        let wasSelected = videoURLs.first == url
        videoURLs.removeAll { $0 == url }
        if wasSelected {
            resetPreviewState()
            if let next = videoURLs.first {
                loadSelectedVideoDuration(next)
                generatePreview()
            }
        }
        updateStatus("Removed video: \(url.lastPathComponent)")
    }

    func clearVideoURLs() {
        guard !isExporting, !isBatchProcessing else { return }
        videoURLs.removeAll()
        resetPreviewState()
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
        
        return .success
    }
    
    // MARK: - Status Management
    func updateStatus(_ message: String) {
        log(message, level: .info, category: .system)
    }
    
    // MARK: - Initialization
    init() {
        log("iOS LUT Converter initialized", level: .success, category: .system)
        log("Ready to import videos", level: .info, category: .system)
        
        // Initialize with GPU processing enabled
        logGPUOperation("GPU processing enabled by default", level: .info)
        videoProcessor.$exportProgress
            .sink { [weak self] progress in
                guard let self, self.isBatchProcessing,
                      self.batchQueue.indices.contains(self.currentBatchIndex) else { return }
                let clamped = progress.isFinite ? max(0, min(1, progress)) : 0
                self.batchQueue[self.currentBatchIndex].progress = clamped
                self.batchProgress = (Double(self.currentBatchIndex) + clamped) / Double(self.batchQueue.count)
            }
            .store(in: &cancellables)
    }
    
    func generatePreview() {
        guard isReadyForPreview else {
            resetPreviewState()
            return
        }
        // Changing a grade preserves the frame the user is inspecting.
        generatePreviewAtTime(currentTime)
    }

    func optimizeForBattery() {
        if shouldOptimizeForBattery {
            exportQuality = .medium
            updateStatus("Optimized for battery life")
        }
    }

    private func invalidateCompletedExports() {
        guard !isExporting, !isBatchProcessing else { return }
        exportConfigurationVersion += 1
        batchExportedVideoURLs.removeAll()
        batchProgress = 0
        batchProcessingStatus = ""
        for index in batchQueue.indices where batchQueue[index].status != .pending || batchQueue[index].outputURL != nil {
            batchQueue[index].status = .pending
            batchQueue[index].progress = 0
            batchQueue[index].outputURL = nil
            batchQueue[index].errorMessage = nil
        }
        // Keep completed files on disk. Editing the current project only removes
        // stale Save/Share state; earlier exports remain available through Files.
    }

    // MARK: - Batch Processing Methods
    
    func addVideoToBatch(_ url: URL) {
        addVideosToBatch([url])
    }

    func addVideosToBatch(_ urls: [URL]) {
        guard !isExporting, !isBatchProcessing else { return }
        let wasEmpty = batchQueue.isEmpty
        let oldCount = batchQueue.count
        for url in urls where !batchQueue.contains(where: { $0.url == url }) {
            batchQueue.append(BatchVideoItem(url: url, name: url.lastPathComponent))
        }
        if batchQueue.count != oldCount { invalidateCompletedExports() }
        if wasEmpty, !batchQueue.isEmpty {
            selectBatchVideoForPreview(index: 0)
        }
    }

    func selectBatchVideoForPreview(index: Int) {
        guard batchQueue.indices.contains(index) else { return }
        selectedBatchVideoIndex = index
        let url = batchQueue[index].url
        videoURLs = [url]
        resetPreviewState()
        loadSelectedVideoDuration(url)
        generatePreview()
    }

    func removeVideoFromBatch(at index: Int) {
        guard !isExporting, !isBatchProcessing, batchQueue.indices.contains(index) else { return }
        let selectedID = batchQueue.indices.contains(selectedBatchVideoIndex)
            ? batchQueue[selectedBatchVideoIndex].id : nil
        invalidateCompletedExports()
        batchQueue.remove(at: index)
        if batchQueue.isEmpty {
            selectedBatchVideoIndex = 0
            clearVideoURLs()
        } else if let selectedID,
                  let retainedIndex = batchQueue.firstIndex(where: { $0.id == selectedID }) {
            // Removing an earlier row shifts the index but preserves selection.
            selectedBatchVideoIndex = retainedIndex
        } else {
            selectBatchVideoForPreview(index: min(index, batchQueue.count - 1))
        }
    }

    func removeVideoFromBatch(id: UUID) {
        if let index = batchQueue.firstIndex(where: { $0.id == id }) {
            removeVideoFromBatch(at: index)
        }
    }

    func clearBatchQueue() {
        guard !isExporting, !isBatchProcessing else { return }
        invalidateCompletedExports()
        batchQueue.removeAll()
        currentBatchIndex = 0
        batchProgress = 0
        batchProcessingStatus = ""
        selectedBatchVideoIndex = 0
        batchExportedVideoURLs.removeAll()
        clearVideoURLs()
    }

    func reorderBatchQueue(from source: IndexSet, to destination: Int) {
        guard !isExporting, !isBatchProcessing,
              source.allSatisfy({ batchQueue.indices.contains($0) }),
              (0...batchQueue.count).contains(destination) else { return }
        let selectedID = batchQueue.indices.contains(selectedBatchVideoIndex)
            ? batchQueue[selectedBatchVideoIndex].id : nil
        let oldOrder = batchQueue.map(\.id)
        batchQueue.move(fromOffsets: source, toOffset: destination)
        if batchQueue.map(\.id) != oldOrder { invalidateCompletedExports() }
        if let index = batchQueue.firstIndex(where: { $0.id == selectedID }) {
            selectedBatchVideoIndex = index
        }
    }

    func cancelBatchProcessing() {
        guard isBatchProcessing else { return }
        batchCancellationRequested = true
        videoProcessor.cancelProcessing()
        batchProcessingStatus = "Cancelling batch..."
    }

    func startBatchProcessing() async {
        guard !isExporting, !isBatchProcessing, !batchQueue.isEmpty else { return }
        isBatchProcessing = true
        batchCancellationRequested = false
        currentBatchIndex = 0
        batchProgress = 0
        batchExportedVideoURLs.removeAll()
        for index in batchQueue.indices {
            batchQueue[index].status = .pending
            batchQueue[index].progress = 0
            batchQueue[index].outputURL = nil
            batchQueue[index].errorMessage = nil
        }
        defer { isBatchProcessing = false }

        // Every item in a run uses the settings present when Export was pressed.
        let outputDirectory = URL.documentsDirectory.appendingPathComponent("BatchOutput", isDirectory: true)
        let config = VideoProcessor.ProcessingConfig(
            videoURLs: [], primaryLUTURL: primaryLUTURL, secondaryLUTURL: secondaryLUTURL,
            primaryLUTOpacity: primaryLUTOpacity, secondaryLUTOpacity: secondLUTOpacity,
            whiteBalanceAdjustment: whiteBalanceValue, useGPUProcessing: useGPU,
            outputQuality: exportQuality.toLUTProcessorQuality(), outputDirectory: outputDirectory)
        let items = batchQueue
        for (index, item) in items.enumerated() {
            guard !batchCancellationRequested, !Task.isCancelled else { break }
            currentBatchIndex = index
            batchQueue[index].status = .processing
            batchProcessingStatus = "Processing \(item.name) (\(index + 1)/\(items.count))"
            do {
                let outputURL = try await processBatchVideo(item, config: config)
                // A completed file remains available even if cancellation arrived
                // at the boundary between this item and the next.
                batchQueue[index].status = .completed
                batchQueue[index].progress = 1
                batchQueue[index].outputURL = outputURL
                batchExportedVideoURLs.append(outputURL)
            } catch {
                if let processingError = error as? VideoProcessor.ProcessingError,
                   case .cancelled = processingError {
                    batchCancellationRequested = true
                }
                batchQueue[index].status = .failed
                batchQueue[index].errorMessage = batchCancellationRequested || Task.isCancelled
                    ? "Cancelled" : error.localizedDescription
            }
            batchProgress = Double(index + 1) / Double(items.count)
        }
        if batchCancellationRequested || Task.isCancelled {
            batchProcessingStatus = "Batch cancelled: \(batchExportedVideoURLs.count) completed"
        } else {
            let failed = batchQueue.filter { $0.status == .failed }.count
            batchProcessingStatus = "Batch finished: \(batchExportedVideoURLs.count) completed, \(failed) failed"
        }
    }

    private func processBatchVideo(_ item: BatchVideoItem, config: VideoProcessor.ProcessingConfig) async throws -> URL {
        let itemConfig = VideoProcessor.ProcessingConfig(
            videoURLs: [item.url], primaryLUTURL: config.primaryLUTURL, secondaryLUTURL: config.secondaryLUTURL,
            primaryLUTOpacity: config.primaryLUTOpacity, secondaryLUTOpacity: config.secondaryLUTOpacity,
            whiteBalanceAdjustment: config.whiteBalanceAdjustment, useGPUProcessing: config.useGPUProcessing,
            outputQuality: config.outputQuality, outputDirectory: config.outputDirectory)
        await videoProcessor.processVideos(config: itemConfig)
        if let error = videoProcessor.lastError { throw error }
        guard let outputURL = videoProcessor.exportedVideoURLs.first else {
            throw NSError(domain: "BatchProcessing", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No output was created for \(item.name)"])
        }
        return outputURL
    }

    var batchProcessingProgress: Double {
        return batchProgress
    }
    
    var batchProcessingStatusMessage: String {
        if isBatchProcessing {
            let completedCount = batchQueue.filter { $0.status == .completed }.count
            let failedCount = batchQueue.filter { $0.status == .failed }.count
            return "Processing: \(completedCount) completed, \(failedCount) failed, \(batchQueue.count - completedCount - failedCount) remaining"
        } else if !batchQueue.isEmpty {
            let completedCount = batchQueue.filter { $0.status == .completed }.count
            let failedCount = batchQueue.filter { $0.status == .failed }.count
            return "Ready: \(batchQueue.count) videos in queue (\(completedCount) completed, \(failedCount) failed)"
        } else {
            return "No videos in batch queue"
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
        case .maximum: return "Maximum (Original resolution, 10-bit HEVC)"
        }
    }
    
    func toLUTProcessorQuality() -> LUTProcessor.OutputQuality {
        switch self {
        case .low: return .low
        case .medium: return .medium
        case .high: return .high
        case .maximum: return .maximum
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
    let id: UUID
    let name: String
    let videoCount: Int
    let lutName: String
    let createdAt: Date
    let thumbnailData: Data?
    
    init(name: String, videoCount: Int, lutName: String, createdAt: Date, thumbnailData: Data? = nil) {
        self.id = UUID()
        self.name = name
        self.videoCount = videoCount
        self.lutName = lutName
        self.createdAt = createdAt
        self.thumbnailData = thumbnailData
    }
}

// FavoriteProject is now defined in ProjectManager.swift to avoid duplication

// ProjectSettings is now defined in ProjectManager.swift to avoid duplication
