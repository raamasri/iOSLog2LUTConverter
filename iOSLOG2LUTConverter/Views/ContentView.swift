import SwiftUI

// MARK: - Main App Content View with Apple Design Language
struct ContentView: View {
    @StateObject private var fileImportManager = FileImportManager()
    @State private var videoCount = 0
    @State private var lutSelected = false
    @State private var secondaryLutSelected = false
    @State private var videoURLs: [URL] = []
    @State private var primaryLUTURL: URL?
    @State private var secondaryLUTURL: URL?
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
        // Native iOS file import functionality
        .fileImporter(
            isPresented: $fileImportManager.isShowingVideoPicker,
            allowedContentTypes: FileImportManager.SupportedVideoTypes.types,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                for url in urls {
                    fileImportManager.importVideo(from: url)
                }
                videoURLs = urls
                videoCount = urls.count
            case .failure(let error):
                print("Error importing videos: \(error.localizedDescription)")
            }
        }
        .fileImporter(
            isPresented: $fileImportManager.isShowingLUTPicker,
            allowedContentTypes: FileImportManager.SupportedLUTTypes.types,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    fileImportManager.importLUT(from: url)
                    primaryLUTURL = url
                    lutSelected = true
                }
            case .failure(let error):
                print("Error importing LUT: \(error.localizedDescription)")
            }
        }
        .fileImporter(
            isPresented: $fileImportManager.isShowingSecondaryLUTPicker,
            allowedContentTypes: FileImportManager.SupportedLUTTypes.types,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    fileImportManager.importLUT(from: url, isSecondary: true)
                    secondaryLUTURL = url
                    secondaryLutSelected = true
                }
            case .failure(let error):
                print("Error importing secondary LUT: \(error.localizedDescription)")
            }
        }
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
            
            // LUT Controls Section
            lutControlsSection
            
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
    
    // MARK: - File Import Section with Real Import Functionality
    private var fileImportSection: some View {
        VStack(spacing: 16) {
            Text("Import Files")
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Video Import Button with corrected signature
            ImportButton(
                title: "Import Videos",
                subtitle: videoCount == 0 ? "No videos selected" : "\(videoCount) video(s) selected",
                systemImage: "video.fill",
                isSelected: videoCount > 0
            ) {
                fileImportManager.isShowingVideoPicker = true
            }
            
            // Primary LUT Import Button
            ImportButton(
                title: "Primary LUT",
                subtitle: lutSelected ? primaryLUTURL?.lastPathComponent ?? "LUT selected" : "No LUT selected",
                systemImage: "camera.filters",
                isSelected: lutSelected
            ) {
                fileImportManager.isShowingLUTPicker = true
            }
            
            // Secondary LUT Import Button
            ImportButton(
                title: "Secondary LUT (Optional)",
                subtitle: secondaryLutSelected ? secondaryLUTURL?.lastPathComponent ?? "LUT selected" : "No secondary LUT",
                systemImage: "camera.filters",
                isSelected: secondaryLutSelected
            ) {
                fileImportManager.isShowingSecondaryLUTPicker = true
            }
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
                // Opacity Slider (only visible when secondary LUT is selected)
                if secondaryLutSelected {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Secondary LUT Opacity")
                                .font(.subheadline)
                            Spacer()
                            Text("100%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Slider(value: .constant(1.0), in: 0...1)
                            .tint(.blue)
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
                        Text("5500K")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Slider(value: .constant(0.0), in: -10...10)
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
                
                Picker("Processing Mode", selection: .constant(true)) {
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
                // TODO: Implement export functionality
            }) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title3)
                    
                    Text("Export Videos")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(
                    (videoCount > 0 && lutSelected) ? Color.blue.gradient : Color.gray.gradient,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(videoCount == 0 || !lutSelected)
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
        VideoPreviewView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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