import Foundation
import SwiftUI
import UIKit

// MARK: - Project Management Service
@MainActor
class ProjectManager: ObservableObject {
    
    // MARK: - Published Properties
    @Published var savedProjects: [SavedProject] = []
    @Published var projectTemplates: [ProjectTemplate] = []
    @Published var recentProjects: [RecentProjectItem] = []
    @Published var favoriteProjects: [UUID] = []
    @Published var isLoading = false
    @Published var lastError: String?
    
    // MARK: - Constants
    private let maxRecentProjects = 10
    private let userDefaultsKey = "ProjectManager"
    private let storageDirectory: URL
    private let userDefaults: UserDefaults
    
    // MARK: - Computed Properties
    var projectsDirectory: URL {
        storageDirectory
    }
    
    var favoriteProjectsList: [SavedProject] {
        return savedProjects.filter { favoriteProjects.contains($0.id) }
    }
    
    // MARK: - Initialization
    init(projectsDirectory: URL? = nil, userDefaults: UserDefaults = .standard) {
        self.storageDirectory = projectsDirectory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SavedProjects", isDirectory: true)
        self.userDefaults = userDefaults
        setupProjectsDirectory()
        loadProjectTemplates()
        loadSavedProjects()
        loadRecentProjects()
        loadFavoriteProjects()
    }
    
