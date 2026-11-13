import SwiftUI
import PhotosUI
import Photos
import CoreTransferable
import Combine
import AVFoundation

// MARK: - Movie Transferable Type for PhotosPicker
struct Movie: Transferable {
    let url: URL
    
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            // A unique directory preserves the filename without concurrent imports
            // racing to overwrite one another.
            let directory = URL.documentsDirectory.appendingPathComponent("ImportedVideos", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let finalURL = directory.appendingPathComponent(received.file.lastPathComponent)
            try FileManager.default.copyItem(at: received.file, to: finalURL)
            return Self.init(url: finalURL)
        }
    }
}

// MARK: - Main App Content View with Apple Design Language
struct ContentView: View {
    @StateObject private var fileImportManager = FileImportManager()
    @StateObject private var lutManager = LUTManager()
    @StateObject private var projectState = ProjectState()
    @StateObject private var exportProcessor = VideoProcessor()
    @State private var videoCount = 0
    @State private var videoURLs: [URL] = []
    @State private var selectedVideoItems: [PhotosPickerItem] = []
    @State private var isShowingVideoPicker = false
    @State private var isShowingVideoFileImporter = false
    @State private var isImportingVideo = false
    @State private var importTask: Task<Void, Never>?
    @State private var importError: String?
    @State private var showingDebugPanel = false
    @State private var showingProjectManagement = false
    @State private var previewDebounceTask: Task<Void, Never>?
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    // Background gradient with Apple-like aesthetics
                    backgroundGradient
                    
