# VideoLUT Converter: iOS/iPadOS Migration Plan

## **Executive Summary**

This document outlines a comprehensive plan for migrating the VideoLUT Converter from macOS to iOS and iPadOS platforms. The migration will maintain all existing functionality while leveraging native iOS APIs for enhanced performance, hardware acceleration, and platform-specific features.

**Key Objectives:**
- Preserve all current functionality (video processing, LUT application, real-time preview)
- Implement hardware acceleration using VideoToolbox and Metal
- Create adaptive UI for iPhone and iPad
- Optimize for mobile constraints (battery, memory, storage)
- Integrate with iOS ecosystem (Files app, Photos, Shortcuts)

---

## **1. Project Structure & Architecture Migration**

### **1.1 Target Platform Setup**
- **Primary Target**: iOS 16.0+ (to leverage latest APIs)
- **Secondary Target**: iPadOS 16.0+ (with optimized iPad-specific features)
- **Universal App**: Single codebase supporting iPhone, iPad, and Mac Catalyst
- **Swift Package Manager**: Transition from bundled FFmpeg to SPM dependencies where possible

### **1.2 Framework Transitions**
```swift
// Current → iOS Migration
NSViewController → UIViewController
NSView → UIView
NSButton → UIButton
NSSlider → UISlider
NSTextField → UILabel
NSTextView → UITextView
NSImageView → UIImageView
NSOpenPanel → UIDocumentPickerViewController
NSProgressIndicator → UIProgressView
Storyboard → SwiftUI + UIKit hybrid approach
```

### **1.3 New iOS-Specific Architecture**
- **MVVM Pattern**: Leverage SwiftUI's reactive programming
- **Combine Framework**: For reactive state management
- **Core Data**: For project persistence and recent files
- **CloudKit**: For cross-device project sync
- **Background Processing**: For long export operations

---

## **2. Hardware Acceleration Strategy**

### **2.1 VideoToolbox Integration**
```swift
// Replace FFmpeg hardware acceleration with native iOS APIs
import VideoToolbox
import CoreMedia
import Metal
import MetalKit

// Hardware-accelerated video processing pipeline
class VideoProcessor {
    private let metalDevice: MTLDevice
    private let ciContext: CIContext
    private let videoComposition: AVVideoComposition
    
    // LUT processing using Metal shaders
    func applyLUT(to video: AVAsset, lut: CIFilter) -> AVAsset
    
    // Real-time preview using Metal
    func generatePreviewFrame(at time: CMTime) -> UIImage
}
```

### **2.2 Core Image LUT Processing**
```swift
// Replace FFmpeg LUT filters with Core Image
import CoreImage

class LUTProcessor {
    func createLUTFilter(from cubeFile: URL) -> CIFilter
    func blendLUTs(primary: CIFilter, secondary: CIFilter, opacity: Float) -> CIFilter
    func applyWhiteBalance(temperature: Float) -> CIFilter
}
```

### **2.3 Metal Performance Shaders**
```swift
// For advanced color processing
import MetalPerformanceShaders

class MetalLUTProcessor {
    func processVideoFrame(texture: MTLTexture, lut: MTLTexture) -> MTLTexture
    func realTimePreview(inputTexture: MTLTexture) -> MTLTexture
}
```

---

## **3. User Interface Adaptation**

### **3.1 SwiftUI-First Approach**
```swift
// Main app structure
@main
struct VideoLUTConverterApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// Adaptive UI for iPhone/iPad
struct ContentView: View {
    @StateObject private var projectState = ProjectState()
    
    var body: some View {
        NavigationSplitView {
            // iPhone: Bottom tab bar
            // iPad: Sidebar with project library
            ProjectLibraryView()
        } detail: {
            // Main editing interface
            VideoEditorView()
        }
    }
}
```

### **3.2 iPhone-Optimized Interface**
```swift
// Vertical layout optimized for mobile
struct iPhoneVideoEditorView: View {
    var body: some View {
        VStack {
            // Preview window (full width)
            VideoPreviewView()
                .aspectRatio(16/9, contentMode: .fit)
            
            // Scrollable controls
            ScrollView {
                VStack(spacing: 20) {
                    FileSelectionSection()
                    LUTControlsSection()
                    ExportSection()
                }
            }
        }
    }
}
```

