import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - iOS File Import Manager (Replaces macOS Drag & Drop)
class FileImportManager: ObservableObject {
    
    // MARK: - Published Properties
    @Published var isShowingVideoPicker = false
    @Published var isShowingLUTPicker = false
    @Published var isShowingSecondaryLUTPicker = false
    @Published var lastImportStatus: ImportStatus = .idle
    
    // MARK: - Supported File Types
    enum SupportedVideoTypes {
        static let types: [UTType] = [
            .movie,
            .video,
            .quickTimeMovie,
            .mpeg4Movie,
            UTType(filenameExtension: "mov") ?? .movie,
            UTType(filenameExtension: "mp4") ?? .mpeg4Movie
        ]
    }
    
    enum SupportedLUTTypes {
        static let types: [UTType] = [
            UTType(filenameExtension: "cube") ?? .data,
            UTType(filenameExtension: "3dl") ?? .data
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
        
        // Simulate import process
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.lastImportStatus = .success("Video imported: \(url.lastPathComponent)")
        }
    }
    
    func importLUT(from url: URL, isSecondary: Bool = false) {
        lastImportStatus = .importing
        
        // Simulate import process
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
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