    // MARK: - Project Templates
    private func loadProjectTemplates() {
        projectTemplates = [
            // Apple Log Templates
            ProjectTemplate(
                name: "iPhone Log to Rec709",
                description: "Convert Apple Log video to standard Rec709 color space",
                category: .apple,
                icon: "iphone",
                primaryLUTName: "AppleLogToRec709-v1.0",
                secondaryLUTName: nil,
                settings: ProjectSettings(
                    primaryLUTOpacity: 1.0,
                    secondaryLUTOpacity: 0.8,
                    whiteBalanceValue: 0.0,
                    exportQuality: .high,
                    useGPUProcessing: true,
                    shouldOptimizeForBattery: false
                )
            ),
            
            ProjectTemplate(
                name: "iPhone Log to Cinematic",
                description: "Transform iPhone footage with cinematic color grading",
                category: .apple,
                icon: "camera.fill",
                primaryLUTName: "AppleLogToRec709-v1.0",
                secondaryLUTName: "BLADE RUNNER 2049 - STREET",
                settings: ProjectSettings(
                    primaryLUTOpacity: 1.0,
                    secondaryLUTOpacity: 0.7,
                    whiteBalanceValue: -2.0,
                    exportQuality: .high,
                    useGPUProcessing: true,
                    shouldOptimizeForBattery: false
                )
            ),
            
            // Sony S-Log Templates
            ProjectTemplate(
                name: "Sony S-Log3 to Rec709",
                description: "Standard conversion from Sony S-Log3 to Rec709",
                category: .sony,
                icon: "video.fill",
                primaryLUTName: "1_SGamut3CineSLog3_To_LC-709",
                secondaryLUTName: nil,
                settings: ProjectSettings(
                    primaryLUTOpacity: 1.0,
                    secondaryLUTOpacity: 0.8,
                    whiteBalanceValue: 0.0,
                    exportQuality: .high,
                    useGPUProcessing: true,
                    shouldOptimizeForBattery: false
                )
            ),
            
            ProjectTemplate(
                name: "Sony S-Log3 Cinematic",
                description: "Sony S-Log3 with cinematic color grading",
                category: .sony,
                icon: "film.fill",
                primaryLUTName: "1_SGamut3CineSLog3_To_LC-709",
                secondaryLUTName: "JOKER",
                settings: ProjectSettings(
                    primaryLUTOpacity: 1.0,
                    secondaryLUTOpacity: 0.6,
                    whiteBalanceValue: -1.0,
                    exportQuality: .high,
                    useGPUProcessing: true,
                    shouldOptimizeForBattery: false
                )
            ),
            
            ProjectTemplate(
                name: "Sony S-Log2 to Rec709",
                description: "Convert Sony S-Log2 footage to standard Rec709",
                category: .sony,
                icon: "video.circle.fill",
                primaryLUTName: "From_SLog2SGumut_To_LC-709_",
                secondaryLUTName: nil,
                settings: ProjectSettings(
                    primaryLUTOpacity: 1.0,
                    secondaryLUTOpacity: 0.8,
                    whiteBalanceValue: 0.0,
                    exportQuality: .high,
                    useGPUProcessing: true,
                    shouldOptimizeForBattery: false
                )
            ),
            
            // Creative Templates
            ProjectTemplate(
                name: "Film Emulation - Kodachrome",
                description: "Classic Kodachrome film look",
                category: .creative,
                icon: "camera.vintage",
                primaryLUTName: "AppleLogToRec709-v1.0",
                secondaryLUTName: "KODACHROME",
                settings: ProjectSettings(
                    primaryLUTOpacity: 1.0,
                    secondaryLUTOpacity: 0.8,
                    whiteBalanceValue: 1.0,
                    exportQuality: .high,
                    useGPUProcessing: true,
                    shouldOptimizeForBattery: false
                )
            ),
            
            ProjectTemplate(
                name: "TV Series - Breaking Bad",
                description: "Recreate the iconic Breaking Bad color palette",
                category: .tvSeries,
                icon: "tv.fill",
                primaryLUTName: "AppleLogToRec709-v1.0",
                secondaryLUTName: "BREAKING BAD",
                settings: ProjectSettings(
                    primaryLUTOpacity: 1.0,
                    secondaryLUTOpacity: 0.7,
                    whiteBalanceValue: -1.5,
                    exportQuality: .high,
                    useGPUProcessing: true,
                    shouldOptimizeForBattery: false
                )
            ),
            
            ProjectTemplate(
                name: "Movie - Blade Runner 2049",
                description: "Cyberpunk aesthetic with orange and teal",
                category: .movie,
                icon: "building.2.fill",
                primaryLUTName: "AppleLogToRec709-v1.0",
                secondaryLUTName: "BLADE RUNNER 2049 - HAZE",
                settings: ProjectSettings(
                    primaryLUTOpacity: 1.0,
                    secondaryLUTOpacity: 0.8,
                    whiteBalanceValue: -2.0,
                    exportQuality: .high,
                    useGPUProcessing: true,
                    shouldOptimizeForBattery: false
                )
            ),
            
            ProjectTemplate(
                name: "Nature Documentary",
                description: "Natural, vibrant colors for nature footage",
                category: .documentary,
                icon: "leaf.fill",
                primaryLUTName: "AppleLogToRec709-v1.0",
                secondaryLUTName: "lut_nature_2",
                settings: ProjectSettings(
                    primaryLUTOpacity: 1.0,
                    secondaryLUTOpacity: 0.6,
                    whiteBalanceValue: 0.5,
                    exportQuality: .high,
                    useGPUProcessing: true,
                    shouldOptimizeForBattery: false
                )
            ),
            
            ProjectTemplate(
                name: "Urban Style",
                description: "Modern urban aesthetic with enhanced contrast",
                category: .urban,
                icon: "building.fill",
                primaryLUTName: "AppleLogToRec709-v1.0",
                secondaryLUTName: "lut_urban_2",
                settings: ProjectSettings(
                    primaryLUTOpacity: 1.0,
                    secondaryLUTOpacity: 0.7,
                    whiteBalanceValue: -0.5,
                    exportQuality: .high,
                    useGPUProcessing: true,
                    shouldOptimizeForBattery: false
                )
            )
        ]
    }
    
    // MARK: - Project Management
    func saveProject(name: String, projectState: ProjectState, lutManager: LUTManager) async -> Bool {
        guard !isLoading else { return false }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            lastError = "Project name cannot be empty"
            return false
        }