### **3.3 iPad-Optimized Interface**
```swift
// Split view interface leveraging iPad's screen real estate
struct iPadVideoEditorView: View {
    var body: some View {
        HSplitView {
            // Left panel - Controls
            VStack {
                FileSelectionView()
                LUTControlsView()
                ExportControlsView()
            }
            .frame(minWidth: 320, maxWidth: 400)
            
            // Right panel - Preview
            VideoPreviewView()
                .toolbar {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        PlaybackControlsView()
                    }
                }
        }
    }
}
```

---

## **4. File Management & Document Handling**

### **4.1 Document-Based Architecture**
```swift
// Replace NSOpenPanel with modern iOS file handling
import UniformTypeIdentifiers

class DocumentManager: ObservableObject {
    func importVideo() async -> [URL]
    func importLUT() async -> URL?
    func exportVideo(to url: URL) async -> Bool
    
    // Support for Files app integration
    func presentDocumentPicker(for types: [UTType]) -> UIDocumentPickerViewController
}

// Define custom UTTypes for LUT files
extension UTType {
    static let cubeLUT = UTType(filenameExtension: "cube")!
}
```

### **4.2 iCloud Drive Integration**
```swift
// Seamless cloud storage
class CloudManager {
    func saveProjectToCloud(_ project: Project) async throws
    func loadProjectsFromCloud() async throws -> [Project]
    func syncWithCloud() async throws
}
```

### **4.3 Enhanced Drag & Drop**
```swift
// iPad drag and drop support
struct VideoDropView: View {
    var body: some View {
        Rectangle()
            .onDrop(of: [.movie, .quickTimeMovie], isTargeted: $isTargeted) { providers in
                // Handle video file drops
                return handleVideoDrop(providers)
            }
    }
}
```

---

## **5. Video Processing Pipeline**

### **5.1 AVFoundation-Based Processing**
```swift
// Replace FFmpeg with native iOS video processing
import AVFoundation

class VideoProcessor {
    private let assetReader: AVAssetReader
    private let assetWriter: AVAssetWriter
    private let videoComposition: AVVideoComposition
    
    func exportVideo(
        asset: AVAsset,
        luts: [CIFilter],
        outputURL: URL,
        progress: @escaping (Double) -> Void
    ) async throws -> Bool {
        // Hardware-accelerated export using VideoToolbox
    }
}
```

### **5.2 Real-Time Preview System**
```swift
// Metal-based real-time preview
class PreviewRenderer: NSObject, MTKViewDelegate {
    private let metalDevice: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let lutTexture: MTLTexture
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Update preview resolution
    }
    
    func draw(in view: MTKView) {
        // Render current frame with LUT applied
    }
}
```

### **5.3 Background Processing**
```swift
// Background export support
class BackgroundExportManager {
    func scheduleExport(project: Project) async throws -> BGTaskRequest
    func handleBackgroundExport(task: BGAppRefreshTask) async
}
```

---

## **6. Performance Optimizations**

### **6.1 Memory Management**
```swift
// Efficient memory usage for mobile devices
class MemoryManager {
    private let memoryPressureSource: DispatchSourceMemoryPressure
    
    func optimizeForMemoryPressure() {
        // Reduce preview quality
        // Clear cached frames
        // Pause background operations
    }
}
```

### **6.2 Battery Optimization**
```swift
// Battery-aware processing
class BatteryAwareProcessor {
    func adjustProcessingQuality(for batteryLevel: Float) -> ProcessingQuality
    func shouldDeferExport() -> Bool
}
```

### **6.3 Thermal Management**
```swift
// Prevent overheating during intensive processing
class ThermalManager {
    func monitorThermalState() -> ProcessingThermalState
    func throttleProcessing(for state: ProcessingThermalState)
}
```

---

## **7. iOS-Specific Features**

### **7.1 Photos Framework Integration**
```swift
// Direct access to photo library
import Photos

class PhotosManager {
    func importFromPhotos() async -> [AVAsset]
    func exportToPhotos(url: URL) async throws
    func createAlbum(named: String) async throws
}
```

### **7.2 Shortcuts Integration**
```swift
// Siri Shortcuts for common workflows
import Intents

class ShortcutsManager {
    func donateApplyLUTIntent(videoName: String, lutName: String)
    func createCustomShortcuts() -> [INShortcut]
}
```

### **7.3 ShareSheet Integration**
```swift
// Enhanced sharing capabilities
struct ShareSheet: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let activityVC = UIActivityViewController(
            activityItems: [videoURL],
            applicationActivities: [CustomExportActivity()]
        )
        return activityVC
    }
}
```

---

