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
    private let projectsDirectoryName = "SavedProjects"
    private let userDefaultsKey = "ProjectManager"
    
    // MARK: - Computed Properties
    var projectsDirectory: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent(projectsDirectoryName)
    }
    
    var favoriteProjectsList: [SavedProject] {
        return savedProjects.filter { favoriteProjects.contains($0.id) }
    }
    
    // MARK: - Initialization
    init() {
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
                description: "Convert iPhone ProRAW/Log footage to standard Rec709 color space",
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
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastError = "Project name cannot be empty"
            return false
        }
        
        isLoading = true
        lastError = nil
        
        do {
            let project = SavedProject(
                name: name,
                videoURLs: projectState.videoURLs,
                primaryLUTName: lutManager.selectedPrimaryLUT?.name,
                secondaryLUTName: lutManager.selectedSecondaryLUT?.name,
                settings: ProjectSettings(
                    primaryLUTOpacity: projectState.primaryLUTOpacity,
                    secondaryLUTOpacity: projectState.secondLUTOpacity,
                    whiteBalanceValue: projectState.whiteBalanceValue,
                    exportQuality: projectState.exportQuality,
                    useGPUProcessing: projectState.useGPU,
                    shouldOptimizeForBattery: projectState.shouldOptimizeForBattery
                ),
                previewThumbnail: projectState.previewImage?.pngData()
            )
            
            // Save to file
            let projectURL = projectsDirectory.appendingPathComponent("\(project.id.uuidString).json")
            let data = try JSONEncoder().encode(project)
            try data.write(to: projectURL)
            
            // Add to saved projects
            savedProjects.append(project)
            
            // Add to recent projects
            addToRecentProjects(project)
            
            // Save metadata
            saveProjectMetadata()
            
            print("✅ Project saved successfully: \(name)")
            isLoading = false
            return true
            
        } catch {
            lastError = "Failed to save project: \(error.localizedDescription)"
            print("❌ Failed to save project: \(error)")
            isLoading = false
            return false
        }
    }
    
    func loadProject(_ project: SavedProject, into projectState: ProjectState, lutManager: LUTManager) async -> Bool {
        isLoading = true
        lastError = nil
        
        do {
            // Load video URLs
            projectState.videoURLs = project.videoURLs
            
            // Load LUTs
            if let primaryLUTName = project.primaryLUTName,
               let primaryLUT = lutManager.primaryLUTs.first(where: { $0.name == primaryLUTName }) {
                lutManager.selectedPrimaryLUT = primaryLUT
                projectState.setPrimaryLUT(primaryLUT.url)
            }
            
            if let secondaryLUTName = project.secondaryLUTName,
               let secondaryLUT = lutManager.secondaryLUTs.first(where: { $0.name == secondaryLUTName }) {
                lutManager.selectedSecondaryLUT = secondaryLUT
                projectState.setSecondaryLUT(secondaryLUT.url)
            }
            
            // Load settings
            projectState.primaryLUTOpacity = project.settings.primaryLUTOpacity
            projectState.secondLUTOpacity = project.settings.secondaryLUTOpacity
            projectState.whiteBalanceValue = project.settings.whiteBalanceValue
            projectState.exportQuality = project.settings.exportQuality
            projectState.shouldOptimizeForBattery = project.settings.shouldOptimizeForBattery
            
            // Add to recent projects
            addToRecentProjects(project)
            
            // Generate preview
            projectState.generatePreview()
            
            print("✅ Project loaded successfully: \(project.name)")
            isLoading = false
            return true
            
        } catch {
            lastError = "Failed to load project: \(error.localizedDescription)"
            print("❌ Failed to load project: \(error)")
            isLoading = false
            return false
        }
    }
    
    func applyTemplate(_ template: ProjectTemplate, to projectState: ProjectState, lutManager: LUTManager) async -> Bool {
        isLoading = true
        lastError = nil
        
        do {
            // Find and apply primary LUT
            if let primaryLUT = lutManager.primaryLUTs.first(where: { $0.name == template.primaryLUTName }) {
                lutManager.selectedPrimaryLUT = primaryLUT
                projectState.setPrimaryLUT(primaryLUT.url)
            }
            
            // Find and apply secondary LUT
            if let secondaryLUTName = template.secondaryLUTName,
               let secondaryLUT = lutManager.secondaryLUTs.first(where: { $0.name == secondaryLUTName }) {
                lutManager.selectedSecondaryLUT = secondaryLUT
                projectState.setSecondaryLUT(secondaryLUT.url)
            } else {
                lutManager.selectedSecondaryLUT = nil
                projectState.setSecondaryLUT(nil)
            }
            
            // Apply settings
            projectState.primaryLUTOpacity = template.settings.primaryLUTOpacity
            projectState.secondLUTOpacity = template.settings.secondaryLUTOpacity
            projectState.whiteBalanceValue = template.settings.whiteBalanceValue
            projectState.exportQuality = template.settings.exportQuality
            projectState.shouldOptimizeForBattery = template.settings.shouldOptimizeForBattery
            
            // Generate preview if video is loaded
            if !projectState.videoURLs.isEmpty {
                projectState.generatePreview()
            }
            
            print("✅ Template applied successfully: \(template.name)")
            isLoading = false
            return true
            
        } catch {
            lastError = "Failed to apply template: \(error.localizedDescription)"
            print("❌ Failed to apply template: \(error)")
            isLoading = false
            return false
        }
    }
    
    func deleteProject(_ project: SavedProject) async -> Bool {
        isLoading = true
        lastError = nil
        
        do {
            // Remove from file system
            let projectURL = projectsDirectory.appendingPathComponent("\(project.id.uuidString).json")
            try FileManager.default.removeItem(at: projectURL)
            
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
        if let data = UserDefaults.standard.data(forKey: "\(userDefaultsKey)_recent"),
           let projects = try? JSONDecoder().decode([RecentProjectItem].self, from: data) {
            recentProjects = projects
        }
    }
    
    private func saveRecentProjects() {
        if let data = try? JSONEncoder().encode(recentProjects) {
            UserDefaults.standard.set(data, forKey: "\(userDefaultsKey)_recent")
        }
    }
    
    private func loadFavoriteProjects() {
        if let data = UserDefaults.standard.data(forKey: "\(userDefaultsKey)_favorites"),
           let favorites = try? JSONDecoder().decode([UUID].self, from: data) {
            favoriteProjects = favorites
        }
    }
    
    private func saveFavoriteProjects() {
        if let data = try? JSONEncoder().encode(favoriteProjects) {
            UserDefaults.standard.set(data, forKey: "\(userDefaultsKey)_favorites")
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
    
    init(name: String, videoURLs: [URL], primaryLUTName: String?, secondaryLUTName: String?, settings: ProjectSettings, previewThumbnail: Data? = nil) {
        self.id = UUID()
        self.name = name
        self.videoURLs = videoURLs
        self.primaryLUTName = primaryLUTName
        self.secondaryLUTName = secondaryLUTName
        self.settings = settings
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.previewThumbnail = previewThumbnail
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
    let id = UUID()
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