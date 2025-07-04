import SwiftUI
import AVFoundation
import UIKit

// MARK: - Prominent Video Preview Component with Apple Design
struct VideoPreviewView: View {
    @ObservedObject var projectState: ProjectState
    @State private var showingBeforeInToggle = false // For A/B toggle mode
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.black
                
                // Main preview content
                if projectState.showBeforeAfter && projectState.rawPreviewImage != nil && projectState.previewImage != nil {
                    // Before/After comparison view
                    beforeAfterPreviewView(geometry: geometry)
                } else {
                    // Standard single preview view
                    standardPreviewView(geometry: geometry)
                }
                
                // Controls overlay
                previewControlsOverlay
            }
        }
        .clipped()
    }
    
    // MARK: - Standard Preview View
    private func standardPreviewView(geometry: GeometryProxy) -> some View {
        Group {
            if let previewImage = projectState.previewImage {
                Image(uiImage: previewImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
            } else if projectState.isPreviewLoading {
                loadingView
            } else {
                placeholderView
            }
        }
    }
    
    // MARK: - Before/After Preview Views
    private func beforeAfterPreviewView(geometry: GeometryProxy) -> some View {
        Group {
            switch projectState.beforeAfterMode {
            case .sideBySide:
                sideBySideView(geometry: geometry)
            case .verticalSplit:
                verticalSplitView(geometry: geometry)
            case .toggle:
                toggleView(geometry: geometry)
            }
        }
    }
    
    private func sideBySideView(geometry: GeometryProxy) -> some View {
        HStack(spacing: 2) {
            // Before (Original)
            VStack(spacing: 4) {
                if let rawImage = projectState.rawPreviewImage {
                    Image(uiImage: rawImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: (geometry.size.width - 2) / 2, maxHeight: geometry.size.height - 40)
                        .clipped()
                }
                
                Text("BEFORE")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        .black.opacity(0.6),
                        in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                    )
            }
            
            // After (LUT processed)
            VStack(spacing: 4) {
                if let processedImage = projectState.previewImage {
                    Image(uiImage: processedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: (geometry.size.width - 2) / 2, maxHeight: geometry.size.height - 40)
                        .clipped()
                }
                
                Text("AFTER")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        .black.opacity(0.6),
                        in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                    )
            }
        }
    }
    
    private func verticalSplitView(geometry: GeometryProxy) -> some View {
        VStack(spacing: 2) {
            // Before (Original) - Top
            HStack {
                if let rawImage = projectState.rawPreviewImage {
                    Image(uiImage: rawImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: geometry.size.width, maxHeight: (geometry.size.height - 2) / 2)
                        .clipped()
                }
                
                Spacer()
                
                Text("BEFORE")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        .black.opacity(0.6),
                        in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                    )
                    .offset(x: -10)
            }
            
            // After (LUT processed) - Bottom
            HStack {
                if let processedImage = projectState.previewImage {
                    Image(uiImage: processedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: geometry.size.width, maxHeight: (geometry.size.height - 2) / 2)
                        .clipped()
                }
                
                Spacer()
                
                Text("AFTER")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        .black.opacity(0.6),
                        in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                    )
                    .offset(x: -10)
            }
        }
    }
    
    private func toggleView(geometry: GeometryProxy) -> some View {
        Group {
            if showingBeforeInToggle {
                if let rawImage = projectState.rawPreviewImage {
                    Image(uiImage: rawImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
                        .transition(.opacity)
                }
            } else {
                if let processedImage = projectState.previewImage {
                    Image(uiImage: processedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showingBeforeInToggle)
    }
    
    // MARK: - Empty State View with Glassy Design
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            // Large video icon with subtle animation
            Image(systemName: "play.rectangle")
                .font(.system(size: 80, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.4))
                .symbolEffect(.pulse.byLayer, options: .repeating)
            
            VStack(spacing: 8) {
                Text("Import a Video to Begin")
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundStyle(.white.opacity(0.8))
                
                Text("Select videos and LUTs to see a live preview")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            
            // Removed Import Video button - use the one below in the controls section
        }
        .padding(40)
        .background(
            // Subtle gradient overlay
            RadialGradient(
                gradient: Gradient(colors: [
                    .blue.opacity(0.1),
                    .clear
                ]),
                center: .center,
                startRadius: 50,
                endRadius: 200
            )
        )
    }
    
    // MARK: - Helper Views
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
            
            Text("Generating preview...")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var placeholderView: some View {
        VStack(spacing: 20) {
            Image(systemName: "video.badge.plus")
                .font(.system(size: 60))
                .foregroundStyle(.white.opacity(0.3))
            
            Text("Select a video to preview")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundStyle(.white.opacity(0.7))
            
            Text("Import a video file to see the preview with LUT effects")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Preview Controls Overlay
    private var previewControlsOverlay: some View {
        VStack {
            // Before/After comparison controls
            beforeAfterControls
            
            Spacer()
            
            // Timeline Scrubber
            timelineControls
        }
    }
    
    // MARK: - Before/After Comparison Controls
    private var beforeAfterControls: some View {
        VStack(spacing: 12) {
            // Before/After Toggle
            HStack {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        projectState.showBeforeAfter.toggle()
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: projectState.showBeforeAfter ? "eye.fill" : "eye")
                            .font(.caption)
                        
                        Text(projectState.showBeforeAfter ? "Hide Comparison" : "Show Before/After")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        .ultraThinMaterial.opacity(0.8),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                // Only show when before/after is enabled and we have both images
                if projectState.showBeforeAfter && projectState.rawPreviewImage != nil && projectState.previewImage != nil {
                    // Comparison mode picker
                    Picker("Comparison Mode", selection: $projectState.beforeAfterMode) {
                        ForEach(ProjectState.BeforeAfterMode.allCases, id: \.self) { mode in
                            HStack(spacing: 4) {
                                Image(systemName: mode.icon)
                                    .font(.caption2)
                                Text(mode.displayName)
                                    .font(.caption2)
                            }
                            .tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .foregroundStyle(.white)
                    .background(
                        .ultraThinMaterial.opacity(0.8),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                }
            }
            
            // A/B Toggle buttons (only for toggle mode)
            if projectState.showBeforeAfter && projectState.beforeAfterMode == .toggle {
                HStack(spacing: 16) {
                    Button("Before (Original)") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showingBeforeInToggle = true
                        }
                    }
                    .foregroundStyle(showingBeforeInToggle ? .blue : .white)
                    .fontWeight(showingBeforeInToggle ? .semibold : .regular)
                    
                    Button("After (LUT)") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showingBeforeInToggle = false
                        }
                    }
                    .foregroundStyle(!showingBeforeInToggle ? .blue : .white)
                    .fontWeight(!showingBeforeInToggle ? .semibold : .regular)
                }
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    .ultraThinMaterial.opacity(0.8),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
            }
        }
        .padding(.top, 20)
        .opacity(projectState.videoURLs.isEmpty ? 0 : 1)
        .animation(.easeInOut(duration: 0.3), value: projectState.showBeforeAfter)
    }
    
    // MARK: - Timeline Controls
    private var timelineControls: some View {
        VStack(spacing: 12) {
            // Time display
            HStack {
                Text(formatTime(projectState.currentTime))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                
                Spacer()
                
                Text(formatTime(projectState.videoDuration))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 4)
            
            // Scrubbing timeline
            VStack(spacing: 8) {
                if projectState.videoDuration > 0 {
                    Slider(
                        value: Binding(
                            get: { projectState.currentTime },
                            set: { newTime in
                                projectState.scrubToTime(newTime)
                            }
                        ),
                        in: 0...projectState.videoDuration
                    ) {
                        // Label
                    } minimumValueLabel: {
                        Image(systemName: "backward.end.fill")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                    } maximumValueLabel: {
                        Image(systemName: "forward.end.fill")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .tint(.blue)
                    .disabled(projectState.isScrubbing || projectState.isPreviewLoading)
                    
                    // Loading indicator for scrubbing
                    if projectState.isScrubbing {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.7)
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            
                            Text("Generating preview...")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                } else {
                    // Placeholder when no video duration is available
                    HStack(spacing: 8) {
                        Image(systemName: "video.slash")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                        
                        Text("Load video to enable scrubbing")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
        }
        .padding(16)
        .background(
            .ultraThinMaterial.opacity(0.8),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .padding(.bottom, 20)
    }
    
    // MARK: - LUT Indicator
    private var lutIndicator: some View {
        HStack(spacing: 8) {
            Image(systemName: "camera.filters")
                .font(.caption)
                .foregroundStyle(.blue)
            
            Text("LUT Applied")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            .thickMaterial,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .opacity(projectState.previewImage != nil ? 1.0 : 0.0)
        .animation(.easeInOut(duration: 0.3), value: projectState.previewImage != nil)
    }
    
    // MARK: - Debug Mode Indicator
    private var debugModeIndicator: some View {
        HStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.caption)
                .foregroundStyle(.yellow)
            
            Text("Debug Mode")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            .ultraThinMaterial.opacity(0.7),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }
    
    // MARK: - Before/After Toggle Button
    private var beforeAfterToggle: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.3)) {
                projectState.showBeforeAfter.toggle()
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: projectState.showBeforeAfter ? "eye.slash" : "eye")
                    .font(.caption)
                    .foregroundStyle(.white)
                
                Text(projectState.showBeforeAfter ? "Before" : "After")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                projectState.showBeforeAfter ? .red.opacity(0.8) : .blue.opacity(0.8),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Simulation Methods (for demonstration)
    private func simulateVideoImport() {
        projectState.isPreviewLoading = true
        
        // Simulate loading delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            projectState.isPreviewLoading = false
            
                         // Create a placeholder preview image
             withAnimation(.easeInOut(duration: 0.5)) {
                 // This will be set by the actual preview generation
                 projectState.updateStatus("Placeholder preview ready")
             }
        }
    }
    
    // MARK: - Helper Methods
    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && !seconds.isNaN else { return "0:00" }
        
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

// MARK: - Preview
#Preview {
    VStack {
        VideoPreviewView(projectState: ProjectState())
            .frame(height: 400)
            .padding()
        
        Spacer()
    }
    .background(.black)
    .preferredColorScheme(.dark)
}

#Preview("With Video") {
    VStack {
        VideoPreviewView(projectState: ProjectState())
            .frame(height: 400)
            .padding()
            .onAppear {
                // Simulate having a video loaded
                // This will now trigger the debug mode gesture
            }
        
        Spacer()
    }
    .background(.black)
    .preferredColorScheme(.dark)
} 