        isLoading = true
        lastError = nil
        defer { isLoading = false }
        let projectID = UUID()
        let assetsDirectory = projectsDirectory.appendingPathComponent(projectID.uuidString, isDirectory: true)
        // Snapshot the active project before copying large videos off the main actor.
        let videos = projectState.batchMode ? projectState.batchQueue.map(\.url) : projectState.videoURLs
        let primaryURL = projectState.primaryLUTURL
        let secondaryURL = projectState.secondaryLUTURL
        let primaryName = primaryURL.map { lutManager.selectedPrimaryLUT?.name ?? $0.deletingPathExtension().lastPathComponent }
        let secondaryName = secondaryURL.map { lutManager.selectedSecondaryLUT?.name ?? $0.deletingPathExtension().lastPathComponent }
        let settings = ProjectSettings(
            primaryLUTOpacity: projectState.primaryLUTOpacity,
            secondaryLUTOpacity: projectState.secondLUTOpacity,
            whiteBalanceValue: projectState.whiteBalanceValue,
            exportQuality: projectState.exportQuality,
            useGPUProcessing: projectState.useGPU,
            shouldOptimizeForBattery: projectState.shouldOptimizeForBattery
        )
        // Keep thumbnails small instead of embedding a full-resolution preview in JSON and defaults.
        let thumbnail: Data? = projectState.previewImage.flatMap { image in
            let size = image.size
            let scale = min(1, 320 / max(max(size.width, size.height), 1))
            let thumbnailSize = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: thumbnailSize, format: format)
                .image { _ in image.draw(in: CGRect(origin: .zero, size: thumbnailSize)) }
                .jpegData(compressionQuality: 0.75)
        }

        do {
            try Self.validateSettings(settings)
            let assets = try await Task.detached(priority: .userInitiated) {
                try FileManager.default.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
                let videoNames = try videos.enumerated().map { index, url in
                    try Self.copyAsset(url, to: assetsDirectory, prefix: "video-\(index)")
                }
                let primaryName = try primaryURL.map { try Self.copyAsset($0, to: assetsDirectory, prefix: "primary") }
                let secondaryName = try secondaryURL.map { try Self.copyAsset($0, to: assetsDirectory, prefix: "secondary") }
                return (videoNames, primaryName, secondaryName)
            }.value
            let project = SavedProject(
                id: projectID, name: trimmedName,
                videoURLs: assets.0.map { assetsDirectory.appendingPathComponent($0) },
                primaryLUTName: primaryName, secondaryLUTName: secondaryName,
                settings: settings, previewThumbnail: thumbnail,
                videoFileNames: assets.0, primaryLUTFileName: assets.1, secondaryLUTFileName: assets.2
            )
            let projectURL = projectsDirectory.appendingPathComponent("\(project.id.uuidString).json")
            try JSONEncoder().encode(project).write(to: projectURL, options: .atomic)
            savedProjects.insert(project, at: 0)
            addToRecentProjects(project)
            saveProjectMetadata()
            return true
        } catch {
            try? FileManager.default.removeItem(at: assetsDirectory)
            lastError = "Failed to save project: \(error.localizedDescription)"
            return false
        }
    }

    nonisolated private static func copyAsset(_ source: URL, to directory: URL, prefix: String) throws -> String {
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }
        let properties = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard source.isFileURL, properties.isRegularFile == true, (properties.fileSize ?? 0) > 0,
              FileManager.default.isReadableFile(atPath: source.path) else {
            throw CocoaError(.fileReadNoPermission, userInfo: [NSLocalizedDescriptionKey: "The file \(source.lastPathComponent) is unavailable. Import it again before saving."])
        }
        let name = "\(prefix)-\(source.lastPathComponent)"
        try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent(name))
        return name
    }

    nonisolated private static func validateSettings(_ settings: ProjectSettings) throws {
        guard settings.primaryLUTOpacity.isFinite, (0...1).contains(settings.primaryLUTOpacity),
              settings.secondaryLUTOpacity.isFinite, (0...1).contains(settings.secondaryLUTOpacity),
              settings.whiteBalanceValue.isFinite, (-10...10).contains(settings.whiteBalanceValue) else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "The project's color settings are outside the supported range."])
        }
    }

    private func assetURL(named name: String, projectID: UUID) throws -> URL {
        guard !name.isEmpty, name != ".", name != "..",
              name == URL(fileURLWithPath: name).lastPathComponent else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return projectsDirectory.appendingPathComponent(projectID.uuidString, isDirectory: true).appendingPathComponent(name)
    }

    private func matchingLUT(_ lut: LUTManager.LUT, name: String) -> Bool {
        func normalized(_ value: String) -> String {
            let lower = value.lowercased()
            return lower.hasSuffix(".cube") ? String(lower.dropLast(5)) : lower
        }
        return normalized(lut.name) == normalized(name)
    }

    private func restoredLUT(name: String?, fileName: String?, projectID: UUID, isSecondary: Bool, lutManager: LUTManager) throws -> LUTManager.LUT? {
        if let fileName {
            let url = try assetURL(named: fileName, projectID: projectID)
            guard FileManager.default.isReadableFile(atPath: url.path) else {
                throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "The saved LUT \(name ?? fileName) is missing."])
            }
            return LUTManager.LUT(name: name ?? url.deletingPathExtension().lastPathComponent,
                                  displayName: name ?? url.deletingPathExtension().lastPathComponent,
                                  description: "LUT saved with this project", category: .custom,
                                  url: url, isBuiltIn: false, isSecondary: isSecondary)
        }
        guard let name else { return nil }
        let available = (isSecondary ? lutManager.secondaryLUTs : lutManager.primaryLUTs) + lutManager.customLUTs
        guard let lut = available.first(where: { matchingLUT($0, name: name) && $0.isSecondary == isSecondary }) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "The LUT \(name) is unavailable. Import it again to open this project."])
        }
        return lut
    }

    func loadProject(_ project: SavedProject, into projectState: ProjectState, lutManager: LUTManager) async -> Bool {
        guard !isLoading, !projectState.isExporting, !projectState.isBatchProcessing else {
            lastError = "Wait for the current operation to finish before opening a project."
            return false
        }
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        do {
            let videos = try project.videoFileNames?.map { try assetURL(named: $0, projectID: project.id) } ?? project.videoURLs
            for url in videos {
                let properties = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard url.isFileURL, properties?.isRegularFile == true, (properties?.fileSize ?? 0) > 0,
                      FileManager.default.isReadableFile(atPath: url.path) else {
                    throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "The video \(url.lastPathComponent) is unavailable or empty. Import it again to open this project."])
                }
            }
            let primary = try restoredLUT(name: project.primaryLUTName, fileName: project.primaryLUTFileName, projectID: project.id, isSecondary: false, lutManager: lutManager)
            let secondary = try restoredLUT(name: project.secondaryLUTName, fileName: project.secondaryLUTFileName, projectID: project.id, isSecondary: true, lutManager: lutManager)
            try Self.validateSettings(project.settings)
            let lutURLs = [primary?.url, secondary?.url].compactMap { $0 }
            try await Task.detached(priority: .userInitiated) {
                for url in lutURLs {
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    _ = try LUTParsingUtils.parseLUTFile(url)
                }
            }.value
            guard !projectState.isExporting, !projectState.isBatchProcessing else {
                throw CocoaError(.fileReadUnknown, userInfo: [NSLocalizedDescriptionKey: "Wait for the current export to finish before opening a project."])
            }
            // Validate first: a missing asset must leave the user's active project intact.
            projectState.primaryLUTOpacity = project.settings.primaryLUTOpacity
            projectState.secondLUTOpacity = project.settings.secondaryLUTOpacity
            projectState.whiteBalanceValue = project.settings.whiteBalanceValue
            projectState.exportQuality = project.settings.exportQuality
            projectState.shouldOptimizeForBattery = project.settings.shouldOptimizeForBattery
            lutManager.selectedPrimaryLUT = primary
            lutManager.selectedSecondaryLUT = secondary
            projectState.setPrimaryLUT(primary?.url)
            projectState.setSecondaryLUT(secondary?.url)
            projectState.replaceProjectVideos(videos)
            addToRecentProjects(project)
            return true
        } catch {
            lastError = "Failed to open project: \(error.localizedDescription)"
            return false
        }
    }

    func applyTemplate(_ template: ProjectTemplate, to projectState: ProjectState, lutManager: LUTManager) async -> Bool {
        guard !isLoading, !projectState.isExporting, !projectState.isBatchProcessing else {
            lastError = "Wait for the current operation to finish before applying a template."
            return false
        }
        lastError = nil
        guard let primary = lutManager.primaryLUTs.first(where: { matchingLUT($0, name: template.primaryLUTName) }),
              template.secondaryLUTName == nil || lutManager.secondaryLUTs.contains(where: { matchingLUT($0, name: template.secondaryLUTName ?? "") }) else {
            lastError = "This template's LUTs are unavailable. Wait for the LUT library to finish loading and try again."
            return false
        }
        let secondary = template.secondaryLUTName.flatMap { name in lutManager.secondaryLUTs.first { matchingLUT($0, name: name) } }
        projectState.primaryLUTOpacity = template.settings.primaryLUTOpacity
        projectState.secondLUTOpacity = template.settings.secondaryLUTOpacity
        projectState.whiteBalanceValue = template.settings.whiteBalanceValue
        projectState.exportQuality = template.settings.exportQuality
        projectState.shouldOptimizeForBattery = template.settings.shouldOptimizeForBattery
        lutManager.selectedPrimaryLUT = primary
        lutManager.selectedSecondaryLUT = secondary
        projectState.setPrimaryLUT(primary.url)
        projectState.setSecondaryLUT(secondary?.url)
        projectState.generatePreview()
        return true
    }

    func deleteProject(_ project: SavedProject, projectState: ProjectState? = nil) async -> Bool {
        guard !isLoading else { return false }
        let assetsDirectory = projectsDirectory.appendingPathComponent(project.id.uuidString, isDirectory: true)
        if let projectState {
            let activeURLs = projectState.videoURLs + projectState.batchQueue.map(\.url)
                + [projectState.primaryLUTURL, projectState.secondaryLUTURL].compactMap { $0 }
            let assetsPath = assetsDirectory.standardizedFileURL.path + "/"
            guard !activeURLs.contains(where: { $0.standardizedFileURL.path.hasPrefix(assetsPath) }) else {
                lastError = "This project is open. Clear the current videos and LUT selections before deleting it."
                return false
            }
        }
        isLoading = true
        lastError = nil
        
        do {
            // Remove from file system
            let projectURL = projectsDirectory.appendingPathComponent("\(project.id.uuidString).json")
            try FileManager.default.removeItem(at: projectURL)
            
            if FileManager.default.fileExists(atPath: assetsDirectory.path) {
                // The project is deleted even if cleanup of an unused media file fails.
                try? FileManager.default.removeItem(at: assetsDirectory)
            }

            // Remove from arrays
            savedProjects.removeAll { $0.id == project.id }
            recentProjects.removeAll { $0.projectId == project.id }
            favoriteProjects.removeAll { $0 == project.id }
            
            // Save metadata
            saveProjectMetadata()
            
            print("✅ Project deleted successfully: \(project.name)")
            isLoading = false
            return true
            
        } catch {
            lastError = "Failed to delete project: \(error.localizedDescription)"
            print("❌ Failed to delete project: \(error)")
            isLoading = false
            return false
        }
    }
    
    func toggleFavorite(_ project: SavedProject) {
        if favoriteProjects.contains(project.id) {
            favoriteProjects.removeAll { $0 == project.id }
        } else {
            favoriteProjects.append(project.id)
        }
        saveFavoriteProjects()
    }
    
    // MARK: - Recent Projects
    private func addToRecentProjects(_ project: SavedProject) {
        let recentItem = RecentProjectItem(
            id: UUID(),
            projectId: project.id,
            name: project.name,
            lastAccessed: Date(),
            thumbnailData: project.previewThumbnail
        )
        
        // Remove if already exists
        recentProjects.removeAll { $0.projectId == project.id }
        
        // Add to beginning
        recentProjects.insert(recentItem, at: 0)
        
        // Keep only max recent projects
        if recentProjects.count > maxRecentProjects {
            recentProjects = Array(recentProjects.prefix(maxRecentProjects))
        }
        
        saveRecentProjects()
    }
    
    // MARK: - Persistence
    private func setupProjectsDirectory() {
        do {
            try FileManager.default.createDirectory(at: projectsDirectory, withIntermediateDirectories: true)
        } catch {
            print("❌ Failed to create projects directory: \(error)")
        }
    }
    
    private func loadSavedProjects() {
        do {
            let projectFiles = try FileManager.default.contentsOfDirectory(at: projectsDirectory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
            
            savedProjects = projectFiles.compactMap { url in
                do {
                    let data = try Data(contentsOf: url)
                    return try JSONDecoder().decode(SavedProject.self, from: data)
                } catch {
                    print("❌ Failed to load project from \(url): \(error)")
                    return nil
                }
            }.sorted { $0.createdAt > $1.createdAt }
            
            print("✅ Loaded \(savedProjects.count) saved projects")
            
        } catch {
            print("❌ Failed to load saved projects: \(error)")
        }
    }
    
    private func loadRecentProjects() {
        if let data = userDefaults.data(forKey: "\(userDefaultsKey)_recent"),
           let projects = try? JSONDecoder().decode([RecentProjectItem].self, from: data) {
            recentProjects = projects
        }
    }
    
    private func saveRecentProjects() {
        if let data = try? JSONEncoder().encode(recentProjects) {
            userDefaults.set(data, forKey: "\(userDefaultsKey)_recent")
        }
    }
    
    private func loadFavoriteProjects() {
        if let data = userDefaults.data(forKey: "\(userDefaultsKey)_favorites"),
           let favorites = try? JSONDecoder().decode([UUID].self, from: data) {
            favoriteProjects = favorites
        }
    }
    
    private func saveFavoriteProjects() {
        if let data = try? JSONEncoder().encode(favoriteProjects) {
            userDefaults.set(data, forKey: "\(userDefaultsKey)_favorites")
        }
    }
    
    private func saveProjectMetadata() {
        saveRecentProjects()
        saveFavoriteProjects()
    }
}