## **8. Data Management & Persistence**

### **8.1 Core Data Stack**
```swift
// Project persistence
import CoreData

class PersistenceController {
    lazy var container: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "VideoLUTConverter")
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Core Data error: \(error)")
            }
        }
        return container
    }()
}
```

### **8.2 Enhanced ProjectState**
```swift
// Observable project state with persistence
@MainActor
class ProjectState: ObservableObject {
    @Published var currentProject: Project?
    @Published var recentProjects: [Project] = []
    @Published var exportProgress: Double = 0.0
    @Published var isExporting: Bool = false
    
    // Background task support
    @Published var backgroundExportProgress: [String: Double] = [:]
    
    func saveProject() async throws
    func loadProject(id: UUID) async throws
    func duplicateProject(_ project: Project) async throws
}
```

---

## **9. Testing & Quality Assurance**

### **9.1 Unit Tests**
```swift
// Comprehensive test coverage
class VideoProcessingTests: XCTestCase {
    func testLUTApplication() async throws
    func testVideoExport() async throws
    func testMemoryManagement() async throws
}
```

### **9.2 UI Tests**
```swift
// Automated UI testing
class VideoLUTConverterUITests: XCTestCase {
    func testCompleteWorkflow() throws
    func testFileImport() throws
    func testExportProcess() throws
}
```

### **9.3 Performance Tests**
```swift
// Performance benchmarking
class PerformanceTests: XCTestCase {
    func testExportSpeed() throws
    func testMemoryUsage() throws
    func testBatteryUsage() throws
}
```

---

## **10. Migration Strategy**

### **10.1 Phase 1: Foundation (2-3 weeks)**
- Set up iOS project structure
- Implement basic UI with SwiftUI
- Create ProjectState management
- Basic file import/export

### **10.2 Phase 2: Core Processing (3-4 weeks)**
- Implement VideoToolbox integration
- Core Image LUT processing
- Real-time preview system
- Hardware acceleration

### **10.3 Phase 3: Advanced Features (2-3 weeks)**
- Background processing
- iCloud integration
- Advanced UI polish
- Performance optimizations

### **10.4 Phase 4: Testing & Optimization (1-2 weeks)**
- Comprehensive testing
- Performance tuning
- Bug fixes and polish

---

## **11. Key Considerations**

### **11.1 Platform Differences**
- **Storage**: Limited compared to desktop - implement smart caching
- **Processing Power**: Variable - adaptive quality settings
- **Battery Life**: Critical consideration - power-efficient algorithms
- **Screen Size**: Adaptive UI for various device sizes

### **11.2 iOS App Store Requirements**
- **Privacy**: Implement App Tracking Transparency
- **Background Processing**: Proper background task management
- **File Access**: Secure file handling with proper permissions
- **Performance**: 60fps UI, efficient memory usage

### **11.3 User Experience Enhancements**
- **Gestures**: Pinch-to-zoom on preview, swipe gestures
- **Haptics**: Tactile feedback for interactions
- **Accessibility**: Full VoiceOver support, Dynamic Type
- **Localization**: Multi-language support

---

## **12. Implementation Priority**

### **High Priority**
1. Video import/export functionality
2. LUT processing with hardware acceleration
3. Real-time preview
4. Basic UI for iPhone/iPad

### **Medium Priority**
1. Background processing
2. iCloud sync
3. Advanced UI features
4. Performance optimizations

### **Low Priority**
1. Shortcuts integration
2. Advanced sharing features
3. Custom LUT creation tools
4. Pro features (multiple LUT layers, etc.)

---

## **13. Current Architecture Analysis**

### **13.1 Existing Components to Migrate**

#### **ViewController.swift → iOS ViewControllers**
- Current: NSViewController with 597 lines
- Migration: Split into multiple SwiftUI views and UIKit controllers
- Key functions: Video loading, LUT selection, preview generation, export

#### **FFmpegManager.swift → Native iOS Processing**
- Current: FFmpeg binary management with architecture detection
- Migration: Replace with VideoToolbox and AVFoundation
- Key functions: Video processing, format conversion, hardware acceleration

#### **ProjectState.swift → Enhanced State Management**
- Current: Basic ObservableObject with video/LUT management
- Migration: Expand with Core Data persistence and iCloud sync
- Key functions: Project management, progress tracking, validation

#### **FilterBuilder.swift → Core Image Integration**
- Current: FFmpeg filter string generation
- Migration: Core Image filter pipeline
- Key functions: LUT application, white balance, opacity blending

