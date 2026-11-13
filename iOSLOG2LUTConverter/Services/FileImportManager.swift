import Foundation
import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

// MARK: - iOS File Import Manager (Replaces macOS Drag & Drop)
@MainActor
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
    @Published private(set) var lastImportedURL: URL?
    
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
            UTType(filenameExtension: "cube") ?? .data
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
    /// Copy imports into app-owned storage so later preview/export does not rely on a picker grant.
    func importVideo(from url: URL) {
        lastImportStatus = .importing
        lastImportedURL = nil
        Task {
            do {
                let importedURL = try await Task.detached(priority: .userInitiated) {
                    try Self.copyImportedFile(from: url)
                }.value
                lastImportedURL = importedURL
                lastImportStatus = .success("Video imported: \(url.lastPathComponent)")
            } catch {
                lastImportStatus = .error("Failed to import video: \(error.localizedDescription)")
            }
        }
    }

    func importVideoFromPhotos(results: [PHPickerResult]) {
        guard let result = results.first else { return }
        lastImportStatus = .importing
        lastImportedURL = nil
        result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] url, error in
            // NSItemProvider deletes this URL as soon as its completion handler returns.
            // Perform the copy here, before hopping to the main actor.
            let imported: Result<URL, Error>
            if let error {
                imported = .failure(error)
            } else if let url {
                imported = Result { try Self.copyImportedFile(from: url) }
            } else {
                imported = .failure(CocoaError(.fileReadUnknown))
            }
            Task { @MainActor in
                switch imported {
                case .success(let url):
                    self?.lastImportedURL = url
                    self?.lastImportStatus = .success("Video imported from Photos")
                case .failure(let error):
                    self?.lastImportStatus = .error("Failed to import video: \(error.localizedDescription)")
                }
            }
        }
    }

    func importLUT(from url: URL, isSecondary: Bool = false) {
        lastImportStatus = .importing
        lastImportedURL = nil
        Task {
            do {
                let importedURL = try await Task.detached(priority: .userInitiated) {
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    _ = try LUTParsingUtils.parseLUTFile(url)
                    return try Self.copyImportedFile(from: url)
                }.value
                lastImportedURL = importedURL
                let lutType = isSecondary ? "Secondary LUT" : "Primary LUT"
                lastImportStatus = .success("\(lutType) imported: \(url.lastPathComponent)")
            } catch {
                lastImportStatus = .error("Failed to import LUT: \(error.localizedDescription)")
            }
        }
    }

    nonisolated static func copyImportedFile(from source: URL, to directory: URL? = nil) throws -> URL {
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }
        // startAccessing returning false is normal for files already in the app sandbox.
        let properties = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard source.isFileURL, properties.isRegularFile == true, (properties.fileSize ?? 0) > 0,
              FileManager.default.isReadableFile(atPath: source.path) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let destinationDirectory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ImportedFiles", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let destination = destinationDirectory.appendingPathComponent("\(UUID().uuidString)-\(source.lastPathComponent)")
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            return destination
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    func resetStatus() {
        lastImportStatus = .idle
        lastImportedURL = nil
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