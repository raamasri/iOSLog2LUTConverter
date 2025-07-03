import SwiftUI
import PhotosUI
import CoreTransferable

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
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
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
        }
        // Handle photo picker selection
        .onChange(of: selectedVideoItems) { _, newItems in
            guard let item = newItems.first else { return }
            
            item.loadTransferable(type: Movie.self) { result in
                DispatchQueue.main.async {
                    switch result {
                                         case .success(let movie?):
                         let url = movie.url
                         self.videoURLs = [url]
                         self.videoCount = 1
                         print("✅ Video imported successfully: \(url.lastPathComponent)")
                    case .failure(let error):
                        print("❌ Failed to import video: \(error)")
                    case .success(.none):
                        print("❌ No video data found")
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
            }
            
            Text("Professional Video LUT Processing")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 8)
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
                    maxSelectionCount: 1,
                    matching: .videos
                ) {
                    HStack {
                        VStack(spacing: 8) {
                            Image(systemName: "video.fill")
                                .font(.title2)
                                .foregroundStyle(videoCount > 0 ? .white : .blue)
                            
                            VStack(spacing: 4) {
                                Text("Import Video")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(videoCount > 0 ? .white : .primary)
                                
                                Text(videoCount == 0 ? "No video selected" : "Video selected: \(videoURLs.first?.lastPathComponent ?? "")")
                                    .font(.caption)
                                    .foregroundStyle(videoCount > 0 ? .white.opacity(0.8) : .secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(videoCount > 0 ? AnyShapeStyle(Color.blue.gradient) : AnyShapeStyle(Color(.systemGray6)))
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
                                     .fill(lutManager.hasSelectedPrimaryLUT ? AnyShapeStyle(Color.green.gradient) : AnyShapeStyle(Color(.systemGray6)))
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
                                     .fill(lutManager.hasSelectedSecondaryLUT ? AnyShapeStyle(Color.pink.gradient) : AnyShapeStyle(Color(.systemGray6)))
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
            
            // Processing Mode Toggle
            VStack(alignment: .leading) {
                Text("Processing Mode")
                    .font(.subheadline)
                
                Picker("Processing Mode", selection: $projectState.useGPU) {
                    Text("CPU").tag(false)
                    Text("GPU").tag(true)
                }
                .pickerStyle(SegmentedPickerStyle())
            }
            .padding(16)
            .background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            
            // Export Button
            Button(action: {
                print("🎬 Exporting video...")
                if let primaryLUT = lutManager.selectedPrimaryLUT {
                    print("📹 Primary LUT: \(primaryLUT.displayName)")
                }
                if let secondaryLUT = lutManager.selectedSecondaryLUT {
                    print("🎨 Secondary LUT: \(secondaryLUT.displayName) (Opacity: \(Int(projectState.secondLUTOpacity * 100))%)")
                }
                if lutManager.selectedPrimaryLUT == nil && lutManager.selectedSecondaryLUT == nil {
                    print("📱 Exporting without LUT (original video)")
                }
            }) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title3)
                    
                    Text("Export Video")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(
                    videoCount > 0 ? Color.blue.gradient : Color.gray.gradient,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(videoCount == 0)
        }
    }
    
    // MARK: - Status Section
    private var statusSection: some View {
        VStack(spacing: 8) {
            Text("Status")
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
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
        VideoPreviewView(onImportVideoTapped: triggerVideoImport)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Helper Methods
    private func triggerVideoImport() {
        // This will trigger the PhotosPicker by clearing and setting the selection
        selectedVideoItems = []
        // The PhotosPicker will be triggered by the PhotosPicker in the file import section
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