#### **DragDropView.swift → iOS File Handling**
- Current: NSView-based drag and drop
- Migration: UIDocumentPickerViewController and drag/drop API
- Key functions: File import, validation, user feedback

### **13.2 Key Challenges**
1. **FFmpeg Replacement**: Transition from command-line tool to native APIs
2. **File System Access**: iOS sandbox limitations vs macOS file access
3. **Background Processing**: iOS background task limitations
4. **Memory Constraints**: Mobile device limitations vs desktop resources
5. **UI Paradigm**: Desktop mouse/keyboard vs touch interface

### **13.3 Opportunities**
1. **Hardware Acceleration**: Better GPU utilization with Metal
2. **Integration**: Native iOS ecosystem integration
3. **Performance**: Optimized for mobile processors
4. **User Experience**: Touch-optimized interface
5. **Portability**: Work anywhere with mobile devices

---

## **14. Technical Implementation Details**

### **14.1 Video Processing Pipeline Replacement**

#### **Current FFmpeg Pipeline**
```swift
// Current approach using FFmpeg command line
let arguments = [
    "-i", videoPath,
    "-vf", "lut3d='\(lutPath)'",
    "-c:v", "h264_videotoolbox",
    outputPath
]
```

#### **New iOS Pipeline**
```swift
// New approach using AVFoundation and Core Image
class VideoProcessor {
    func processVideo(
        asset: AVAsset,
        lutFilter: CIFilter,
        outputURL: URL
    ) async throws {
        let composition = AVVideoComposition(
            asset: asset,
            applyingCIFiltersWithHandler: { request in
                let filtered = lutFilter.apply(to: request.sourceImage)
                request.finish(with: filtered, context: nil)
            }
        )
        
        let export = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetHighestQuality
        )
        export?.videoComposition = composition
        export?.outputURL = outputURL
        
        await export?.export()
    }
}
```

### **14.2 LUT Processing Implementation**
```swift
// Core Image LUT implementation
class LUTProcessor {
    func loadLUT(from url: URL) throws -> CIFilter {
        let data = try Data(contentsOf: url)
        let lutImage = try createLUTImage(from: data)
        
        let filter = CIFilter(name: "CIColorCube")!
        filter.setValue(lutImage, forKey: "inputCubeData")
        filter.setValue(64, forKey: "inputCubeDimension")
        
        return filter
    }
    
    private func createLUTImage(from data: Data) throws -> CIImage {
        // Parse .cube file format and create CIImage
        // Implementation details for cube file parsing
    }
}
```

### **14.3 Real-Time Preview System**
```swift
// Metal-based real-time preview
class PreviewRenderer {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let library: MTLLibrary
    
    func renderFrame(
        inputTexture: MTLTexture,
        lutTexture: MTLTexture,
        outputTexture: MTLTexture
    ) {
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let encoder = commandBuffer.makeComputeCommandEncoder()!
        
        encoder.setComputePipelineState(lutPipelineState)
        encoder.setTexture(inputTexture, index: 0)
        encoder.setTexture(lutTexture, index: 1)
        encoder.setTexture(outputTexture, index: 2)
        
        let threadsPerGrid = MTLSize(
            width: inputTexture.width,
            height: inputTexture.height,
            depth: 1
        )
        
        encoder.dispatchThreads(
            threadsPerGrid,
            threadsPerThreadgroup: threadsPerThreadgroup
        )
        
        encoder.endEncoding()
        commandBuffer.commit()
    }
}
```

---

## **15. Conclusion**

This migration plan provides a comprehensive roadmap for transforming the VideoLUT Converter from a macOS desktop application to a modern iOS/iPadOS universal app. The plan prioritizes:

1. **Functionality Preservation**: All existing features will be maintained
2. **Performance Enhancement**: Native iOS APIs will provide better performance
3. **User Experience**: Touch-optimized interface for mobile devices
4. **Platform Integration**: Deep integration with iOS ecosystem
5. **Future-Proofing**: Modern architecture supporting future enhancements

The estimated timeline of 8-12 weeks provides a realistic schedule for implementing this migration while maintaining high code quality and thorough testing.

**Success Metrics:**
- Feature parity with macOS version
- 60fps real-time preview performance
- Sub-30 second export times for typical videos
- 4.5+ App Store rating
- Successful App Store review process

This document serves as the definitive guide for the iOS/iPadOS migration project and should be referenced throughout the development process.
