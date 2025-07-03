# VideoLUT Converter: iOS/iPadOS Migration Implementation Plan

## Executive Summary

The macOS VideoLUT Converter is a **mature, professional-grade application** with:
- **1,287 lines of Swift code** across 8 core files
- **Universal binary support** (Intel + Apple Silicon)
- **Professional drag & drop interface**
- **Advanced FFmpeg integration** with 76MB universal binary
- **Real-time preview and batch processing**
- **95/100 App Store readiness score**

This document provides a comprehensive migration strategy from the existing macOS codebase to iOS/iPadOS, maintaining all functionality while adding mobile-specific enhancements.

## Current macOS Architecture Analysis

### **Core Components to Migrate**

| Component | Lines | Purpose | iOS Migration Strategy |
|-----------|--------|---------|----------------------|
| `ViewController.swift` | 597 | Main UI controller | → Split into SwiftUI views + UIKit controllers |
| `FFmpegManager.swift` | 281 | Universal FFmpeg handling | → Replace with VideoToolbox + AVFoundation |
| `ProcessManager.swift` | 206 | Process execution & progress | → Background processing with URLSession |
| `DragDropView.swift` | 256 | Custom drag & drop UI | → UIDocumentPickerViewController + native drag/drop |
| `FilterBuilder.swift` | 171 | FFmpeg filter generation | → Core Image filter pipeline |
| `ProjectState.swift` | 135 | State management | → Enhanced with Core Data persistence |
| `StringUtilities.swift` | 37 | Text processing | → Direct port |
| `Constants.swift` | 34 | App configuration | → iOS-specific constants |

### **Key Features Requiring Migration**

```swift
// Current macOS Features → iOS Implementation
✅ Dual LUT processing → Core Image CIColorCube filters
✅ Real-time preview → Metal + CIContext rendering
✅ Batch processing → Background processing framework
✅ Universal FFmpeg → VideoToolbox + AVAssetExportSession
✅ Drag & drop → UIDocumentPickerViewController
✅ Progress tracking → NSProgress + Combine publishers
✅ GPU/CPU modes → Hardware acceleration APIs
✅ White balance → Core Image color adjustment
```

## Migration Strategy

### **Phase 1: Foundation Setup (3-4 weeks)**

#### **1.1 Project Structure Migration**
```swift
// Create iOS-equivalent architecture
iOS Project Structure:
├── Models/
│   ├── ProjectState.swift (Enhanced)
│   ├── ExportSettings.swift (New)
│   └── ValidationResult.swift (Extracted)
├── Views/
│   ├── ContentView.swift (SwiftUI root)
│   ├── VideoPreviewView.swift (Metal rendering)
│   ├── FileImportView.swift (Document picker)
│   └── ControlsView.swift (LUT + export controls)
├── Services/
│   ├── VideoProcessor.swift (Replace FFmpeg)
│   ├── LUTProcessor.swift (Core Image)
│   └── BackgroundExportManager.swift (New)
├── Utilities/
│   ├── StringUtilities.swift (Direct port)
│   ├── FileUtilities.swift (iOS file handling)
│   └── Constants.swift (iOS-specific)
└── Resources/
    ├── Sample.cube (LUT files)
    └── Help.bundle (Documentation)
```

#### **1.2 Enhanced ProjectState for iOS**
```swift
// Migrate and enhance ProjectState.swift
@MainActor
class ProjectState: ObservableObject {
    // Existing properties (direct migration)
    @Published var videoURLs: [URL] = []
    @Published var primaryLUTURL: URL?
    @Published var secondaryLUTURL: URL?
    @Published var secondLUTOpacity: Float = 1.0
    @Published var useGPU: Bool = true
    @Published var whiteBalanceValue: Float = 0.0
    
    // New iOS-specific properties
    @Published var isExporting: Bool = false
    @Published var backgroundExportProgress: [String: Double] = [:]
    @Published var exportQuality: ExportQuality = .high
    @Published var shouldOptimizeForBattery: Bool = true
    
    // Core Data integration
    @Published var recentProjects: [RecentProject] = []
    @Published var favoriteProjects: [FavoriteProject] = []
    
    // iOS-specific computed properties
    var canExportInBackground: Bool {
        return !videoURLs.isEmpty && primaryLUTURL != nil
    }
    
    var estimatedExportTime: TimeInterval {
        // Calculate based on video duration and device performance
        return 0.0 // TODO: Implement calculation
    }
    
    var estimatedFileSize: Int64 {
        // Calculate based on video bitrate and settings
        return 0 // TODO: Implement calculation
    }
}
```

