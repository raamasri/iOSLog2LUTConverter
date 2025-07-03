# iOSLog2LUTConverter v0.1

A professional iOS application for applying LUT (Look-Up Table) color grading to videos, migrated from macOS with native iOS optimizations and Apple's design language.

## 🎬 Features

### Core Functionality
- **Video LUT Processing** - Apply professional color grading LUTs to videos
- **Dual LUT Support** - Primary and secondary LUT with opacity blending
- **Multiple Video Formats** - Support for MP4, MOV, and other common formats
- **LUT Format Support** - .cube, .3dl, and other industry-standard LUT formats
- **White Balance Controls** - Professional color temperature adjustment

### iOS-Specific Features
- **Native Document Picker** - iOS-native file import system
- **Core Image Processing** - Hardware-accelerated video processing
- **Adaptive Interface** - Optimized for both iPhone and iPad
- **Background Processing** - Efficient video processing with progress tracking
- **Metal Rendering** - High-performance video preview

### Design & UX
- **Apple Design Language** - Ultrathin materials and glassy textures
- **Prominent Video Preview** - Large, centered video preview window
- **Touch-Optimized Controls** - Native iOS gesture support
- **Dynamic Typography** - Apple's system fonts with proper hierarchy
- **Responsive Layout** - Portrait (iPhone) and landscape (iPad) optimized

## 🏗️ Architecture

### Migration from macOS
This iOS app is a complete migration from a mature macOS VideoLUT Converter, featuring:

- **SwiftUI Interface** - Modern declarative UI replacing NSViewController
- **Core Image Pipeline** - Native iOS video processing replacing FFmpeg
- **Enhanced ProjectState** - iOS-optimized state management with Core Data integration
- **Document-Based Import** - iOS document picker replacing drag & drop

### Technical Stack
- **Swift 5** - Modern Swift with async/await support
- **SwiftUI** - Declarative user interface
- **Core Image** - Hardware-accelerated image processing
- **AVFoundation** - Video handling and export
- **Metal** - High-performance graphics rendering
- **Combine** - Reactive programming for state management

## 📱 Platform Support

- **iOS 18.5+** - Latest iOS features and optimizations
- **Universal Binary** - Native support for ARM64 and x86_64
- **iPhone & iPad** - Responsive design for all screen sizes
- **iOS Simulator** - Full simulator support for development

## 🚀 Getting Started

### Requirements
- Xcode 16+
- iOS 18.5+ deployment target
- macOS development machine

### Building
1. Clone the repository
2. Open `iOSLOG2LUTConverter.xcodeproj` in Xcode
3. Select your target device or simulator
4. Build and run (⌘+R)

### Usage
1. **Import Videos** - Tap "Import Videos" to select video files
2. **Add LUTs** - Import primary and optional secondary LUT files
3. **Adjust Settings** - Configure LUT opacity and white balance
4. **Process Videos** - Export your color-graded videos

## 📂 Project Structure

```
iOSLOG2LUTConverter/
├── Models/
│   └── ProjectState.swift          # Enhanced state management
├── Views/
│   ├── ContentView.swift           # Main SwiftUI interface
│   └── VideoPreviewView.swift      # Prominent video preview
├── Services/
│   ├── FileImportManager.swift     # iOS document picker
│   ├── LUTProcessor.swift          # Core Image LUT processing
│   └── VideoProcessor.swift        # Video export pipeline
└── Supporting Files/
    ├── Info.plist                  # App configuration
    └── Assets.xcassets             # App icons and images
```

## 🎯 Version 0.1 Features

This initial release includes:

- ✅ Complete iOS migration from macOS codebase
- ✅ Apple-like SwiftUI interface with ultrathin materials
- ✅ Prominent video preview window
- ✅ Native iOS file import system
- ✅ Core Image-based LUT processing
- ✅ Dual LUT support with opacity controls
- ✅ White balance adjustment
- ✅ Universal binary build support

## 🔮 Future Roadmap

- Real-time video preview with LUT applied
- Batch processing for multiple videos
- Custom LUT creation tools
- iCloud integration for LUT library
- Apple Pencil support for iPad
- Shortcuts app integration

## 📄 License

Professional video processing application for iOS.

## 🤝 Contributing

This project represents a complete migration from macOS to iOS, maintaining professional-grade video processing capabilities while embracing iOS design principles and performance optimizations.

---

**Built with ❤️ for iOS using Apple's latest technologies** 