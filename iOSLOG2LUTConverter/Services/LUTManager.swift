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
        print("🔍 Attempting to load Primary LUTs...")
        
        // Try multiple methods to find the LUT files
        var primaryLUTsPath: String?
        
        // Method 1: Try Bundle.main.path
        if let bundlePath = Bundle.main.path(forResource: "Primary LUTS", ofType: nil) {
            primaryLUTsPath = bundlePath
            print("✅ Found Primary LUTS via Bundle.main.path: \(bundlePath)")
        }
        // Method 2: Try Bundle.main.resourcePath
        else if let resourcePath = Bundle.main.resourcePath {
            let testPath = resourcePath + "/Primary LUTS"
            if FileManager.default.fileExists(atPath: testPath) {
                primaryLUTsPath = testPath
                print("✅ Found Primary LUTS via resourcePath: \(testPath)")
            } else {
                print("❌ Primary LUTS not found at resourcePath: \(testPath)")
            }
        }
        // Method 3: Try Bundle.main.bundleURL
        else {
            let bundleURL = Bundle.main.bundleURL.appendingPathComponent("Primary LUTS")
            if FileManager.default.fileExists(atPath: bundleURL.path) {
                primaryLUTsPath = bundleURL.path
                print("✅ Found Primary LUTS via bundleURL: \(bundleURL.path)")
            } else {
                print("❌ Primary LUTS not found at bundleURL: \(bundleURL.path)")
            }
        }
        
        // If still not found, list all bundle contents for debugging
        if primaryLUTsPath == nil {
            print("❌ Could not find Primary LUTS directory anywhere")
            print("🔍 Debugging bundle contents:")
            if let resourcePath = Bundle.main.resourcePath {
                print("📁 Bundle resource path: \(resourcePath)")
                do {
                    let contents = try FileManager.default.contentsOfDirectory(atPath: resourcePath)
                    print("📋 Bundle contents: \(contents)")
                } catch {
                    print("❌ Error reading bundle contents: \(error)")
                }
            }
            return []
        }
        
        guard let lutPath = primaryLUTsPath else {
            print("❌ Primary LUTs path is nil")
            return []
        }
        
        print("📁 Looking for primary LUTs at: \(lutPath)")
        
        // Check if directory exists
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: lutPath) {
            print("❌ Primary LUTS directory does not exist at: \(lutPath)")
            return []
        }
        
        do {
            let lutFiles = try fileManager.contentsOfDirectory(atPath: lutPath)
                .filter { $0.hasSuffix(".cube") }
                .sorted()
            
            print("📁 Found \(lutFiles.count) primary LUT files in Primary LUTS folder")
            print("📋 Primary LUT files: \(lutFiles)")
            
            return lutFiles.compactMap { fileName in
                let filePath = lutPath + "/" + fileName
                let fileURL = URL(fileURLWithPath: filePath)
                
                let lut = LUT(
                    name: fileName,
                    displayName: formatLUTName(fileName),
                    description: generateLUTDescription(fileName),
                    category: categorizePrimaryLUT(fileName),
                    url: fileURL,
                    isBuiltIn: true,
                    isSecondary: false
                )
                
                print("✅ Created primary LUT: \(lut.displayName) (\(lut.category.rawValue))")
                return lut
            }
        } catch {
            print("❌ Error loading primary LUTs: \(error)")
            return []
        }
    }
    
    private func loadSecondaryLUTs() -> [LUT] {
        print("🔍 Attempting to load Secondary LUTs...")
        
        // Try multiple methods to find the LUT files
        var secondaryLUTsPath: String?
        
        // Method 1: Try Bundle.main.path
        if let bundlePath = Bundle.main.path(forResource: "Secondary LUTS", ofType: nil) {
            secondaryLUTsPath = bundlePath
            print("✅ Found Secondary LUTS via Bundle.main.path: \(bundlePath)")
        }
        // Method 2: Try Bundle.main.resourcePath
        else if let resourcePath = Bundle.main.resourcePath {
            let testPath = resourcePath + "/Secondary LUTS"
            if FileManager.default.fileExists(atPath: testPath) {
                secondaryLUTsPath = testPath
                print("✅ Found Secondary LUTS via resourcePath: \(testPath)")
            } else {
                print("❌ Secondary LUTS not found at resourcePath: \(testPath)")
            }
        }
        // Method 3: Try Bundle.main.bundleURL
        else {
            let bundleURL = Bundle.main.bundleURL.appendingPathComponent("Secondary LUTS")
            if FileManager.default.fileExists(atPath: bundleURL.path) {
                secondaryLUTsPath = bundleURL.path
                print("✅ Found Secondary LUTS via bundleURL: \(bundleURL.path)")
            } else {
                print("❌ Secondary LUTS not found at bundleURL: \(bundleURL.path)")
            }
        }
        
        // If still not found, list all bundle contents for debugging
        if secondaryLUTsPath == nil {
            print("❌ Could not find Secondary LUTS directory anywhere")
            return []
        }
        
        guard let lutPath = secondaryLUTsPath else {
            print("❌ Secondary LUTs path is nil")
            return []
        }
        
        print("📁 Looking for secondary LUTs at: \(lutPath)")
        
        // Check if directory exists
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: lutPath) {
            print("❌ Secondary LUTS directory does not exist at: \(lutPath)")
            return []
        }
        
        do {
            let lutFiles = try fileManager.contentsOfDirectory(atPath: lutPath)
                .filter { $0.hasSuffix(".cube") }
                .sorted()
            
            print("📁 Found \(lutFiles.count) secondary LUT files in Secondary LUTS folder")
            print("📋 Secondary LUT files: \(lutFiles.prefix(10))...") // Show first 10 to avoid spam
            
            return lutFiles.compactMap { fileName in
                let filePath = lutPath + "/" + fileName
                let fileURL = URL(fileURLWithPath: filePath)
                
                let lut = LUT(
                    name: fileName,
                    displayName: formatLUTName(fileName),
                    description: generateLUTDescription(fileName),
                    category: categorizeSecondaryLUT(fileName),
                    url: fileURL,
                    isBuiltIn: true,
                    isSecondary: true
                )
                
                print("✅ Created secondary LUT: \(lut.displayName) (\(lut.category.rawValue))")
                return lut
            }
        } catch {
            print("❌ Error loading secondary LUTs: \(error)")
            return []
        }
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