### **Phase 2: Core Video Processing (4-5 weeks)**

#### **2.1 Replace FFmpeg with Native iOS APIs**

**Current FFmpeg Pipeline:**
```swift
// Current: FFmpegManager.swift (281 lines)
class FFmpegManager {
    static func getFFmpegPath() throws -> String // 76MB binary
    func executeFFmpeg(arguments: [String]) -> Bool
}
```

**New iOS Video Processing:**
```swift
// New: VideoProcessor.swift
import AVFoundation
import VideoToolbox
import CoreImage
import Metal

class VideoProcessor: ObservableObject {
    private let ciContext: CIContext
    private let metalDevice: MTLDevice
    
    func processVideo(
        asset: AVAsset,
        primaryLUT: CIFilter,
        secondaryLUT: CIFilter? = nil,
        opacity: Float = 1.0,
        whiteBalance: Float = 0.0,
        outputURL: URL,
        progress: @escaping (Double) -> Void
    ) async throws -> Bool {
        
        // Create video composition with Core Image
        let videoComposition = AVVideoComposition(
            asset: asset,
            applyingCIFiltersWithHandler: { request in
                var outputImage = request.sourceImage
                
                // Apply primary LUT
                primaryLUT.setValue(outputImage, forKey: kCIInputImageKey)
                outputImage = primaryLUT.outputImage ?? outputImage
                
                // Apply secondary LUT with opacity
                if let secondaryLUT = secondaryLUT {
                    secondaryLUT.setValue(outputImage, forKey: kCIInputImageKey)
                    if let lutOutput = secondaryLUT.outputImage {
                        let blendFilter = CIFilter(name: "CISourceOverCompositing")!
                        blendFilter.setValue(lutOutput, forKey: kCIInputImageKey)
                        blendFilter.setValue(outputImage, forKey: kCIInputBackgroundImageKey)
                        outputImage = blendFilter.outputImage ?? outputImage
                    }
                }
                
                // Apply white balance
                if whiteBalance != 0.0 {
                    let temperatureFilter = CIFilter(name: "CITemperatureAndTint")!
                    temperatureFilter.setValue(outputImage, forKey: kCIInputImageKey)
                    temperatureFilter.setValue(whiteBalance * 1000, forKey: "inputNeutral")
                    outputImage = temperatureFilter.outputImage ?? outputImage
                }
                
                request.finish(with: outputImage, context: self.ciContext)
            }
        )
        
        // Export using AVAssetExportSession
        let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetHighestQuality
        )
        
        exportSession?.videoComposition = videoComposition
        exportSession?.outputURL = outputURL
        exportSession?.outputFileType = .mp4
        
        // Progress monitoring
        let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            progress(Double(exportSession?.progress ?? 0))
        }
        
        await exportSession?.export()
        progressTimer.invalidate()
        
        return exportSession?.status == .completed
    }
}
```

#### **2.2 LUT Processing with Core Image**
```swift
// Replace FilterBuilder.swift with LUTProcessor.swift
class LUTProcessor {
    func loadLUT(from url: URL) throws -> CIFilter {
        let data = try Data(contentsOf: url)
        let lutData = try parseCubeFile(data)
        
        let filter = CIFilter(name: "CIColorCube")!
        filter.setValue(lutData, forKey: "inputCubeData")
        filter.setValue(64, forKey: "inputCubeDimension")
        
        return filter
    }
    
    private func parseCubeFile(_ data: Data) throws -> Data {
        // Parse .cube file format
        // Convert to RGB cube data format required by Core Image
        // This is a complex implementation that handles:
        // - 3D LUT cube format parsing
        // - RGB value interpolation
        // - Proper data structure for CIColorCube
        return Data() // TODO: Implement cube file parsing
    }
}
```