// MARK: - Data Models
struct SavedProject: Identifiable, Codable {
    let id: UUID
    let name: String
    let videoURLs: [URL]
    let primaryLUTName: String?
    let secondaryLUTName: String?
    let settings: ProjectSettings
    let createdAt: Date
    let modifiedAt: Date
    let previewThumbnail: Data?
    // Relative filenames survive app-container relocation. Nil preserves older project files.
    let videoFileNames: [String]?
    let primaryLUTFileName: String?
    let secondaryLUTFileName: String?

    init(id: UUID = UUID(), name: String, videoURLs: [URL], primaryLUTName: String?, secondaryLUTName: String?, settings: ProjectSettings, previewThumbnail: Data? = nil, videoFileNames: [String]? = nil, primaryLUTFileName: String? = nil, secondaryLUTFileName: String? = nil) {
        self.id = id
        self.name = name
        self.videoURLs = videoURLs
        self.primaryLUTName = primaryLUTName
        self.secondaryLUTName = secondaryLUTName
        self.settings = settings
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.previewThumbnail = previewThumbnail
        self.videoFileNames = videoFileNames
        self.primaryLUTFileName = primaryLUTFileName
        self.secondaryLUTFileName = secondaryLUTFileName
    }
}

struct ProjectTemplate: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let category: TemplateCategory
    let icon: String
    let primaryLUTName: String
    let secondaryLUTName: String?
    let settings: ProjectSettings
    
    enum TemplateCategory: String, CaseIterable {
        case apple = "Apple"
        case sony = "Sony"
        case creative = "Creative"
        case tvSeries = "TV Series"
        case movie = "Movies"
        case documentary = "Documentary"
        case urban = "Urban"
        case nature = "Nature"
        
        var icon: String {
            switch self {
            case .apple: return "apple.logo"
            case .sony: return "video.fill"
            case .creative: return "paintbrush.fill"
            case .tvSeries: return "tv.fill"
            case .movie: return "film.fill"
            case .documentary: return "doc.fill"
            case .urban: return "building.fill"
            case .nature: return "leaf.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .apple: return .blue
            case .sony: return .orange
            case .creative: return .pink
            case .tvSeries: return .red
            case .movie: return .purple
            case .documentary: return .green
            case .urban: return .gray
            case .nature: return .mint
            }
        }
    }
}

struct RecentProjectItem: Identifiable, Codable {
    let id: UUID
    let projectId: UUID
    let name: String
    let lastAccessed: Date
    let thumbnailData: Data?
}

// MARK: - Enhanced Project Settings
struct ProjectSettings: Codable {
    let primaryLUTOpacity: Float
    let secondaryLUTOpacity: Float
    let whiteBalanceValue: Float
    let exportQuality: ExportQuality
    let useGPUProcessing: Bool
    let shouldOptimizeForBattery: Bool
    
    init(primaryLUTOpacity: Float = 1.0, secondaryLUTOpacity: Float = 0.8, whiteBalanceValue: Float = 0.0, exportQuality: ExportQuality = .high, useGPUProcessing: Bool = true, shouldOptimizeForBattery: Bool = true) {
        self.primaryLUTOpacity = primaryLUTOpacity
        self.secondaryLUTOpacity = secondaryLUTOpacity
        self.whiteBalanceValue = whiteBalanceValue
        self.exportQuality = exportQuality
        self.useGPUProcessing = useGPUProcessing
        self.shouldOptimizeForBattery = shouldOptimizeForBattery
    }
} 