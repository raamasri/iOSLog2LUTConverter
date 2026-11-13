import Foundation
import SwiftUI

// MARK: - LUT Manager for Default and Custom LUTs
@MainActor
class LUTManager: ObservableObject {
    
    // MARK: - LUT Data Model
    struct LUT: Identifiable, Hashable {
        var id: String { "\(isSecondary ? "secondary" : "primary"):\(url.standardizedFileURL.path)" }
        let name: String
        let displayName: String
        let description: String
        let category: LUTCategory
        let url: URL
        let isBuiltIn: Bool
        let isSecondary: Bool
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
        
        static func == (lhs: LUT, rhs: LUT) -> Bool {
            lhs.id == rhs.id
        }
    }
    
    // MARK: - LUT Categories
    enum LUTCategory: String, CaseIterable {
        case appleLog = "Apple Log"
        case sonyS_Log2 = "Sony S-Log2"
        case sonyS_Log3 = "Sony S-Log3"
        case creative = "Creative"
        case cinematic = "Cinematic"
        case filmEmulation = "Film Emulation"
        case tvShows = "TV Shows"
        case custom = "Custom"
        
        var icon: String {
            switch self {
            case .appleLog: return "apple.logo"
            case .sonyS_Log2, .sonyS_Log3: return "video.fill"
            case .creative: return "paintbrush.fill"
            case .cinematic: return "film.fill"
            case .filmEmulation: return "camera.vintage"
            case .tvShows: return "tv.fill"
            case .custom: return "folder.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .appleLog: return .blue
            case .sonyS_Log2, .sonyS_Log3: return .orange
            case .creative: return .pink
            case .cinematic: return .purple
            case .filmEmulation: return .green
            case .tvShows: return .red
            case .custom: return .gray
            }
        }
    }
    
    // MARK: - Published Properties
    @Published var primaryLUTs: [LUT] = []
    @Published var secondaryLUTs: [LUT] = []
    @Published var customLUTs: [LUT] = []
    @Published var selectedPrimaryLUT: LUT?
    @Published var selectedSecondaryLUT: LUT?
    @Published var isLoading = false
    private var builtInLUTLoadTask: Task<Void, Never>?
    
    // MARK: - Computed Properties
    var primaryLutsByCategory: [LUTCategory: [LUT]] {
        Dictionary(grouping: catalogIncludingSelection(primaryLUTs + customLUTs.filter { !$0.isSecondary }, selected: selectedPrimaryLUT), by: { $0.category })
    }
    
    var secondaryLutsByCategory: [LUTCategory: [LUT]] {
        Dictionary(grouping: catalogIncludingSelection(secondaryLUTs + customLUTs.filter { $0.isSecondary }, selected: selectedSecondaryLUT), by: { $0.category })
    }
    
    private func catalogIncludingSelection(_ catalog: [LUT], selected: LUT?) -> [LUT] {
        // Saved projects own exact copies of their LUTs. Surface the active copy
        // in the selector without importing it into the global library or changing
        // its URL; clearing the selection also removes this temporary catalog row.
        guard let selected, !catalog.contains(where: { $0.id == selected.id }) else { return catalog }
        return catalog + [selected]
    }

    var hasSelectedPrimaryLUT: Bool {
        selectedPrimaryLUT != nil
    }
    
    var hasSelectedSecondaryLUT: Bool {
        selectedSecondaryLUT != nil
    }
    
    // MARK: - Initialization
    init() {
        loadBuiltInLUTs()
        loadCustomLUTs()
    }
    
    // MARK: - LUT Loading
    @discardableResult
    func loadBuiltInLUTs() -> Task<Void, Never> {
        if let builtInLUTLoadTask { return builtInLUTLoadTask }
        isLoading = true
        let task = Task.detached(priority: .userInitiated) { [self] in
            let primary = self.loadPrimaryLUTs()
            let secondary = self.loadSecondaryLUTs()
            await MainActor.run {
                self.primaryLUTs = primary
                self.secondaryLUTs = secondary
                self.isLoading = false
                self.builtInLUTLoadTask = nil
            }
        }
        builtInLUTLoadTask = task
        return task
    }

    nonisolated private func loadPrimaryLUTs() -> [LUT] {
        print("🔍 Loading Primary LUTs from app bundle...")
        
        // First try to find Primary LUTS subfolder (for simulator/development)
        if let primaryLUTsURL = Bundle.main.url(forResource: "Primary LUTS", withExtension: nil) {
            print("✅ Found Primary LUTS folder at: \(primaryLUTsURL.path)")
            return loadLUTsFromDirectory(primaryLUTsURL, isPrimary: true)
        }
        
        // Fallback: Load from bundle root and filter by filename patterns (for device deployment)
        print("📱 Primary LUTS folder not found, loading from bundle root...")
        return loadPrimaryLUTsFromBundleRoot()
    }
    