### **Phase 3: UI Migration (3-4 weeks)**

#### **3.1 SwiftUI Interface Architecture**
```swift
// Replace 597-line ViewController.swift with SwiftUI
@main
struct VideoLUTConverterApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @StateObject private var projectState = ProjectState()
    
    var body: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            iPadInterface()
        } else {
            iPhoneInterface()
        }
    }
    
    private func iPadInterface() -> some View {
        HSplitView {
            // Left panel: Controls (similar to current macOS layout)
            VStack(alignment: .leading, spacing: 20) {
                FileImportSection()
                LUTControlsSection()
                ExportControlsSection()
            }
            .frame(minWidth: 320, maxWidth: 400)
            .padding()
            
            // Right panel: Preview (maintains current preview functionality)
            VideoPreviewView(projectState: projectState)
                .frame(minWidth: 600)
        }
    }
    
    private func iPhoneInterface() -> some View {
        NavigationView {
            VStack {
                // Full-width preview
                VideoPreviewView(projectState: projectState)
                    .aspectRatio(16/9, contentMode: .fit)
                
                // Scrollable controls
                ScrollView {
                    VStack(spacing: 20) {
                        FileImportSection()
                        LUTControlsSection()
                        ExportControlsSection()
                    }
                    .padding()
                }
            }
        }
    }
}
```

#### **3.2 File Import (Replace DragDropView)**
```swift
// Replace DragDropView.swift with iOS document picker
struct FileImportSection: View {
    @StateObject private var projectState = ProjectState()
    @State private var showingVideoPicker = false
    @State private var showingLUTPicker = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Video import (maintains current functionality)
            Button(action: { showingVideoPicker = true }) {
                ImportButtonView(
                    title: "Import Videos",
                    subtitle: "\(projectState.videoURLs.count) files selected",
                    systemImage: "video.fill"
                )
            }
            .sheet(isPresented: $showingVideoPicker) {
                DocumentPicker(
                    types: [.movie, .video],
                    allowsMultipleSelection: true
                ) { urls in
                    projectState.videoURLs = urls
                }
            }
            
            // LUT import (maintains current functionality)  
            Button(action: { showingLUTPicker = true }) {
                ImportButtonView(
                    title: "Import LUT",
                    subtitle: projectState.primaryLUTURL?.lastPathComponent ?? "No LUT selected",
                    systemImage: "camera.filters"
                )
            }
            .sheet(isPresented: $showingLUTPicker) {
                DocumentPicker(
                    types: [UTType(filenameExtension: "cube")!],
                    allowsMultipleSelection: false
                ) { urls in
                    projectState.primaryLUTURL = urls.first
                }
            }
        }
    }
}
```

### **Phase 4: Background Processing (2-3 weeks)**

#### **4.1 Background Export Manager**
```swift
// New capability not in macOS version
import BackgroundTasks

class BackgroundExportManager: ObservableObject {
    @Published var backgroundExports: [BackgroundExport] = []
    
    func scheduleBackgroundExport(project: ProjectState) throws {
        let request = BGProcessingTaskRequest(identifier: "com.videolut.export")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 1)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        
        try BGTaskScheduler.shared.submit(request)
    }
    
    func handleBackgroundExport(task: BGProcessingTask) {
        // Process video export in background
        // This extends beyond current macOS capabilities
    }
}
```

### **Phase 5: iOS-Specific Enhancements (1-2 weeks)**