                    if horizontalSizeClass == .regular || geometry.size.width > geometry.size.height {
                        // iPad Interface - Side-by-side layout
                        iPadInterface(geometry: geometry)
                    } else {
                        // iPhone Interface - Vertical layout
                        iPhoneInterface(geometry: geometry)
                    }
                }
                
                // Debug Panel Overlay
                if showingDebugPanel {
                    DebugControlPanel(
                        projectState: projectState,
                        lutManager: lutManager,
                        fileImportManager: fileImportManager
                    )
                    .frame(width: min(400, geometry.size.width * 0.9))
                    .frame(height: min(600, geometry.size.height * 0.8))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(100)
                    .offset(x: horizontalSizeClass == .regular ? geometry.size.width * 0.3 : 0)
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showingProjectManagement) {
            ProjectManagementView(
                projectState: projectState,
                lutManager: lutManager
            )
        }
        .photosPicker(isPresented: $isShowingVideoPicker, selection: $selectedVideoItems,
                      maxSelectionCount: projectState.batchMode ? 10 : 1, matching: .videos,
                      preferredItemEncoding: .current)
        .fileImporter(isPresented: $isShowingVideoFileImporter,
                      allowedContentTypes: FileImportManager.SupportedVideoTypes.types,
                      allowsMultipleSelection: projectState.batchMode) { result in
            switch result {
            case .success(let urls): importVideoFiles(urls)
            case .failure(let error): reportImportError(error.localizedDescription)
            }
        }
        .alert("Unable to Import Video", isPresented: Binding(
            get: { importError != nil }, set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) { importError = nil }
        } message: { Text(importError ?? "") }
        .onChange(of: selectedVideoItems) { _, newItems in
            guard !newItems.isEmpty, !isExporting else { return }
            importTask?.cancel()
            isImportingVideo = true
            fileImportManager.lastImportStatus = .importing
            let importingBatch = projectState.batchMode
            importTask = Task {
                defer { isImportingVideo = false }
                var loadedVideos: [URL] = []
                var failures: [String] = []
                for item in newItems {
                    do {
                        guard let movie = try await item.loadTransferable(type: Movie.self) else {
                            failures.append("The selected item contains no readable video.")
                            continue
                        }
                        guard !Task.isCancelled else { return }
                        loadedVideos.append(movie.url)
                    } catch { failures.append(error.localizedDescription) }
                }
                guard !Task.isCancelled else { return }
                finishVideoImport(loadedVideos, batch: importingBatch)
                if !failures.isEmpty { reportImportError(failures.joined(separator: "\n")) }
                selectedVideoItems = []
            }
        }
        .onReceive(exportProcessor.$exportProgress) { progress in
            guard projectState.isExporting, !projectState.isBatchProcessing else { return }
            projectState.currentProgress = progress
            projectState.overallProgress = progress
        }
        // Update ProjectState when LUTs are selected
        .onChange(of: lutManager.selectedPrimaryLUT) { _, newLUT in
            projectState.setPrimaryLUT(newLUT?.url)
        }
        .onChange(of: lutManager.selectedSecondaryLUT) { _, newLUT in
            projectState.setSecondaryLUT(newLUT?.url)
        }
        .onChange(of: projectState.primaryLUTOpacity) { _, _ in
            previewDebounceTask?.cancel()
            previewDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled else { return }
                projectState.generatePreview()
            }
        }
        .onChange(of: projectState.secondLUTOpacity) { _, _ in
            previewDebounceTask?.cancel()
            previewDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled else { return }
                projectState.generatePreview()
            }
        }
        .onChange(of: projectState.whiteBalanceValue) { _, _ in
            previewDebounceTask?.cancel()
            previewDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled else { return }
                projectState.generatePreview()
            }
        }
        // Update video URLs when test video is loaded
        .onChange(of: projectState.videoURLs) { oldURLs, newURLs in
            if oldURLs != newURLs && !projectState.batchMode && !isExporting {
                clearExportResult()
            }
            self.videoURLs = newURLs
            self.videoCount = projectState.batchMode ? projectState.batchQueue.count : newURLs.count
        }
        .onChange(of: projectState.exportConfigurationVersion) { _, _ in
            // The model has invalidated any batch results; clear only this view's
            // single-export and Photos-save state, without mutating the model.
            clearExportResult()
        }
        // Listen for debug export notification
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("DebugTestExport"))) { _ in
            exportVideo()
        }
        // LUT selector sheets are now handled in the fileImportSection
    }
    
    // MARK: - Background Gradient
    private var backgroundGradient: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color.primary.opacity(0.05),
                Color.secondary.opacity(0.1)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
    
    // MARK: - iPad Interface (Horizontal Split)
    private func iPadInterface(geometry: GeometryProxy) -> some View {
        HStack(spacing: 0) {
            // Left Panel - Controls with ultrathin material
            ScrollView {
                controlsPanelContent
            }
            .accessibilityIdentifier("controlsScrollView")
            .frame(width: min(400, geometry.size.width * 0.35))
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 0)
            )
            
            // Right Panel - Prominent Preview
            VStack(spacing: 0) {
                prominentVideoPreview
            }
            .frame(maxWidth: .infinity)
            .background(Color.black.opacity(0.05))
        }
    }
    
    // MARK: - iPhone Interface (Vertical Stack)
    private func iPhoneInterface(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // Top - Prominent Preview (takes most space)
            prominentVideoPreview
                .frame(height: geometry.size.height * 0.5)
            
            // Bottom - Scrollable Controls
            ScrollView {
                controlsPanelContent
                    .padding(.top)
            }
            .accessibilityIdentifier("controlsScrollView")
            .frame(maxHeight: .infinity)
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .mask(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
        }
    }
    
    // MARK: - Controls Panel Content
    private var controlsPanelContent: some View {
        VStack(spacing: 24) {
            // App Title with Apple Typography
            appTitle
            
            // Processing Mode Toggle - Moved to top for better UX
            processingModeSection
            
            // File Import Section with Real Import Functionality
            fileImportSection
            
            // LUT Controls Section - Now integrated into import buttons above
            
            // Export Controls Section
            exportControlsSection
            
            // Status Section
            statusSection
            
            // Verbose Log Section
            verboseLogSection
            
            // Reset Button - Always available at bottom
            resetSection
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
    
    // MARK: - App Title
    private var appTitle: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "video.badge.waveform")
                    .font(.title2)
                    .foregroundStyle(.blue.gradient)
                
                Text("VideoLUT")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                
                Text("Converter")
                    .font(.title2)
                    .fontWeight(.light)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                // Project Management Button
                Button {
                    showingProjectManagement = true
                } label: {
                    Image(systemName: "folder.badge.gearshape")
                }
                .disabled(controlsLocked)
                .accessibilityLabel("Project Management")
                .accessibilityIdentifier("projectManagement")
                .font(.title2)
                .foregroundStyle(.blue.gradient)
                .symbolEffect(.bounce, value: showingProjectManagement)
                
                // Debug Button
                if projectState.isDebugMode {
                    Button {
                        withAnimation(.spring()) {
                            showingDebugPanel.toggle()
                        }
                    } label: {
                        Image(systemName: showingDebugPanel ? "ant.circle.fill" : "ant.circle")
                    }
                    .accessibilityLabel("Debug Panel")
                    .font(.title2)
                    .foregroundStyle(.yellow.gradient)
                    .symbolEffect(.bounce, value: showingDebugPanel)
                }
            }
            
            Text("Professional Video LUT Processing")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 8)
    }
    
    // MARK: - Processing Mode Section
    private var processingModeSection: some View {
        VStack(spacing: 16) {
            Text("Processing Mode")
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(alignment: .leading) {
                Picker("Processing Mode", selection: Binding(
                    get: { projectState.batchMode }, set: { newValue in
                        guard !controlsLocked, newValue != projectState.batchMode else { return }
                        projectState.clearBatchQueue()
                        projectState.clearVideoURLs()
                        projectState.batchMode = newValue
                        videoURLs = []
                        videoCount = 0
                        selectedVideoItems = []
                        clearExportResult()
                    })) {
                    Text("Single Video").tag(false)
                    Text("Batch Processing").tag(true)
                }
                .pickerStyle(SegmentedPickerStyle())
                .disabled(controlsLocked)

            }
            .padding(16)
            .background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
    }
    
    // MARK: - File Import Section
    private var fileImportSection: some View {
        VStack(spacing: 16) {
            Text("Media & LUTs")
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(spacing: 12) {
                // Video Import Button - Single video only using PhotosPicker
                Button(action: triggerVideoImport) {
                    HStack {
                        VStack(spacing: 8) {
                            Image(systemName: projectState.batchMode ? "square.stack.3d.up.fill" : "video.fill")
                                .font(.title2)
                                .foregroundStyle((projectState.batchMode ? !projectState.batchQueue.isEmpty : videoCount > 0) ? .white : .blue)
                            
                            VStack(spacing: 4) {
                                Text(projectState.batchMode ? "Import Videos" : "Import Video")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle((projectState.batchMode ? !projectState.batchQueue.isEmpty : videoCount > 0) ? .white : .primary)
                                
                                Text((projectState.batchMode ? projectState.batchQueue.isEmpty : videoCount == 0) ? 
                                     (projectState.batchMode ? "No videos selected" : "No video selected") : 
                                     (projectState.batchMode ? 
                                      "Videos selected: \(projectState.batchQueue.count)" : 
                                      "Video selected: \(videoURLs.first?.lastPathComponent ?? "")"))
                                    .font(.caption)
                                    .foregroundStyle((projectState.batchMode ? !projectState.batchQueue.isEmpty : videoCount > 0) ? .white.opacity(0.8) : .secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill((projectState.batchMode ? !projectState.batchQueue.isEmpty : videoCount > 0) ? AnyShapeStyle(Color.blue.gradient) : AnyShapeStyle(Color.gray.opacity(0.2)))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke((projectState.batchMode ? !projectState.batchQueue.isEmpty : videoCount > 0) ? .clear : .blue.opacity(0.3), lineWidth: 1)
                                )
                        )
                    }
                }
                .accessibilityIdentifier("importPhotos")

                Button("Import from Files", systemImage: "folder") {
                    isShowingVideoFileImporter = true
                }
                .disabled(controlsLocked)
                .accessibilityIdentifier("importFiles")

                if isImportingVideo { ProgressView("Importing video…") }

                // Primary LUT Selection - Now Optional
                VStack(spacing: 8) {
                    Button {
                        print("🔥 ContentView: PRIMARY LUT BUTTON TAPPED")
                        print("🔥 ContentView: Setting isShowingLUTPicker = true")
                        fileImportManager.isShowingLUTPicker = true
                    } label: {
                        HStack {
                            VStack(spacing: 8) {
                                Image(systemName: "camera.filters")
                                    .font(.title2)
                                    .foregroundStyle(lutManager.hasSelectedPrimaryLUT ? .white : .green)
                                
                                VStack(spacing: 4) {
                                    Text("Select Primary LUT")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundStyle(lutManager.hasSelectedPrimaryLUT ? .white : .primary)
                                    
                                    Text(lutManager.selectedPrimaryLUT?.displayName ?? "Optional - for Log footage")
                                        .font(.caption)
                                        .foregroundStyle(lutManager.hasSelectedPrimaryLUT ? .white.opacity(0.8) : .secondary)
                                        .multilineTextAlignment(.center)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(lutManager.hasSelectedPrimaryLUT ? AnyShapeStyle(Color.green.gradient) : AnyShapeStyle(Color.gray.opacity(0.2)))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(lutManager.hasSelectedPrimaryLUT ? .clear : .green.opacity(0.3), lineWidth: 1)
                                    )
                            )
                        }
                    }
                    .accessibilityIdentifier("selectPrimaryLUT")

                    // Primary LUT Opacity Slider
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Primary LUT Opacity")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(projectState.primaryLUTOpacity * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Slider(value: $projectState.primaryLUTOpacity, in: 0...1)
                            .tint(.green)
                            .accessibilityLabel("Primary LUT opacity")
                            .accessibilityIdentifier("primaryOpacity")
                            .disabled(!lutManager.hasSelectedPrimaryLUT)
                    }
                    .padding(.horizontal, 4)
                    .opacity(lutManager.hasSelectedPrimaryLUT ? 1.0 : 0.5)
                }
                
                // White Balance Slider
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("White Balance")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(projectState.formattedWhiteBalance)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Slider(value: $projectState.whiteBalanceValue, in: -10...10)
                        .tint(.orange)
                        .accessibilityLabel("White balance")
                        .accessibilityIdentifier("whiteBalance")
                }
                .padding(.horizontal, 4)
                
                // Secondary LUT Selection - Now Optional
                VStack(spacing: 8) {
                    Button {
                        print("🔥 ContentView: SECONDARY LUT BUTTON TAPPED")
                        print("🔥 ContentView: Setting isShowingSecondaryLUTPicker = true")
                        fileImportManager.isShowingSecondaryLUTPicker = true
                    } label: {
                        HStack {
                            VStack(spacing: 8) {
                                Image(systemName: "paintbrush.fill")
                                    .font(.title2)
                                    .foregroundStyle(lutManager.hasSelectedSecondaryLUT ? .white : .pink)
                                
                                VStack(spacing: 4) {
                                    Text("Select Secondary LUT")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundStyle(lutManager.hasSelectedSecondaryLUT ? .white : .primary)
                                    
                                    Text(lutManager.selectedSecondaryLUT?.displayName ?? "Optional - for creative effects")
                                        .font(.caption)
                                        .foregroundStyle(lutManager.hasSelectedSecondaryLUT ? .white.opacity(0.8) : .secondary)
                                        .multilineTextAlignment(.center)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(lutManager.hasSelectedSecondaryLUT ? AnyShapeStyle(Color.pink.gradient) : AnyShapeStyle(Color.gray.opacity(0.2)))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(lutManager.hasSelectedSecondaryLUT ? .clear : .pink.opacity(0.3), lineWidth: 1)
                                    )
                            )
                        }
                    }
                    .accessibilityIdentifier("selectSecondaryLUT")

                    // Secondary LUT Opacity Slider
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Secondary LUT Opacity")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(projectState.secondLUTOpacity * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Slider(value: $projectState.secondLUTOpacity, in: 0...1)
                            .tint(.pink)
                            .accessibilityLabel("Secondary LUT opacity")
                            .accessibilityIdentifier("secondaryOpacity")
                            .disabled(!lutManager.hasSelectedSecondaryLUT)
                    }
                    .padding(.horizontal, 4)
                    .opacity(lutManager.hasSelectedSecondaryLUT ? 1.0 : 0.5)
                }
            }
        }
        .disabled(controlsLocked)
        .padding(.horizontal)
        .sheet(isPresented: $fileImportManager.isShowingLUTPicker) {
            LUTSelectorView(
                lutManager: lutManager,
                fileImportManager: fileImportManager,
                isSecondary: false
            )
        }
        .sheet(isPresented: $fileImportManager.isShowingSecondaryLUTPicker) {
            LUTSelectorView(
                lutManager: lutManager,
                fileImportManager: fileImportManager,
                isSecondary: true
            )
        }
    }
    
    // MARK: - LUT Controls Section
    private var lutControlsSection: some View {
        VStack(spacing: 16) {
            Text("LUT Controls")
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(spacing: 12) {
                // Primary LUT Opacity Slider (visible when primary LUT is selected)
                if lutManager.selectedPrimaryLUT != nil {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Primary LUT Opacity")
                                .font(.subheadline)
                            Spacer()
                            Text("\(Int(projectState.primaryLUTOpacity * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Slider(value: $projectState.primaryLUTOpacity, in: 0...1)
                            .tint(.green)
                    }
                    .padding(16)
                    .background(
                        .regularMaterial,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                
                // Secondary LUT Opacity Slider (visible when secondary LUT is selected)
                if lutManager.selectedSecondaryLUT != nil {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Secondary LUT Opacity")
                                .font(.subheadline)
                            Spacer()
                            Text("\(Int(projectState.secondLUTOpacity * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Slider(value: $projectState.secondLUTOpacity, in: 0...1)
                            .tint(.pink)
                    }
                    .padding(16)
                    .background(
                        .regularMaterial,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                
                // White Balance Slider  
                VStack(alignment: .leading) {
                    HStack {
                        Text("White Balance")
                            .font(.subheadline)
                        Spacer()
                        Text(projectState.formattedWhiteBalance)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Slider(value: $projectState.whiteBalanceValue, in: -10...10)
                        .tint(.orange)
                }
                .padding(16)
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }
        }
    }
    
    // MARK: - Export Controls Section
    private var exportControlsSection: some View {
        VStack(spacing: 16) {
            Text("Export Settings")
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Batch Queue Section (shown when batch mode is enabled)
            if projectState.batchMode {
                batchQueueSection
            }
            
            // Export Quality Selector
            VStack(alignment: .leading) {
                Text("Export Quality")
                    .font(.subheadline)
                
                Picker("Export Quality", selection: $projectState.exportQuality) {
                    ForEach(ExportQuality.allCases, id: \.self) { quality in
                        Text(quality.description)
                            .tag(quality)
                    }
                }
                .pickerStyle(.menu)
                .disabled(controlsLocked)
                .accentColor(.purple)
                .accessibilityIdentifier("exportQuality")
            }
            .padding(16)
            .background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            
            // Convert Video Button
            Button(action: exportVideo) {
                HStack {
                    if isExporting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else if isConversionComplete {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                    } else {
                        Image(systemName: "wand.and.rays")
                            .font(.title3)
                    }
                    
                    Text(isExporting ? 
                         (projectState.batchMode ? "Processing Batch..." : "Converting...") : 
                         (isConversionComplete ? "Converted!" : 
                          (projectState.batchMode ? "Process Batch" : "Convert Video")))
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(
                    isConversionComplete ? Color.green.gradient : 
                    ((projectState.batchMode ? !projectState.batchQueue.isEmpty : videoCount > 0) && !isExporting) ? Color.blue.gradient : Color.gray.gradient,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled((projectState.batchMode ? projectState.batchQueue.isEmpty : videoCount == 0) || controlsLocked)
            .accessibilityIdentifier("convertVideo")
            
            // Save to Photos Button (shown after export)
            if showingShareSheet && !projectState.batchMode {
                Button(action: saveToPhotos) {
                    HStack {
                        Image(systemName: isSavedToPhotos ? "checkmark.circle.fill" : "photo.badge.plus")
                            .font(.title3)
                        
                        Text(isSavedToPhotos ? "Saved to Photos!" : "Save to Photos")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(
                        isSavedToPhotos ? Color.blue.gradient : Color.green.gradient,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isSavedToPhotos || isSavingToPhotos || isExporting)
                .accessibilityIdentifier("saveVideoToPhotos")
                .transition(.scale.combined(with: .opacity))
            }
            
            if let exportedVideoURL, !projectState.batchMode {
                ShareLink("Share Exported Video", item: exportedVideoURL)
                    .disabled(isExporting)
                    .accessibilityIdentifier("shareVideo")
            }
            if projectState.batchMode && !projectState.batchExportedVideoURLs.isEmpty && !isExporting {
                ShareLink("Share Exported Batch", items: projectState.batchExportedVideoURLs)
                    .accessibilityIdentifier("shareBatch")
            }
            if isExporting {
                Button("Cancel Processing", role: .destructive) {
                    if projectState.isBatchProcessing { projectState.cancelBatchProcessing() }
                    else { exportProcessor.cancelProcessing() }
                }
                .accessibilityIdentifier("cancelProcessing")
            }

            // Save to Photos Button for Batch Processing (shown after batch processing is complete)
            if projectState.batchMode && !projectState.isBatchProcessing && !projectState.batchExportedVideoURLs.isEmpty {
                Button(action: saveBatchToPhotos) {
                    HStack {
                        Image(systemName: isSavedToPhotos ? "checkmark.circle.fill" : "photo.badge.plus")
                            .font(.title3)
                        
                        Text(isSavedToPhotos ? "Batch Saved to Photos!" : "Save Batch to Photos")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(
                        isSavedToPhotos ? Color.blue.gradient : Color.green.gradient,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isSavedToPhotos || isSavingToPhotos || isExporting)
                .accessibilityIdentifier("saveBatchToPhotos")
                .transition(.scale.combined(with: .opacity))
            }
            
            // Reset Button (shown after conversion)
            if isConversionComplete {
                Button(action: resetConversion) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                            .font(.title3)
                        
                        Text("Start New Conversion")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(
                        Color.orange.gradient,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
    }
    
    // MARK: - Batch Queue Section
    private var batchQueueSection: some View {
        VStack(spacing: 12) {
            batchQueueHeader
            
            if projectState.batchQueue.isEmpty {
                batchQueueEmptyState
            } else {
                batchQueueContent
            }
            batchQueueControls
        }
        .padding(16)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .transition(.scale.combined(with: .opacity))
    }
    
    private var batchQueueHeader: some View {
        HStack {
            Image(systemName: "square.stack.3d.up")
                .font(.title3)
                .foregroundStyle(.purple)
            
            Text("Batch Queue")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            Spacer()
            
            Text("\(projectState.batchQueue.count) videos")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private var batchQueueEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.title2)
                .foregroundStyle(.secondary)
            
            Text("No videos in batch queue")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text("Add videos to start batch processing")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }
    
    private var batchQueueContent: some View {
        VStack(spacing: 6) {
            batchQueueList
        }
    }
    
    private var batchQueueList: some View {
        VStack(spacing: 6) {
            ForEach(Array(projectState.batchQueue.enumerated()), id: \.element.id) { index, item in
                batchQueueItem(index: index, item: item)
            }
        }
        .frame(maxHeight: 200)
    }
    
    private func batchQueueItem(index: Int, item: ProjectState.BatchVideoItem) -> some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(batchItemStatusColor(for: item.status))
                .frame(width: 8, height: 8)
            
            // Video info - Make it tappable for preview selection
            Button(action: {
                projectState.selectBatchVideoForPreview(index: index)
            }) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.caption)
                        .fontWeight(index == projectState.selectedBatchVideoIndex ? .bold : .medium)
                        .lineLimit(1)
                        .foregroundStyle(index == projectState.selectedBatchVideoIndex ? .blue : .primary)
                    
                    Text(batchItemStatusText(for: item.status))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // Preview indicator for selected video
            if index == projectState.selectedBatchVideoIndex {
                Image(systemName: "eye.fill")
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }
            
            // Progress indicator
            batchItemProgressIndicator(item: item)
            
            // Remove button (only for pending items)
            if item.status == .pending && !controlsLocked {
                Button(action: {
                    projectState.removeVideoFromBatch(at: index)
                }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            index == projectState.selectedBatchVideoIndex ? 
                Color.blue.opacity(0.1) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(
                    index == projectState.selectedBatchVideoIndex ? 
                        Color.blue.opacity(0.3) : Color.clear,
                    lineWidth: 1
                )
        )
    }
    
    @ViewBuilder
    private func batchItemProgressIndicator(item: ProjectState.BatchVideoItem) -> some View {
        if item.status == .processing {
            ProgressView(value: item.progress)
                .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                .scaleEffect(0.7)
                .frame(width: 20, height: 20)
        } else if item.status == .completed {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else if item.status == .failed {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
    
    private var batchQueueControls: some View {
        HStack(spacing: 8) {
            Button(action: {
                triggerVideoImport()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                        .font(.caption)
                    Text(projectState.batchQueue.isEmpty ? "Add Videos" : "Add More")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundStyle(.blue)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(controlsLocked)
            .accessibilityIdentifier("batchAddVideos")

            Spacer()

            Button(action: {
                projectState.clearBatchQueue()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "trash.circle.fill")
                        .font(.caption)
                    Text("Clear All")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundStyle(.red)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(controlsLocked || projectState.batchQueue.isEmpty)
        }
    }
    
    // MARK: - Status Section
    private var statusSection: some View {
        VStack(spacing: 8) {
            Text("Status")
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Export Progress Bar (shown during export)
            if isExporting {
                VStack(spacing: 8) {
                    ProgressView(value: exportProgress)
                        .progressViewStyle(LinearProgressViewStyle())
                        .scaleEffect(y: 2.0)
                        .animation(.easeInOut(duration: 0.3), value: exportProgress)
                    
                    Text(exportStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .animation(.easeInOut(duration: 0.3), value: exportStatusMessage)
                }
                .padding(12)
                .background(
                    .thinMaterial,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .transition(.opacity.combined(with: .scale))
            } else {
                // Regular Status Display
                HStack {
                    // Status indicator icon - Fixed to use proper enum cases
                    Image(systemName: getStatusIcon())
                        .font(.caption)
                        .foregroundStyle(getStatusColor())
                    
                    Text(projectState.batchMode && !projectState.batchProcessingStatus.isEmpty ? projectState.batchProcessingStatus : projectState.statusMessage)
                        .accessibilityIdentifier("operationStatus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                }
                .padding(12)
                .background(
                    .thinMaterial,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
            }
            
            // Save to Photos confirmation message
            if !saveToPhotosMessage.isEmpty {
                HStack {
                    Image(systemName: isSavedToPhotos ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(isSavedToPhotos ? .green : .red)
                    
                    Text(saveToPhotosMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                }
                .padding(12)
                .background(
                    .thinMaterial,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .transition(.opacity.combined(with: .scale))
            }
        }
    }
    
    // MARK: - Verbose Log Section
    private var verboseLogSection: some View {
        VStack(spacing: 12) {
            // Log Header with Toggle
            HStack {
                Text("System Log")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Button(action: {
                    projectState.showVerboseLog.toggle()
                }) {
                    Image(systemName: projectState.showVerboseLog ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Button(action: {
                    projectState.clearLog()
                }) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            
            // Log Content
            if projectState.showVerboseLog {
                ScrollView {
                    ScrollViewReader { proxy in
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(projectState.verboseLog) { entry in
                                HStack(alignment: .top, spacing: 8) {
                                    // Icon
                                    Image(systemName: entry.level.icon)
                                        .font(.caption2)
                                        .foregroundStyle(entry.level.color)
                                        .frame(width: 12)
                                    
                                    // Timestamp
                                    Text(entry.formattedTimestamp)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 60, alignment: .leading)
                                    
                                    // Category
                                    Text(entry.category.rawValue)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 60, alignment: .leading)
                                    
                                    // Message
                                    Text(entry.message)
                                        .font(.caption2)
                                        .foregroundStyle(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(
                                    entry.level == .error ? Color.red.opacity(0.1) :
                                    entry.level == .warning ? Color.orange.opacity(0.1) :
                                    entry.level == .success ? Color.green.opacity(0.1) :
                                    Color.clear
                                )
                                .cornerRadius(4)
                                .id(entry.id)
                            }
                        }
                        .padding(8)
                        .onChange(of: projectState.verboseLog.count) { _, _ in
                            // Auto-scroll to bottom when new log entries are added
                            if let lastEntry = projectState.verboseLog.last {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    proxy.scrollTo(lastEntry.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 200)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
        }
        .padding(16)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }
    
    // MARK: - Reset Section
    private var resetSection: some View {
        Button(action: resetConversion) {
            HStack {
                Image(systemName: "arrow.clockwise")
                    .font(.title3)
                
                Text("Reset All")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(
                Color.red.gradient,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(controlsLocked)
        .accessibilityIdentifier("resetAll")
        .transition(.scale.combined(with: .opacity))
    }
    
    // MARK: - Helper Methods for Status
    private func getStatusIcon() -> String {
        switch fileImportManager.lastImportStatus {
        case .error(_):
            return "exclamationmark.triangle"
        case .success(_):
            return "checkmark.circle"
        case .importing:
            return "arrow.clockwise"
        case .idle:
            return "info.circle"
        }
    }
    
    private func getStatusColor() -> Color {
        switch fileImportManager.lastImportStatus {
        case .error(_):
            return .red
        case .success(_):
            return .green
        case .importing:
            return .blue
        case .idle:
            return .blue
        }
    }
    
    // MARK: - Prominent Video Preview
    private var prominentVideoPreview: some View {
        VideoPreviewView(projectState: projectState)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Helper Methods
    private func triggerVideoImport() {
        guard !controlsLocked else { return }
        selectedVideoItems = []
        isShowingVideoPicker = true
    }
    
    private func reportImportError(_ message: String) {
        importError = message
        fileImportManager.lastImportStatus = .error(message)
        projectState.logVideoOperation(message, level: .error)
    }

    private func finishVideoImport(_ urls: [URL], batch: Bool) {
        guard !urls.isEmpty else { return }
        clearExportResult()
        if batch {
            projectState.addVideosToBatch(urls)
        } else if let url = urls.first {
            projectState.clearVideoURLs()
            projectState.addVideoURL(url)
        }
        videoURLs = projectState.videoURLs
        videoCount = batch ? projectState.batchQueue.count : videoURLs.count
        fileImportManager.lastImportStatus = .success("Imported \(urls.count) video(s)")
        projectState.logVideoOperation("Imported \(urls.count) video(s)", level: .success)
    }

    private func importVideoFiles(_ urls: [URL]) {
        guard !controlsLocked else { return }
        isImportingVideo = true
        fileImportManager.lastImportStatus = .importing
        let importingBatch = projectState.batchMode
        importTask = Task {
            defer { isImportingVideo = false }
            var imported: [URL] = []
            var failures: [String] = []
            for url in urls {
                do {
                    let destination = try await Task.detached(priority: .userInitiated) {
                        let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let directory = URL.documentsDirectory.appendingPathComponent("ImportedVideos", isDirectory: true)
                            .appendingPathComponent(UUID().uuidString, isDirectory: true)
                        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                        let destination = directory.appendingPathComponent(url.lastPathComponent)
                        do {
                            try FileManager.default.copyItem(at: url, to: destination)
                            return destination
                        } catch {
                            try? FileManager.default.removeItem(at: directory)
                            throw error
                        }
                    }.value
                    do {
                        let tracks = try await AVURLAsset(url: destination).loadTracks(withMediaType: .video)
                        guard !tracks.isEmpty else {
                            throw NSError(domain: "VideoImport", code: 1, userInfo: [NSLocalizedDescriptionKey: "The file contains no supported video track."])
                        }
                        imported.append(destination)
                    } catch {
                        try? FileManager.default.removeItem(at: destination.deletingLastPathComponent())
                        throw error
                    }
                } catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            }
            finishVideoImport(imported, batch: importingBatch)
            if !failures.isEmpty { reportImportError(failures.joined(separator: "\n")) }
        }
    }

    private func clearExportResult() {
        isConversionComplete = false
        showingShareSheet = false
        exportedVideoURL = nil
        isSavedToPhotos = false
        savedBatchURLs = []
        saveToPhotosMessage = ""
    }

    // MARK: - Debug Mode Methods
    private func autoSelectDebugLUTs() {
        print("🧪 ContentView: Auto-selecting test LUTs...")
        
        // Auto-select first primary LUT
        if let firstPrimaryLUT = lutManager.primaryLUTs.first {
            print("✅ Debug: Auto-selecting primary LUT: \(firstPrimaryLUT.displayName)")
            lutManager.selectedPrimaryLUT = firstPrimaryLUT
        }
        
        // Auto-select first secondary LUT
        if let firstSecondaryLUT = lutManager.secondaryLUTs.first {
            print("✅ Debug: Auto-selecting secondary LUT: \(firstSecondaryLUT.displayName)")
            lutManager.selectedSecondaryLUT = firstSecondaryLUT
        }
        
        print("🧪 Debug: LUT auto-selection complete")
    }
    
    // MARK: - Export Functionality
    @State private var exportedVideoURL: URL?
    @State private var showingShareSheet = false
    private var isExporting: Bool { projectState.isExporting || projectState.isBatchProcessing || exportProcessor.isExporting }
    private var controlsLocked: Bool { isExporting || isImportingVideo || isSavingToPhotos }
    private var exportProgress: Double { projectState.isBatchProcessing ? projectState.batchProgress : exportProcessor.exportProgress }
    private var exportStatusMessage: String { projectState.isBatchProcessing ? projectState.batchProcessingStatus : exportProcessor.statusMessage }
    @State private var isConversionComplete = false
    @State private var isSavedToPhotos = false
    @State private var isSavingToPhotos = false
    @State private var savedBatchURLs: Set<URL> = []
    @State private var saveToPhotosMessage = ""
    
    private func exportVideo() {
        guard !controlsLocked else { return }
        clearExportResult()
        // Check if batch mode is enabled
        if projectState.batchMode {
            // Handle batch processing
            guard !projectState.batchQueue.isEmpty else {
                projectState.logBatchOperation("No videos in batch queue", level: .error)
                return
            }
            
            projectState.logBatchOperation("Starting batch processing for \(projectState.batchQueue.count) videos", level: .info)
            
            Task {
                await projectState.startBatchProcessing()
            }
            return
        }
        
        // Handle single video processing
        guard videoCount > 0, let firstVideo = projectState.videoURLs.first else {
            projectState.logExportOperation("No video selected for export", level: .error)
            return
        }
        
        projectState.logExportOperation("Starting video export process", level: .info)
        projectState.logExportOperation("Input video: \(firstVideo.lastPathComponent)", level: .info)
        projectState.logExportOperation("Export quality: \(projectState.exportQuality.rawValue)", level: .info)
        
        // Log LUT configuration
        if let primaryLUT = projectState.primaryLUTURL {
            projectState.logLUTOperation("Primary LUT: \(primaryLUT.lastPathComponent)", level: .info)
            projectState.logLUTOperation("Primary LUT opacity: \(Int(projectState.primaryLUTOpacity * 100))%", level: .info)
        }
        
        if let secondaryLUT = projectState.secondaryLUTURL {
            projectState.logLUTOperation("Secondary LUT: \(secondaryLUT.lastPathComponent)", level: .info)
            projectState.logLUTOperation("Secondary LUT opacity: \(Int(projectState.secondLUTOpacity * 100))%", level: .info)
        }
        
        if projectState.whiteBalanceValue != 0 {
            projectState.logExportOperation("White balance adjustment: \(projectState.formattedWhiteBalance)", level: .info)
        }
        
        projectState.logGPUOperation("Using GPU acceleration for processing", level: .info)
        
        projectState.isExporting = true
        projectState.currentProgress = 0
        projectState.overallProgress = 0
        Task {
            defer { projectState.isExporting = false }
            projectState.logExportOperation("Initializing video processor...", level: .info)
            
            // Create output directory
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let outputDirectory = documentsPath.appendingPathComponent("LUTexport")
            
            let config = VideoProcessor.ProcessingConfig(
                videoURLs: [firstVideo],
                primaryLUTURL: projectState.primaryLUTURL,
                secondaryLUTURL: projectState.secondaryLUTURL,
                primaryLUTOpacity: projectState.primaryLUTOpacity,
                secondaryLUTOpacity: projectState.secondLUTOpacity,
                whiteBalanceAdjustment: projectState.whiteBalanceValue,
                useGPUProcessing: projectState.useGPU,
                outputQuality: projectState.exportQuality.toLUTProcessorQuality(),
                outputDirectory: outputDirectory
            )
            
            projectState.logExportOperation("Configuration created successfully", level: .success)
            
            await exportProcessor.processVideos(config: config)

            if exportProcessor.lastError == nil, let result = exportProcessor.exportedVideoURLs.first {
                projectState.logExportOperation("Video export completed successfully", level: .success)
                projectState.logExportOperation("Output file: \(result.lastPathComponent)", level: .success)
                
                // Store the result for sharing
                exportedVideoURL = result
                showingShareSheet = true
                isConversionComplete = true
            } else {
                projectState.logExportOperation(exportProcessor.lastError?.localizedDescription ?? "Export failed: No output file generated", level: .error)
            }
        }
    }
    
    private func saveToPhotos() {
        guard !controlsLocked, !isSavedToPhotos, let videoURL = exportedVideoURL else { return }
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            saveToPhotosMessage = "The exported video is no longer available. Convert it again before saving."
            return
        }
        isSavingToPhotos = true
        Task {
            defer { isSavingToPhotos = false }
            let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard authorization == .authorized || authorization == .limited else {
                saveToPhotosMessage = "Photos access denied. Enable access in Settings to save this video."
                return
            }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
                }
                isSavedToPhotos = true
                saveToPhotosMessage = "Video saved to Photos."
                projectState.updateStatus(saveToPhotosMessage)
            } catch {
                saveToPhotosMessage = "Failed to save to Photos: \(error.localizedDescription)"
                projectState.updateStatus(saveToPhotosMessage)
            }
        }
    }

    private func saveBatchToPhotos() {
        guard !controlsLocked, !projectState.batchExportedVideoURLs.isEmpty else { return }
        let allURLs = Set(projectState.batchExportedVideoURLs)
        let remainingURLs = allURLs.subtracting(savedBatchURLs)
        guard !remainingURLs.isEmpty else { return }
        isSavingToPhotos = true
        Task {
            defer { isSavingToPhotos = false }
            let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard authorization == .authorized || authorization == .limited else {
                saveToPhotosMessage = "Photos access denied. Enable access in Settings to save these videos."
                return
            }
            for videoURL in remainingURLs {
                guard FileManager.default.fileExists(atPath: videoURL.path) else { continue }
                do {
                    try await PHPhotoLibrary.shared().performChanges {
                        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
                    }
                    savedBatchURLs.insert(videoURL)
                } catch {
                    projectState.logExportOperation("Unable to save \(videoURL.lastPathComponent): \(error.localizedDescription)", level: .error)
                }
            }
            isSavedToPhotos = allURLs.isSubset(of: savedBatchURLs)
            saveToPhotosMessage = isSavedToPhotos
                ? "All \(allURLs.count) videos saved to Photos."
                : "Saved \(savedBatchURLs.intersection(allURLs).count) of \(allURLs.count) videos. Tap Save Batch to retry the remaining videos."
            projectState.updateStatus(saveToPhotosMessage)
        }
    }

    private func resetConversion() {
        guard !controlsLocked else { return }
        projectState.logVideoOperation("Resetting all app data and selections", level: .info)
        
        // Reset all conversion states
        exportProcessor.resetProcessor()
        isConversionComplete = false
        showingShareSheet = false
        exportedVideoURL = nil
        isSavedToPhotos = false
        saveToPhotosMessage = ""
        savedBatchURLs = []

        // Clear video and LUT selections
        videoURLs = []
        videoCount = 0
        selectedVideoItems = []
        lutManager.selectedPrimaryLUT = nil
        lutManager.selectedSecondaryLUT = nil
        projectState.clearVideoURLs()
        projectState.setPrimaryLUT(nil)
        projectState.setSecondaryLUT(nil)
        projectState.previewImage = nil
        
        // Clear batch queue and exported URLs
        projectState.clearBatchQueue()
        
        // Reset opacity sliders
        projectState.primaryLUTOpacity = 1.0
        projectState.secondLUTOpacity = 1.0
        projectState.whiteBalanceValue = 0.0
        
        // Reset processing mode to single video
        projectState.batchMode = false
        
        projectState.logVideoOperation("All data cleared - ready for new conversion", level: .success)
        print("🔄 Complete app reset - ready for new conversion")
    }
    
    // MARK: - Helper Methods
    private func convertToLUTProcessorQuality(_ quality: ExportQuality) -> LUTProcessor.OutputQuality {
        switch quality {
        case .low: return .low
        case .medium: return .medium
        case .high: return .high
        case .maximum: return .maximum
        }
    }

    // MARK: - Helper Methods for Batch Queue
    private func batchItemStatusColor(for status: ProjectState.BatchVideoItem.BatchVideoStatus) -> Color {
        switch status {
        case .pending: return .blue
        case .processing: return .orange
        case .completed: return .green
        case .failed: return .red
        }
    }
    
    private func batchItemStatusText(for status: ProjectState.BatchVideoItem.BatchVideoStatus) -> String {
        switch status {
        case .pending: return "Pending"
        case .processing: return "Processing"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }
}

// MARK: - Content View Preview
#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}

#Preview("Light Mode") {
    ContentView()
        .preferredColorScheme(.light)
} 