    nonisolated private func loadSecondaryLUTs() -> [LUT] {
        print("🔍 Loading Secondary LUTs from app bundle...")
        
        // First try to find Secondary LUTS subfolder (for simulator/development)
        if let secondaryLUTsURL = Bundle.main.url(forResource: "Secondary LUTS", withExtension: nil) {
            print("✅ Found Secondary LUTS folder at: \(secondaryLUTsURL.path)")
            return loadLUTsFromDirectory(secondaryLUTsURL, isPrimary: false)
        }
        
        // Fallback: Load from bundle root and filter by filename patterns (for device deployment)
        print("📱 Secondary LUTS folder not found, loading from bundle root...")
        return loadSecondaryLUTsFromBundleRoot()
    }
    
    nonisolated private func loadLUTsFromDirectory(_ directoryURL: URL, isPrimary: Bool) -> [LUT] {
        do {
            let lutFiles = try FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "cube" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            
            print("📁 Found \(lutFiles.count) \(isPrimary ? "primary" : "secondary") LUT files")
            
            let luts = lutFiles.compactMap { url in
                isPrimary ? createPrimaryLUT(from: url) : createSecondaryLUT(from: url)
            }
            
            return luts
        } catch {
            print("❌ Error loading LUTs from directory: \(error)")
            return []
        }
    }
    
    nonisolated private func loadPrimaryLUTsFromBundleRoot() -> [LUT] {
        let bundleURL = Bundle.main.bundleURL
        
        do {
            let allFiles = try FileManager.default.contentsOfDirectory(at: bundleURL, includingPropertiesForKeys: nil)
            let cubeFiles = allFiles.filter { $0.pathExtension.lowercased() == "cube" }
            
            // Filter for primary LUTs based on filename patterns
            let primaryLUTFiles = cubeFiles.filter { url in
                let filename = url.lastPathComponent.uppercased()
                return filename.contains("APPLELOG") ||
                       filename.contains("SGAMUT") ||
                       filename.contains("SLOG") ||
                       filename.contains("_TO_") ||
                       filename.contains("FROM_")
            }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            
            print("📁 Found \(primaryLUTFiles.count) primary LUT files in bundle root")
            print("📋 Primary LUT files: \(primaryLUTFiles.map { $0.lastPathComponent })")
            
            let luts = primaryLUTFiles.compactMap { createPrimaryLUT(from: $0) }
            return luts
        } catch {
            print("❌ Error loading primary LUTs from bundle root: \(error)")
            return []
        }
    }
    
    nonisolated private func loadSecondaryLUTsFromBundleRoot() -> [LUT] {
        let bundleURL = Bundle.main.bundleURL
        
        do {
            let allFiles = try FileManager.default.contentsOfDirectory(at: bundleURL, includingPropertiesForKeys: nil)
            let cubeFiles = allFiles.filter { $0.pathExtension.lowercased() == "cube" }
            
            // Filter for secondary LUTs (everything that's not a primary LUT)
            let secondaryLUTFiles = cubeFiles.filter { url in
                let filename = url.lastPathComponent.uppercased()
                return !(filename.contains("APPLELOG") ||
                        filename.contains("SGAMUT") ||
                        filename.contains("SLOG") ||
                        filename.contains("_TO_") ||
                        filename.contains("FROM_"))
            }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            
            print("📁 Found \(secondaryLUTFiles.count) secondary LUT files in bundle root")
            print("📋 Secondary LUT files: \(secondaryLUTFiles.prefix(10).map { $0.lastPathComponent })...")
            
            let luts = secondaryLUTFiles.compactMap { createSecondaryLUT(from: $0) }
            return luts
        } catch {
            print("❌ Error loading secondary LUTs from bundle root: \(error)")
            return []
        }
    }
    
    // MARK: - LUT Creation Helper Methods
    nonisolated private func createPrimaryLUT(from url: URL) -> LUT? {
        let fileName = url.lastPathComponent
        
        let lut = LUT(
            name: fileName,
            displayName: formatLUTName(fileName),
            description: generateLUTDescription(fileName, isSecondary: false),
            category: categorizePrimaryLUT(fileName),
            url: url,
            isBuiltIn: true,
            isSecondary: false
        )
        
        return lut
    }
    
    nonisolated private func createSecondaryLUT(from url: URL) -> LUT? {
        let fileName = url.lastPathComponent
        
        let lut = LUT(
            name: fileName,
            displayName: formatLUTName(fileName),
            description: generateLUTDescription(fileName, isSecondary: true),
            category: categorizeSecondaryLUT(fileName),
            url: url,
            isBuiltIn: true,
            isSecondary: true
        )
        
        return lut
    }
    
    // MARK: - LUT Categorization
    nonisolated private func categorizePrimaryLUT(_ fileName: String) -> LUTCategory {
        let name = fileName.lowercased()
        
        if name.contains("apple") {
            return .appleLog
        } else if name.contains("slog3") || name.contains("sgamut3") {
            return .sonyS_Log3
        } else if name.contains("slog2") {
            return .sonyS_Log2
        } else {
            return .custom
        }
    }
    