#### **5.1 Hardware Optimization**
```swift
// Battery and thermal management (new iOS capabilities)
class PerformanceManager: ObservableObject {
    @Published var thermalState: ProcessInfo.ThermalState = .nominal
    @Published var batteryLevel: Float = 1.0
    @Published var isLowPowerModeEnabled: Bool = false
    
    func optimizeForDevice() -> ExportQuality {
        // Adjust export quality based on device capabilities
        // This is iOS-specific optimization
        return .high
    }
}
```

#### **5.2 iOS Ecosystem Integration**
```swift
// Features not available in macOS
import Photos
import Intents

class iOSIntegrationManager {
    func exportToPhotos(videoURL: URL) async throws {
        // Save to Photos library
    }
    
    func createSiriShortcut(for project: ProjectState) {
        // Create Siri Shortcuts for common workflows
    }
    
    func shareVideo(url: URL) -> UIActivityViewController {
        // Enhanced sharing with iOS share sheet
        return UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
}
```

## Migration Timeline & Priorities

### **Updated Realistic Timeline: 12-16 weeks**

| Phase | Duration | Critical Path | Dependencies |
|-------|----------|---------------|--------------|
| **Phase 1: Foundation** | 3-4 weeks | Project structure, Enhanced ProjectState | None |
| **Phase 2: Video Processing** | 4-5 weeks | FFmpeg → VideoToolbox migration | Phase 1 |
| **Phase 3: UI Migration** | 3-4 weeks | SwiftUI interface, File handling | Phase 1 |
| **Phase 4: Background Processing** | 2-3 weeks | iOS background tasks | Phase 2 |
| **Phase 5: iOS Enhancements** | 1-2 weeks | Platform integration | All phases |

### **Risk Assessment & Mitigation**

| Risk | Probability | Impact | Mitigation Strategy |
|------|-------------|--------|-------------------|
| **Core Image LUT limitations** | High | High | Implement Metal shaders as fallback |
| **VideoToolbox compatibility** | Medium | High | Extensive testing on all device types |
| **Performance on older devices** | Medium | Medium | Adaptive quality settings |
| **Battery usage concerns** | Low | Medium | Thermal/battery monitoring |

## Implementation Recommendations

### **Immediate Next Steps**

1. **Create iOS Project Structure** (Week 1)
   ```bash
   # Set up enhanced iOS project
   mkdir -p iOS/Models iOS/Views iOS/Services iOS/Utilities
   # Copy and begin migrating Swift files
   ```

2. **Begin ProjectState Migration** (Week 1-2)
   - Direct port of existing ProjectState.swift
   - Add iOS-specific properties
   - Implement Core Data persistence

3. **Prototype Video Processing** (Week 2-3)
   - Create basic VideoProcessor with Core Image
   - Test LUT loading and application
   - Verify performance on actual devices

4. **UI Prototyping** (Week 3-4)
   - Create SwiftUI interface matching macOS layout
   - Implement document picker for file import
   - Test on iPhone and iPad

### **Success Metrics**

- **Feature Parity**: 100% of macOS features working on iOS
- **Performance**: Real-time preview at 30fps on iPhone 12+
- **Battery**: <20% additional drain during export
- **User Experience**: <2 taps to start export process
- **App Store**: Pass all iOS App Store requirements

## Conclusion

The VideoLUT Converter macOS app is a **sophisticated, production-ready application** that requires a comprehensive migration strategy. The existing codebase provides an excellent foundation with:

- **Clean, well-architected Swift code**
- **Universal platform compatibility**
- **Professional user interface**
- **Advanced video processing capabilities**

The migration to iOS will **enhance and expand** these capabilities by adding:
- **Mobile-optimized interface**
- **Background processing**
- **iOS ecosystem integration**
- **Hardware-accelerated performance**

This plan provides a realistic roadmap for creating a **best-in-class iOS video processing application** that maintains the professional quality of the macOS original while leveraging iOS-specific capabilities.

---

*This document serves as the definitive implementation guide for the iOS/iPadOS migration project and should be referenced throughout the development process.* 