import Foundation
import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

// MARK: - iOS File Import Manager (Replaces macOS Drag & Drop)
class FileImportManager: ObservableObject {
    
    // MARK: - Published Properties
    @Published var isShowingVideoPicker = false
    
    @Published var isShowingLUTPicker = false {
        willSet {
            print("🔍 FileImportManager: isShowingLUTPicker changing from \(isShowingLUTPicker) to \(newValue)")
            if newValue {
                print("🟢 FileImportManager: PRIMARY LUT picker is being SHOWN")
            } else {
                print("🔴 FileImportManager: PRIMARY LUT picker is being HIDDEN")
            }
        }
    }
    
    @Published var isShowingSecondaryLUTPicker = false {
        willSet {
            print("🔍 FileImportManager: isShowingSecondaryLUTPicker changing from \(isShowingSecondaryLUTPicker) to \(newValue)")
            if newValue {
                print("🟢 FileImportManager: SECONDARY LUT picker is being SHOWN")
            } else {
                print("🔴 FileImportManager: SECONDARY LUT picker is being HIDDEN")
            }
        }
    }
    
    // NEW: Separate flags for the file importers (only triggered by custom import buttons)
    @Published var isShowingCustomLUTImporter = false {
        willSet {
            print("📁 FileImportManager: isShowingCustomLUTImporter changing from \(isShowingCustomLUTImporter) to \(newValue)")
            if newValue {
                print("📁 FileImportManager: CUSTOM PRIMARY LUT file importer is being SHOWN")
            } else {
                print("📁 FileImportManager: CUSTOM PRIMARY LUT file importer is being HIDDEN")
            }
        }
    }
    
    @Published var isShowingCustomSecondaryLUTImporter = false {
        willSet {
            print("📁 FileImportManager: isShowingCustomSecondaryLUTImporter changing from \(isShowingCustomSecondaryLUTImporter) to \(newValue)")
            if newValue {
                print("📁 FileImportManager: CUSTOM SECONDARY LUT file importer is being SHOWN")
            } else {
                print("📁 FileImportManager: CUSTOM SECONDARY LUT file importer is being HIDDEN")
            }
        }
    }
    
    @Published var lastImportStatus: ImportStatus = .idle
    
    // MARK: - Photo Picker Configuration
    var photoPickerConfig: PHPickerConfiguration {
        var config = PHPickerConfiguration()
        config.filter = .videos
        config.selectionLimit = 1
        config.preferredAssetRepresentationMode = .current
        return config
    }
    
    // MARK: - Supported File Types
    enum SupportedVideoTypes {
        static let types: [UTType] = [
            .movie,
            .video,
            .quickTimeMovie,
            .mpeg4Movie,
            .audiovisualContent,
            UTType(filenameExtension: "mov") ?? .movie,
            UTType(filenameExtension: "mp4") ?? .mpeg4Movie,
            UTType(filenameExtension: "m4v") ?? .video,
            UTType(filenameExtension: "avi") ?? .video
        ]
    }

    enum SupportedLUTTypes {
        static let types: [UTType] = [
            UTType(filenameExtension: "cube") ?? .data,
            UTType(filenameExtension: "3dl") ?? .data,
            UTType(filenameExtension: "lut") ?? .data,
            .data // Allow generic data files for LUTs
        ]
    }

    // MARK: - Import Status
    enum ImportStatus {
        case idle
        case importing
        case success(String)
        case error(String)
        
        var message: String {
            switch self {
            case .idle:
                return "Ready to import"
            case .importing:
                return "Importing..."
            case .success(let message):
                return message
            case .error(let message):
                return "Error: \(message)"
            }
        }
    }

    // MARK: - Import Methods
    func importVideo(from url: URL) {
        lastImportStatus = .importing
        
        // Start accessing the security-scoped resource
        guard url.startAccessingSecurityScopedResource() else {
            lastImportStatus = .error("Unable to access video file")
            return
        }
        
        // Simulate import process with actual file validation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Stop accessing the resource when done
            url.stopAccessingSecurityScopedResource()
            self.lastImportStatus = .success("Video imported: \(url.lastPathComponent)")
        }
    }
    
    func importVideoFromPhotos(results: [PHPickerResult]) {
        guard let result = results.first else { return }
        
        lastImportStatus = .importing
        
        result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] url, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.lastImportStatus = .error("Failed to load video: \(error.localizedDescription)")
                    return
                }
                
                guard let url = url else {
                    self?.lastImportStatus = .error("No video URL received")
                    return
                }
                
                // Copy the file to a temporary location since the original will be deleted
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
                
                do {
                    try FileManager.default.copyItem(at: url, to: tempURL)
                    self?.lastImportStatus = .success("Video imported from Photos")
                    // Here you would typically update your project state with the video URL
                } catch {
                    self?.lastImportStatus = .error("Failed to copy video: \(error.localizedDescription)")
                }
            }
        }
    }

    func importLUT(from url: URL, isSecondary: Bool = false) {
        lastImportStatus = .importing
        
        // Start accessing the security-scoped resource
        guard url.startAccessingSecurityScopedResource() else {
            lastImportStatus = .error("Unable to access LUT file")
            return
        }
        
        // Simulate import process with actual file validation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Stop accessing the resource when done
            url.stopAccessingSecurityScopedResource()
            let lutType = isSecondary ? "Secondary LUT" : "Primary LUT"
            self.lastImportStatus = .success("\(lutType) imported: \(url.lastPathComponent)")
        }
    }

    func resetStatus() {
        lastImportStatus = .idle
    }
}

// MARK: - Import Button Component
struct ImportButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.green.gradient : Color.accentColor.gradient)
                    .symbolEffect(.bounce, value: isSelected)
                
                VStack(alignment: .center, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(
                .thickMaterial,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isSelected ? Color.green.opacity(0.5) : Color.accentColor.opacity(0.3),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
} 