    nonisolated private func categorizeSecondaryLUT(_ fileName: String) -> LUTCategory {
        let name = fileName.lowercased()
        
        // TV Shows
        if name.contains("breaking bad") || name.contains("game of thrones") || 
           name.contains("ozark") || name.contains("euphoria") || 
           name.contains("chernobyl") || name.contains("dahmer") ||
           name.contains("peaky blinders") || name.contains("dark") {
            return .tvShows
        }
        
        // Film Emulation
        if name.contains("kodachrome") || name.contains("velvia") || 
           name.contains("porta") || name.contains("provia") ||
           name.contains("eterna") || name.contains("superia") ||
           name.contains("50d") || name.contains("gold") ||
           name.contains("500t") || name.contains("pro_400h") {
            return .filmEmulation
        }
        
        // Cinematic
        if name.contains("joker") || name.contains("batman") || 
           name.contains("blade runner") || name.contains("1917") ||
           name.contains("parasite") || name.contains("roma") ||
           name.contains("revenant") || name.contains("macbeth") ||
           name.contains("green knight") || name.contains("taxi driver") ||
           name.contains("fight club") || name.contains("nightcrawler") ||
           name.contains("assassination") || name.contains("fallen angels") ||
           name.contains("banshees") || name.contains("whiplash") ||
           name.contains("country for old men") || name.contains("western front") {
            return .cinematic
        }
        
        // Creative (everything else)
        return .creative
    }
    
    // MARK: - LUT Name Formatting
    nonisolated private func formatLUTName(_ fileName: String) -> String {
        let nameWithoutExtension = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        
        // Special formatting for common patterns
        let formatted = nameWithoutExtension
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
        
        return formatted.trimmingCharacters(in: .whitespaces)
    }
    
    nonisolated private func generateLUTDescription(_ fileName: String, isSecondary: Bool) -> String {
        let category = isSecondary ?
            categorizeSecondaryLUT(fileName) : categorizePrimaryLUT(fileName)
        
        switch category {
        case .appleLog:
            return fileName.lowercased().contains("tolin") ? "Apple Log to linear conversion" : "Apple Log to Rec.709 conversion"
        case .sonyS_Log2:
            return "Sony S-Log2 to Rec.709 conversion"
        case .sonyS_Log3:
            return "Sony S-Log3 to Rec.709 conversion"
        case .creative:
            return "Creative color grading effect"
        case .cinematic:
            return "Cinematic color grading inspired by films"
        case .filmEmulation:
            return "Film stock emulation"
        case .tvShows:
            return "TV show inspired color grading"
        case .custom:
            return "Custom LUT"
        }
    }
    
    // MARK: - LUT Selection
    func selectPrimaryLUT(_ lut: LUT?) {
        selectedPrimaryLUT = lut
    }
    
    func selectSecondaryLUT(_ lut: LUT?) {
        selectedSecondaryLUT = lut
    }
    
    func clearPrimaryLUT() {
        selectedPrimaryLUT = nil
    }
    
    func clearSecondaryLUT() {
        selectedSecondaryLUT = nil
    }
    
    // MARK: - Custom LUT Import
    @discardableResult
    func importCustomLUT(from url: URL, isSecondary: Bool = false) throws -> LUT {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }

        // Validate before persisting or selecting the file so unsupported/invalid
        // imports cannot silently replace a working grade.
        _ = try LUTParsingUtils.parseLUTFile(url)
        let directory = customLUTDirectory(isSecondary: isSecondary)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = url.deletingPathExtension().lastPathComponent
        var destination = directory.appendingPathComponent(name).appendingPathExtension("cube")
        var suffix = 2
        while FileManager.default.fileExists(atPath: destination.path) && destination != url {
            destination = directory.appendingPathComponent("\(name) \(suffix)").appendingPathExtension("cube")
            suffix += 1
        }
        if destination != url {
            do {
                try FileManager.default.copyItem(at: url, to: destination)
            } catch {
                try? FileManager.default.removeItem(at: destination)
                throw error
            }
        }
        let lut = makeCustomLUT(url: destination, isSecondary: isSecondary)
        if !customLUTs.contains(where: { $0.url == destination }) {
            customLUTs.append(lut)
        }
        if isSecondary { selectedSecondaryLUT = lut } else { selectedPrimaryLUT = lut }
        return lut
    }

    private func customLUTDirectory(isSecondary: Bool) -> URL {
        URL.documentsDirectory.appendingPathComponent("CustomLUTs", isDirectory: true)
            .appendingPathComponent(isSecondary ? "Secondary" : "Primary", isDirectory: true)
    }

    private func makeCustomLUT(url: URL, isSecondary: Bool) -> LUT {
        LUT(name: url.lastPathComponent, displayName: formatLUTName(url.lastPathComponent),
            description: "Custom LUT", category: .custom, url: url,
            isBuiltIn: false, isSecondary: isSecondary)
    }

    private func loadCustomLUTs() {
        customLUTs = [false, true].flatMap { isSecondary in
            let files = (try? FileManager.default.contentsOfDirectory(
                at: customLUTDirectory(isSecondary: isSecondary), includingPropertiesForKeys: nil)) ?? []
            return files.filter { $0.pathExtension.lowercased() == "cube" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                .map { makeCustomLUT(url: $0, isSecondary: isSecondary) }
        }
    }
}
