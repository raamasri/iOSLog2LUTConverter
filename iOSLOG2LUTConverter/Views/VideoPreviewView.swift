import SwiftUI
import AVFoundation

// MARK: - Prominent Video Preview Component with Apple Design
struct VideoPreviewView: View {
    @State private var previewImage: Image?
    @State private var isLoading: Bool = false
    @State private var showControls: Bool = false
    @Environment(\.colorScheme) var colorScheme
    
    // Callback to trigger photo picker from parent
    var onImportVideoTapped: (() -> Void)?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Black background for video content
                Rectangle()
                    .fill(.black)
                
                // Preview content or placeholder
                Group {
                    if let previewImage = previewImage {
                        // Actual video preview
                        previewImage
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .transition(.opacity.combined(with: .scale))
                    } else if isLoading {
                        // Loading state with Apple-like spinner
                        loadingView
                    } else {
                        // Empty state with glassy design
                        emptyStateView
                    }
                }
                
                // Preview controls overlay (when video is loaded)
                if previewImage != nil {
                    previewControlsOverlay
                        .opacity(showControls ? 1.0 : 0.0)
                        .animation(.easeInOut(duration: 0.3), value: showControls)
                }
                
                // LUT preview indicator (top right)
                lutIndicator
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(16)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 15, x: 0, y: 8)
            .onTapGesture {
                if previewImage != nil {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showControls.toggle()
                    }
                }
            }
        }
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
    
    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.2)
            
            Text("Generating Preview...")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(32)
        .background(
            .ultraThinMaterial.opacity(0.3),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }
    
    // MARK: - Preview Controls Overlay
    private var previewControlsOverlay: some View {
        VStack {
            Spacer()
            
            HStack(spacing: 20) {
                // Previous frame
                Button(action: {}) {
                    Image(systemName: "backward.frame.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                
                // Play/Pause
                Button(action: {}) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.3), radius: 5)
                }
                .buttonStyle(.plain)
                
                // Next frame
                Button(action: {}) {
                    Image(systemName: "forward.frame.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .background(
                .ultraThinMaterial.opacity(0.7),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .padding(.bottom, 20)
        }
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
        .opacity(previewImage != nil ? 1.0 : 0.0)
        .animation(.easeInOut(duration: 0.3), value: previewImage != nil)
    }
    
    // MARK: - Simulation Methods (for demonstration)
    private func simulateVideoImport() {
        isLoading = true
        
        // Simulate loading delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isLoading = false
            
            // Create a placeholder preview image
            withAnimation(.easeInOut(duration: 0.5)) {
                previewImage = Image(systemName: "video.fill")
            }
        }
    }
}

// MARK: - Preview
#Preview {
    VStack {
        VideoPreviewView()
            .frame(height: 400)
            .padding()
        
        Spacer()
    }
    .background(.black)
    .preferredColorScheme(.dark)
}

#Preview("With Video") {
    VStack {
        VideoPreviewView()
            .frame(height: 400)
            .padding()
            .onAppear {
                // Simulate having a video loaded
            }
        
        Spacer()
    }
    .background(.black)
    .preferredColorScheme(.dark)
} 