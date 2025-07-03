import SwiftUI

// MARK: - Debug Control Panel for Testing
struct DebugControlPanel: View {
    @ObservedObject var projectState: ProjectState
    @ObservedObject var lutManager: LUTManager
    @ObservedObject var fileImportManager: FileImportManager
    
    @State private var showingLogs = false
    @State private var logs: [String] = []
    @State private var isRandomizing = false
    @State private var testProgress: Double = 0.0
    @State private var currentTestStep = ""
    
    // Randomization settings
    @State private var randomPrimaryOpacity: Float = 1.0
    @State private var randomSecondaryOpacity: Float = 0.5
    @State private var randomWhiteBalance: Float = 0.0
    @State private var randomUseGPU: Bool = true
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Image(systemName: "ant.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.yellow.gradient)
                
                Text("Debug Control Panel")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button {
                    showingLogs.toggle()
                } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.title3)
                }
            }
            .padding(.horizontal)
            
            // Test Status
            if !currentTestStep.isEmpty {
                HStack {
                    ProgressView(value: testProgress)
                        .progressViewStyle(.linear)
                    
                    Text(currentTestStep)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            }
            
            ScrollView {
                VStack(spacing: 16) {
                    // Quick Actions
                    quickActionsSection
                    
                    // Randomization Controls
                    randomizationSection
                    
                    // Manual Controls
                    manualControlsSection
                    
                    // Export Test
                    exportTestSection
                    
                    // System Info
                    systemInfoSection
                }
                .padding()
            }
        }
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .sheet(isPresented: $showingLogs) {
            LogViewerView(logs: logs)
        }
        .onAppear {
            captureInitialLogs()
        }
    }
    
    // MARK: - Quick Actions Section
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Quick Actions", systemImage: "bolt.fill")
                .font(.headline)
                .foregroundStyle(.primary)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                // Run Full Test
                Button {
                    runFullTest()
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Run Full Test")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue.gradient, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
                }
                
                // Randomize All
                Button {
                    randomizeAllSettings()
                } label: {
                    HStack {
                        Image(systemName: "dice.fill")
                        Text("Randomize All")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.purple.gradient, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
                }
                
                // Clear All
                Button {
                    clearAllSettings()
                } label: {
                    HStack {
                        Image(systemName: "trash.fill")
                        Text("Clear All")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.red.gradient, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
                }
                
                // Capture Logs
                Button {
                    captureLogs()
                } label: {
                    HStack {
                        Image(systemName: "doc.text.fill")
                        Text("Capture Logs")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.green.gradient, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Randomization Section
    private var randomizationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Randomization Settings", systemImage: "shuffle")
                .font(.headline)
                .foregroundStyle(.primary)
            
            // Random Primary LUT
            Button {
                randomizePrimaryLUT()
            } label: {
                HStack {
                    Text("Random Primary LUT")
                    Spacer()
                    if let lut = lutManager.selectedPrimaryLUT {
                        Text(lut.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 8))
            }
            
            // Random Secondary LUT
            Button {
                randomizeSecondaryLUT()
            } label: {
                HStack {
                    Text("Random Secondary LUT")
                    Spacer()
                    if let lut = lutManager.selectedSecondaryLUT {
                        Text(lut.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 8))
            }
            
            // Opacity Sliders
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Primary Opacity: \(Int(projectState.primaryLUTOpacity * 100))%")
                    Spacer()
                    Button("Random") {
                        randomizePrimaryOpacity()
                    }
                    .font(.caption)
                }
                
                Slider(value: $projectState.primaryLUTOpacity, in: 0...1)
                    .tint(.green)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Secondary Opacity: \(Int(projectState.secondLUTOpacity * 100))%")
                    Spacer()
                    Button("Random") {
                        randomizeSecondaryOpacity()
                    }
                    .font(.caption)
                }
                
                Slider(value: $projectState.secondLUTOpacity, in: 0...1)
                    .tint(.pink)
            }
            
            // CPU/GPU Toggle
            HStack {
                Text("Processing Mode")
                Spacer()
                Picker("", selection: $projectState.useGPU) {
                    Text("CPU").tag(false)
                    Text("GPU").tag(true)
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 150)
                
                Button("Random") {
                    projectState.useGPU = Bool.random()
                    addLog("🎲 Randomized processing mode: \(projectState.useGPU ? "GPU" : "CPU")")
                }
                .font(.caption)
            }
        }
        .padding()
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Manual Controls Section
    private var manualControlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Manual Controls", systemImage: "slider.horizontal.3")
                .font(.headline)
                .foregroundStyle(.primary)
            
            // White Balance
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("White Balance: \(projectState.formattedWhiteBalance)")
                    Spacer()
                    Button("Reset") {
                        projectState.whiteBalanceValue = 0.0
                    }
                    .font(.caption)
                }
                
                Slider(value: $projectState.whiteBalanceValue, in: -10...10)
                    .tint(.orange)
            }
            
            // Export Quality
            HStack {
                Text("Export Quality")
                Spacer()
                Picker("", selection: $projectState.exportQuality) {
                    ForEach(ExportQuality.allCases, id: \.self) { quality in
                        Text(quality.rawValue).tag(quality)
                    }
                }
                .pickerStyle(MenuPickerStyle())
            }
        }
        .padding()
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Export Test Section
    private var exportTestSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Export Test", systemImage: "square.and.arrow.up")
                .font(.headline)
                .foregroundStyle(.primary)
            
            // Current Settings Summary
            VStack(alignment: .leading, spacing: 8) {
                Text("Current Settings:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if let video = projectState.videoURLs.first {
                    Text("📹 Video: \(video.lastPathComponent)")
                        .font(.caption2)
                }
                
                if let primary = lutManager.selectedPrimaryLUT {
                    Text("🎨 Primary: \(primary.displayName) (\(Int(projectState.primaryLUTOpacity * 100))%)")
                        .font(.caption2)
                }
                
                if let secondary = lutManager.selectedSecondaryLUT {
                    Text("🎭 Secondary: \(secondary.displayName) (\(Int(projectState.secondLUTOpacity * 100))%)")
                        .font(.caption2)
                }
                
                Text("⚙️ Mode: \(projectState.useGPU ? "GPU" : "CPU")")
                    .font(.caption2)
            }
            .padding()
            .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 8))
            
            // Export Button
            Button {
                testExport()
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.up.fill")
                    Text("Test Export")
                    if projectState.isExporting {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(projectState.isReadyForExport ? Color.blue : Color.gray, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
            }
            .disabled(!projectState.isReadyForExport || projectState.isExporting)
        }
        .padding()
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - System Info Section
    private var systemInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("System Info", systemImage: "info.circle")
                .font(.headline)
                .foregroundStyle(.primary)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Video Count: \(projectState.videoURLs.count)")
                Text("Primary LUTs Loaded: \(lutManager.primaryLUTs.count)")
                Text("Secondary LUTs Loaded: \(lutManager.secondaryLUTs.count)")
                Text("Debug Mode: \(projectState.isDebugMode ? "Enabled" : "Disabled")")
                Text("GPU Available: Yes (Metal)")
                Text("Memory Usage: \(getMemoryUsage())")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Helper Methods
    private func runFullTest() {
        addLog("🚀 Starting full test workflow...")
        
        Task {
            // Step 1: Load test video
            updateTestProgress(0.1, "Loading test video...")
            projectState.enableDebugMode()
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            // Step 2: Randomize primary LUT
            updateTestProgress(0.2, "Selecting random primary LUT...")
            randomizePrimaryLUT()
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            // Step 3: Randomize secondary LUT
            updateTestProgress(0.3, "Selecting random secondary LUT...")
            randomizeSecondaryLUT()
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            // Step 4: Randomize opacities
            updateTestProgress(0.4, "Randomizing opacities...")
            randomizePrimaryOpacity()
            randomizeSecondaryOpacity()
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            // Step 5: Randomize settings
            updateTestProgress(0.5, "Randomizing settings...")
            projectState.whiteBalanceValue = Float.random(in: -5...5)
            projectState.useGPU = Bool.random()
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            // Step 6: Generate preview
            updateTestProgress(0.6, "Generating preview...")
            projectState.generatePreview()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            
            // Step 7: Export
            updateTestProgress(0.8, "Starting export...")
            testExport()
            
            updateTestProgress(1.0, "Test complete!")
            addLog("✅ Full test workflow completed")
            
            // Clear progress after delay
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            updateTestProgress(0.0, "")
        }
    }
    
    private func randomizeAllSettings() {
        addLog("🎲 Randomizing all settings...")
        
        withAnimation {
            randomizePrimaryLUT()
            randomizeSecondaryLUT()
            randomizePrimaryOpacity()
            randomizeSecondaryOpacity()
            projectState.whiteBalanceValue = Float.random(in: -10...10)
            projectState.useGPU = Bool.random()
            projectState.exportQuality = ExportQuality.allCases.randomElement() ?? .high
        }
        
        projectState.generatePreview()
    }
    
    private func clearAllSettings() {
        addLog("🗑️ Clearing all settings...")
        
        withAnimation {
            lutManager.clearPrimaryLUT()
            lutManager.clearSecondaryLUT()
            projectState.resetToDefaults()
            projectState.videoURLs.removeAll()
        }
    }
    
    private func randomizePrimaryLUT() {
        guard !lutManager.primaryLUTs.isEmpty else {
            addLog("❌ No primary LUTs available")
            return
        }
        
        let randomLUT = lutManager.primaryLUTs.randomElement()!
        lutManager.selectPrimaryLUT(randomLUT)
        addLog("🎨 Selected primary LUT: \(randomLUT.displayName)")
    }
    
    private func randomizeSecondaryLUT() {
        guard !lutManager.secondaryLUTs.isEmpty else {
            addLog("❌ No secondary LUTs available")
            return
        }
        
        let randomLUT = lutManager.secondaryLUTs.randomElement()!
        lutManager.selectSecondaryLUT(randomLUT)
        addLog("🎭 Selected secondary LUT: \(randomLUT.displayName)")
    }
    
    private func randomizePrimaryOpacity() {
        projectState.primaryLUTOpacity = Float.random(in: 0.3...1.0)
        addLog("🎨 Primary opacity: \(Int(projectState.primaryLUTOpacity * 100))%")
    }
    
    private func randomizeSecondaryOpacity() {
        projectState.secondLUTOpacity = Float.random(in: 0.1...0.8)
        addLog("🎭 Secondary opacity: \(Int(projectState.secondLUTOpacity * 100))%")
    }
    
    private func testExport() {
        addLog("📤 Starting test export...")
        addLog("⚙️ GPU: \(projectState.useGPU ? "Enabled" : "Disabled")")
        addLog("📊 Quality: \(projectState.exportQuality.rawValue)")
        
        // The actual export is handled by ContentView's exportVideo method
        NotificationCenter.default.post(name: Notification.Name("DebugTestExport"), object: nil)
    }
    
    private func updateTestProgress(_ progress: Double, _ step: String) {
        DispatchQueue.main.async {
            self.testProgress = progress
            self.currentTestStep = step
        }
    }
    
    private func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let logEntry = "[\(timestamp)] \(message)"
        logs.append(logEntry)
        print(message)
        
        // Keep only last 100 logs
        if logs.count > 100 {
            logs.removeFirst()
        }
    }
    
    private func captureInitialLogs() {
        addLog("🐛 Debug Control Panel initialized")
        addLog("📱 Device: \(UIDevice.current.name)")
        addLog("🖥️ System: iOS \(UIDevice.current.systemVersion)")
        addLog("💾 Available Storage: \(getAvailableStorage())")
    }
    
    private func captureLogs() {
        addLog("📸 Capturing current state...")
        addLog("Videos: \(projectState.videoURLs.count)")
        addLog("Primary LUT: \(lutManager.selectedPrimaryLUT?.displayName ?? "None")")
        addLog("Secondary LUT: \(lutManager.selectedSecondaryLUT?.displayName ?? "None")")
        addLog("GPU Mode: \(projectState.useGPU)")
        addLog("Export Quality: \(projectState.exportQuality.rawValue)")
        showingLogs = true
    }
    
    private func getMemoryUsage() -> String {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if result == KERN_SUCCESS {
            let usedMemory = Double(info.resident_size) / 1024.0 / 1024.0
            return String(format: "%.1f MB", usedMemory)
        }
        return "Unknown"
    }
    
    private func getAvailableStorage() -> String {
        do {
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            if let freeSpace = attributes[.systemFreeSize] as? NSNumber {
                let freeSpaceGB = freeSpace.doubleValue / 1024 / 1024 / 1024
                return String(format: "%.1f GB", freeSpaceGB)
            }
        } catch {}
        return "Unknown"
    }
}

// MARK: - Log Viewer
struct LogViewerView: View {
    let logs: [String]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(logs, id: \.self) { log in
                        Text(log)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(colorForLog(log))
                            .padding(.horizontal)
                            .padding(.vertical, 2)
                    }
                }
                .padding(.vertical)
            }
            .background(Color(.systemBackground))
            .navigationTitle("Debug Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        shareLogs()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }
    
    private func colorForLog(_ log: String) -> Color {
        if log.contains("❌") || log.contains("Error") {
            return .red
        } else if log.contains("⚠️") || log.contains("Warning") {
            return .orange
        } else if log.contains("✅") || log.contains("Success") {
            return .green
        } else if log.contains("🎲") || log.contains("Random") {
            return .purple
        } else if log.contains("📤") || log.contains("Export") {
            return .blue
        }
        return .primary
    }
    
    private func shareLogs() {
        let logText = logs.joined(separator: "\n")
        
        let activityVC = UIActivityViewController(
            activityItems: [logText],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

#Preview {
    DebugControlPanel(
        projectState: ProjectState(),
        lutManager: LUTManager(),
        fileImportManager: FileImportManager()
    )
    .frame(height: 600)
    .padding()
}