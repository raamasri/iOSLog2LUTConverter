import SwiftUI
import PhotosUI
import Photos
import CoreTransferable
import Combine

// MARK: - Movie Transferable Type for PhotosPicker
struct Movie: Transferable {
    let url: URL
    
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = URL.documentsDirectory.appending(path: "movie.mov")
            if FileManager.default.fileExists(atPath: copy.path()) {
                try FileManager.default.removeItem(at: copy)
            }
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self.init(url: copy)
        }
    }
}

// MARK: - Main App Content View with Apple Design Language
struct ContentView: View {
    @StateObject private var fileImportManager = FileImportManager()
    @StateObject private var lutManager = LUTManager()
    @StateObject private var projectState = ProjectState()
    @State private var videoCount = 0
    @State private var videoURLs: [URL] = []
    @State private var selectedVideoItems: [PhotosPickerItem] = []
    @State private var showingDebugPanel = false
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ZStack {
                    // Background gradient with Apple-like aesthetics
                    backgroundGradient
                    
                    if horizontalSizeClass == .regular {
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
        .navigationViewStyle(StackNavigationViewStyle())
        // Handle photo picker selection
        .onChange(of: selectedVideoItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            
            if projectState.batchMode {
                // Handle multiple video selection for batch processing
                var loadedVideos: [URL] = []
                let group = DispatchGroup()
                
                for item in newItems {
                    group.enter()
                    item.loadTransferable(type: Movie.self) { result in
                        defer { group.leave() }
                        
                        switch result {
                        case .success(let movie?):
                            loadedVideos.append(movie.url)
                            print("✅ Video imported for batch: \(movie.url.lastPathComponent)")
                        case .failure(let error):
                            print("❌ Failed to import video for batch: \(error)")
                        case .success(.none):
                            print("❌ No video data found")
                        }
                    }
                }
                
                group.notify(queue: .main) {
                    // Add all videos to batch queue
                    self.projectState.addVideosToBatch(loadedVideos)
                    self.videoURLs = loadedVideos
                    self.videoCount = loadedVideos.count
                    print("📦 Added \(loadedVideos.count) videos to batch queue")
                }
            } else {
                // Handle single video selection
                guard let item = newItems.first else { return }
                
                item.loadTransferable(type: Movie.self) { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success(let movie?):
                            let url = movie.url
                            self.videoURLs = [url]
                            self.videoCount = 1
                            // CRITICAL: Update ProjectState with the imported video
                            self.projectState.addVideoURL(url)
                            print("✅ Video imported successfully: \(url.lastPathComponent)")
                        case .failure(let error):
                            print("❌ Failed to import video: \(error)")
                        case .success(.none):
                            print("❌ No video data found")
                        }
                    }
                }
            }
        }
        // Update ProjectState when LUTs are selected
        .onChange(of: lutManager.selectedPrimaryLUT) { _, newLUT in
            projectState.setPrimaryLUT(newLUT?.url)
        }
        .onChange(of: lutManager.selectedSecondaryLUT) { _, newLUT in
            projectState.setSecondaryLUT(newLUT?.url)
        }
        // Update preview when opacity changes
        .onChange(of: projectState.primaryLUTOpacity) { _, newOpacity in
            print("🎨 Primary LUT opacity changed to \(Int(newOpacity * 100))% - Regenerating preview...")
            projectState.generatePreview()
        }
        .onChange(of: projectState.secondLUTOpacity) { _, newOpacity in
            print("🎭 Secondary LUT opacity changed to \(Int(newOpacity * 100))% - Regenerating preview...")
            projectState.generatePreview()
        }
        .onChange(of: projectState.whiteBalanceValue) { _, newValue in
            print("🌡️ White balance changed to \(projectState.formattedWhiteBalance) - Regenerating preview...")
            projectState.generatePreview()
        }
        // Update video URLs when test video is loaded
        .onChange(of: projectState.videoURLs) { _, newURLs in
            self.videoURLs = newURLs
            self.videoCount = newURLs.count
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
            VStack(spacing: 0) {
                controlsPanelContent
            }
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
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
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
                
                // Debug Button
                if projectState.isDebugMode {
                    Button {
                        withAnimation(.spring()) {
                            showingDebugPanel.toggle()
                        }
                    } label: {
                        Image(systemName: showingDebugPanel ? "ant.circle.fill" : "ant.circle")
                            .font(.title2)
                            .foregroundStyle(.yellow.gradient)
                            .symbolEffect(.bounce, value: showingDebugPanel)
                    }
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
                Picker("Processing Mode", selection: $projectState.batchMode) {
                    Text("Single Video").tag(false)
                    Text("Batch Processing").tag(true)
                }
                .pickerStyle(SegmentedPickerStyle())
                .onChange(of: projectState.batchMode) { _, newValue in
                    print("📦 Processing Mode Changed: \(newValue ? "Batch" : "Single") Processing")
                    // Clear videos when switching modes to avoid confusion
                    if newValue {
                        // Switching to batch mode - clear single video selection
                        videoURLs = []
                        videoCount = 0
                        selectedVideoItems = []
                    } else {
                        // Switching to single mode - clear batch queue
                        projectState.clearBatchQueue()
                        videoURLs = []
                        videoCount = 0
                        selectedVideoItems = []
                    }
                }
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
                PhotosPicker(
                    selection: $selectedVideoItems,
                    maxSelectionCount: projectState.batchMode ? 10 : 1,
                    matching: .videos
                ) {
                    HStack {
                        VStack(spacing: 8) {
                            Image(systemName: projectState.batchMode ? "square.stack.3d.up.fill" : "video.fill")
                                .font(.title2)
                                .foregroundStyle(videoCount > 0 ? .white : .blue)
                            
                            VStack(spacing: 4) {
                                Text(projectState.batchMode ? "Import Videos" : "Import Video")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(videoCount > 0 ? .white : .primary)
                                
                                Text(videoCount == 0 ? 
                                     (projectState.batchMode ? "No videos selected" : "No video selected") : 
                                     (projectState.batchMode ? 
                                      "Videos selected: \(videoCount)" : 
                                      "Video selected: \(videoURLs.first?.lastPathComponent ?? "")"))
                                    .font(.caption)
                                    .foregroundStyle(videoCount > 0 ? .white.opacity(0.8) : .secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(videoCount > 0 ? AnyShapeStyle(Color.blue.gradient) : AnyShapeStyle(Color.gray.opacity(0.2)))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(videoCount > 0 ? .clear : .blue.opacity(0.3), lineWidth: 1)
                                )
                        )
                    }
                }
                
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
                            .disabled(!lutManager.hasSelectedSecondaryLUT)
                    }
                    .padding(.horizontal, 4)
                    .opacity(lutManager.hasSelectedSecondaryLUT ? 1.0 : 0.5)
                }
            }
        }
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
            
            // Batch Processing Button (shown when batch mode is enabled)
            if projectState.batchMode {
                NavigationLink(destination: BatchProcessingView(projectState: projectState)) {
                    HStack {
                        Image(systemName: "square.stack.3d.up")
                            .font(.title3)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Batch Processing")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            Text("\(projectState.batchQueue.count) videos in queue")
                                .font(.caption)
                                .opacity(0.8)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .opacity(0.6)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(
                        Color.purple.gradient,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
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
                .accentColor(.purple)
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
            .disabled((projectState.batchMode ? projectState.batchQueue.isEmpty : videoCount == 0) || isExporting)
            
            // Save to Photos Button (shown after export)
            if showingSaveToPhotos {
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
                .disabled(isSavedToPhotos)
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
                    
                    Text(fileImportManager.lastImportStatus.message)
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
        // This will trigger the PhotosPicker by clearing and setting the selection
        selectedVideoItems = []
        // The PhotosPicker will be triggered by the PhotosPicker in the file import section
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
    @State private var showingSaveToPhotos = false
    @State private var isExporting = false
    @State private var exportProgress: Double = 0.0
    @State private var exportStatusMessage = ""
    @State private var isConversionComplete = false
    @State private var isSavedToPhotos = false
    @State private var saveToPhotosMessage = ""
    
    private func exportVideo() {
        // Check if batch mode is enabled
        if projectState.batchMode {
            // Handle batch processing
            guard !projectState.batchQueue.isEmpty else {
                print("❌ Batch Export: No videos in batch queue")
                projectState.updateStatus("No videos in batch queue")
                return
            }
            
            print("📦 Starting batch processing...")
            print("📹 Videos in queue: \(projectState.batchQueue.count)")
            
            Task {
                await projectState.startBatchProcessing()
            }
            return
        }
        
        // Handle single video processing
        guard videoCount > 0, let videoURL = videoURLs.first else {
            print("❌ Export: No video selected")
            return
        }
        
        print("🎬 Starting video export...")
        print("📹 Video: \(videoURL.lastPathComponent)")
        print("⚙️ Processing Mode: \(projectState.useGPU ? "GPU" : "CPU")")
        
        if let primaryLUT = lutManager.selectedPrimaryLUT {
            print("🎨 Primary LUT: \(primaryLUT.displayName) (Opacity: \(Int(projectState.primaryLUTOpacity * 100))%)")
        }
        if let secondaryLUT = lutManager.selectedSecondaryLUT {
            print("🎭 Secondary LUT: \(secondaryLUT.displayName) (Opacity: \(Int(projectState.secondLUTOpacity * 100))%)")
        }
        if lutManager.selectedPrimaryLUT == nil && lutManager.selectedSecondaryLUT == nil {
            print("📱 Exporting without LUT (original video)")
        }
        
        // Start export UI state
        isExporting = true
        exportProgress = 0.0
        exportStatusMessage = "Initializing conversion..."
        
        Task {
            do {
                // Create temporary export folder
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let exportFolder = documentsPath.appendingPathComponent("LUTexport")
                
                await MainActor.run {
                    exportStatusMessage = "Creating export directory..."
                    exportProgress = 0.1
                }
                
                try FileManager.default.createDirectory(at: exportFolder, withIntermediateDirectories: true)
                print("📁 Export folder created: \(exportFolder.path)")
                
                let outputFilename = projectState.generateOutputFileName(for: videoURL)
                let outputURL = exportFolder.appendingPathComponent(outputFilename)
                
                // Remove existing file if it exists
                if FileManager.default.fileExists(atPath: outputURL.path) {
                    try FileManager.default.removeItem(at: outputURL)
                    print("🗑️ Removed existing file: \(outputURL.lastPathComponent)")
                }
                
                // Use VideoProcessor for actual LUT processing if LUTs are selected
                if lutManager.selectedPrimaryLUT != nil || lutManager.selectedSecondaryLUT != nil {
                    await MainActor.run {
                        exportStatusMessage = "Processing video with LUTs..."
                        exportProgress = 0.2
                    }
                    
                    print("🎨 Processing video with LUTs...")
                    let videoProcessor = VideoProcessor()
                    
                    // Convert ExportQuality to LUTProcessor.OutputQuality
                    let lutOutputQuality = convertToLUTProcessorQuality(projectState.exportQuality)
                    
                    let settings = VideoProcessor.ProcessingConfig(
                        videoURLs: [videoURL],
                        primaryLUTURL: lutManager.selectedPrimaryLUT?.url,
                        secondaryLUTURL: lutManager.selectedSecondaryLUT?.url,
                        primaryLUTOpacity: Float(projectState.primaryLUTOpacity),
                        secondaryLUTOpacity: Float(projectState.secondLUTOpacity),
                        whiteBalanceAdjustment: Float(projectState.whiteBalanceValue),
                        useGPUProcessing: projectState.useGPU,
                        outputQuality: lutOutputQuality,
                        outputDirectory: exportFolder
                    )
                    
                    // CRITICAL: Clean export folder before processing to avoid finding old files
                    let exportedFiles = try FileManager.default.contentsOfDirectory(at: exportFolder, includingPropertiesForKeys: nil)
                    for file in exportedFiles where file.pathExtension == "mp4" {
                        try FileManager.default.removeItem(at: file)
                        print("🗑️ Removed old export file: \(file.lastPathComponent)")
                    }
                    
                    // Subscribe to progress updates
                    let progressCancellable = videoProcessor.$exportProgress
                        .receive(on: DispatchQueue.main)
                        .sink { progress in
                            self.exportProgress = 0.2 + (progress * 0.7) // Map to 20%-90%
                        }
                    
                    let statusCancellable = videoProcessor.$statusMessage
                        .receive(on: DispatchQueue.main)
                        .sink { status in
                            self.exportStatusMessage = status
                        }
                    
                    // CRITICAL: Monitor for errors during processing
                    let errorCancellable = videoProcessor.$lastError
                        .receive(on: DispatchQueue.main)
                        .sink { error in
                            if let error = error {
                                print("❌ VideoProcessor reported error: \(error.localizedDescription)")
                            }
                        }
                    
                    await videoProcessor.processVideos(config: settings)
                    
                    progressCancellable.cancel()
                    statusCancellable.cancel()
                    errorCancellable.cancel()
                    
                    // CRITICAL: Check if processing actually succeeded
                    if let processingError = videoProcessor.lastError {
                        print("❌ VideoProcessor failed: \(processingError.localizedDescription)")
                        throw NSError(domain: "ExportError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Video processing failed: \(processingError.localizedDescription)"])
                    }
                    
                    // CRITICAL: Verify VideoProcessor actually created files
                    if videoProcessor.exportedVideoURLs.isEmpty {
                        print("❌ VideoProcessor completed but no files were exported")
                        throw NSError(domain: "ExportError", code: 3, userInfo: [NSLocalizedDescriptionKey: "No videos were exported successfully"])
                    }
                    
                    // Use the file from VideoProcessor's exported list
                    let actualOutputURL = videoProcessor.exportedVideoURLs.first!
                    
                    // Double-check the file exists and has reasonable size
                    guard FileManager.default.fileExists(atPath: actualOutputURL.path) else {
                        print("❌ Expected output file does not exist: \(actualOutputURL.path)")
                        throw NSError(domain: "ExportError", code: 4, userInfo: [NSLocalizedDescriptionKey: "Output file was not created"])
                    }
                    
                    let fileAttributes = try FileManager.default.attributesOfItem(atPath: actualOutputURL.path)
                    let fileSize = fileAttributes[.size] as? Int64 ?? 0
                    
                    if fileSize < 1024 { // Less than 1KB indicates failure
                        print("❌ Output file is suspiciously small: \(fileSize) bytes")
                        throw NSError(domain: "ExportError", code: 5, userInfo: [NSLocalizedDescriptionKey: "Output file is too small (\(fileSize) bytes), processing may have failed"])
                    }
                    
                    print("✅ Video processing verified successful: \(actualOutputURL.lastPathComponent) (Size: \(fileSize) bytes)")
                    
                    await MainActor.run {
                        self.exportedVideoURL = actualOutputURL
                        self.exportStatusMessage = "LUT processing completed!"
                        self.exportProgress = 0.95
                    }
                    
                    print("✅ LUT processing completed!")
                } else {
                    await MainActor.run {
                        exportStatusMessage = "Copying original video..."
                        exportProgress = 0.5
                    }
                    
                    // Simple copy if no LUTs selected
                    try FileManager.default.copyItem(at: videoURL, to: outputURL)
                    print("📁 No LUTs selected - copied original video")
                    
                    await MainActor.run {
                        self.exportedVideoURL = outputURL
                        self.exportStatusMessage = "Video copied successfully!"
                        self.exportProgress = 0.95
                    }
                }
                
                await MainActor.run {
                    self.exportStatusMessage = "Conversion completed!"
                    self.exportProgress = 1.0
                    self.isExporting = false
                    self.isConversionComplete = true
                    self.showingSaveToPhotos = true
                }
                
                print("✅ Export completed successfully!")
                print("📁 Exported to: \(self.exportedVideoURL?.path ?? "Unknown")")
                
            } catch {
                print("❌ Export failed: \(error.localizedDescription)")
                await MainActor.run {
                    self.isExporting = false
                    self.exportProgress = 0.0
                    self.exportStatusMessage = "Export failed: \(error.localizedDescription)"
                    self.isConversionComplete = false
                    projectState.updateStatus("Export failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func saveToPhotos() {
        guard let videoURL = exportedVideoURL else { return }
        
        print("📱 Saving video to Photos...")
        print("📁 Video URL: \(videoURL.path)")
        print("📁 File exists: \(FileManager.default.fileExists(atPath: videoURL.path))")
        
        // Check if file exists and is readable
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            print("❌ Video file does not exist at path: \(videoURL.path)")
            projectState.updateStatus("Video file not found")
            return
        }
        
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized, .limited:
                    print("✅ Photos access authorized, attempting to save...")
                    PHPhotoLibrary.shared().performChanges({
                        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
                    }) { success, error in
                        DispatchQueue.main.async {
                            if success {
                                print("✅ Video saved to Photos successfully!")
                                projectState.updateStatus("Video saved to Photos")
                                self.isSavedToPhotos = true
                                self.saveToPhotosMessage = "✅ Video successfully saved to Photos!"
                            } else {
                                print("❌ Failed to save video to Photos: \(error?.localizedDescription ?? "Unknown error")")
                                if let error = error {
                                    print("❌ Error details: \(error)")
                                }
                                projectState.updateStatus("Failed to save to Photos")
                                self.saveToPhotosMessage = "❌ Failed to save to Photos: \(error?.localizedDescription ?? "Unknown error")"
                            }
                        }
                    }
                case .denied, .restricted:
                    print("❌ Photos access denied")
                    projectState.updateStatus("Photos access denied")
                    self.saveToPhotosMessage = "❌ Photos access denied. Please enable in Settings."
                case .notDetermined:
                    print("❌ Photos access not determined")
                    projectState.updateStatus("Photos access required")
                    self.saveToPhotosMessage = "❌ Photos access required. Please grant permission."
                @unknown default:
                    print("❌ Unknown Photos authorization status")
                    projectState.updateStatus("Photos access error")
                    self.saveToPhotosMessage = "❌ Photos access error occurred."
                }
            }
        }
    }
    
    private func resetConversion() {
        // Reset all conversion states
        isExporting = false
        exportProgress = 0.0
        exportStatusMessage = ""
        isConversionComplete = false
        showingSaveToPhotos = false
        exportedVideoURL = nil
        isSavedToPhotos = false
        saveToPhotosMessage = ""
        
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
        
        // Reset opacity sliders
        projectState.primaryLUTOpacity = 1.0
        projectState.secondLUTOpacity = 1.0
        
        print("🔄 Conversion reset - ready for new conversion")
        projectState.updateStatus("Ready for new conversion")
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