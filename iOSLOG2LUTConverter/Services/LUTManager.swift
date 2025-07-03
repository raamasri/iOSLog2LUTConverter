import Foundation
import SwiftUI

// MARK: - LUT Manager for Default and Custom LUTs
class LUTManager: ObservableObject {
    
    // MARK: - LUT Data Model
    struct LUT: Identifiable, Hashable {
        let id = UUID()
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
    
    // MARK: - Computed Properties
    var primaryLutsByCategory: [LUTCategory: [LUT]] {
        Dictionary(grouping: primaryLUTs, by: { $0.category })
    }
    
    var secondaryLutsByCategory: [LUTCategory: [LUT]] {
        Dictionary(grouping: secondaryLUTs + customLUTs.filter { $0.isSecondary }, by: { $0.category })
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
    }
    
    // MARK: - LUT Loading
    private func loadBuiltInLUTs() {
        print("🔄 Starting to load built-in LUTs...")
        isLoading = true
        
        DispatchQueue.global(qos: .background).async {
            let primaryLUTs = self.loadPrimaryLUTs()
            let secondaryLUTs = self.loadSecondaryLUTs()
            
            print("✅ Loaded \(primaryLUTs.count) primary LUTs and \(secondaryLUTs.count) secondary LUTs")
            
            DispatchQueue.main.async {
                self.primaryLUTs = primaryLUTs
                self.secondaryLUTs = secondaryLUTs
                self.isLoading = false
                
                print("📊 LUT Manager State:")
                print("   - Primary LUTs: \(self.primaryLUTs.count)")
                print("   - Secondary LUTs: \(self.secondaryLUTs.count)")
                print("   - Primary by Category: \(self.primaryLutsByCategory.keys.count) categories")
                print("   - Secondary by Category: \(self.secondaryLutsByCategory.keys.count) categories")
            }
        }
    }
    
    private func loadPrimaryLUTs() -> [LUT] {
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
    
    private func loadSecondaryLUTs() -> [LUT] {
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
    
    private func loadLUTsFromDirectory(_ directoryURL: URL, isPrimary: Bool) -> [LUT] {
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
    
    private func loadPrimaryLUTsFromBundleRoot() -> [LUT] {
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
    
    private func loadSecondaryLUTsFromBundleRoot() -> [LUT] {
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
    private func createPrimaryLUT(from url: URL) -> LUT? {
        let fileName = url.lastPathComponent
        
        let lut = LUT(
            name: fileName,
            displayName: formatLUTName(fileName),
            description: generateLUTDescription(fileName),
            category: categorizePrimaryLUT(fileName),
            url: url,
            isBuiltIn: true,
            isSecondary: false
        )
        
        print("✅ Created primary LUT: \(lut.displayName) (\(lut.category.rawValue))")
        return lut
    }
    
    private func createSecondaryLUT(from url: URL) -> LUT? {
        let fileName = url.lastPathComponent
        
        let lut = LUT(
            name: fileName,
            displayName: formatLUTName(fileName),
            description: generateLUTDescription(fileName),
            category: categorizeSecondaryLUT(fileName),
            url: url,
            isBuiltIn: true,
            isSecondary: true
        )
        
        print("✅ Created secondary LUT: \(lut.displayName) (\(lut.category.rawValue))")
        return lut
    }
    
    // MARK: - LUT Categorization
    private func categorizePrimaryLUT(_ fileName: String) -> LUTCategory {
        let name = fileName.lowercased()
        
        if name.contains("apple") {
            return .appleLog
        } else if name.contains("slog2") {
            return .sonyS_Log2
        } else if name.contains("slog3") {
            return .sonyS_Log3
        } else {
            return .custom
        }
    }
    
    private func categorizeSecondaryLUT(_ fileName: String) -> LUTCategory {
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
    private func formatLUTName(_ fileName: String) -> String {
        let nameWithoutExtension = fileName.replacingOccurrences(of: ".cube", with: "")
        
        // Special formatting for common patterns
        let formatted = nameWithoutExtension
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
        
        return formatted.trimmingCharacters(in: .whitespaces)
    }
    
    private func generateLUTDescription(_ fileName: String) -> String {
        let category = fileName.contains("Secondary") ? 
            categorizeSecondaryLUT(fileName) : categorizePrimaryLUT(fileName)
        
        switch category {
        case .appleLog:
            return "Apple Log to Rec.709 conversion"
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
    func importCustomLUT(from url: URL, isSecondary: Bool = false) {
        // Implementation for custom LUT import
        // This would copy the file to app documents and add to customLUTs array
        print("📥 Importing custom LUT: \(url.lastPathComponent)")
    }
} 