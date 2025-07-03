import SwiftUI

// MARK: - LUT Selector View with Apple Design
struct LUTSelectorView: View {
    @ObservedObject var lutManager: LUTManager
    @ObservedObject var fileImportManager: FileImportManager
    let isSecondary: Bool
    @Environment(\.dismiss) private var dismiss
    
    // Computed property to get the appropriate LUT collection
    private var lutsByCategory: [LUTManager.LUTCategory: [LUTManager.LUT]] {
        let luts = if isSecondary {
            lutManager.secondaryLutsByCategory
        } else {
            lutManager.primaryLutsByCategory
        }
        
        print("🔍 LUTSelectorView - \(isSecondary ? "Secondary" : "Primary") LUTs by category:")
        for (category, categoryLuts) in luts {
            print("   - \(category.rawValue): \(categoryLuts.count) LUTs")
        }
        print("   - Total categories: \(luts.keys.count)")
        
        return luts
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 20) {
                    // Header with icon and description
                    VStack(spacing: 12) {
                        Image(systemName: isSecondary ? "paintbrush.fill" : "camera.filters")
                            .font(.system(size: 40))
                            .foregroundStyle(isSecondary ? Color.pink.gradient : Color.blue.gradient)
                            .symbolEffect(.pulse)
                        
                        Text(isSecondary ? "Choose a Creative LUT" : "Choose a LUT")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        
                        Text(isSecondary ? "Select from creative secondary LUTs for layering effects" : "Select from professional built-in LUTs or import your own")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.top)
                    
                    // Debug info
                    if lutsByCategory.isEmpty {
                        VStack(spacing: 8) {
                            Text("🔍 Debug Info")
                                .font(.headline)
                                .foregroundStyle(.orange)
                            
                            Text("No LUTs found in \(isSecondary ? "secondary" : "primary") collection")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Text("LUT Manager loading: \(lutManager.isLoading ? "Yes" : "No")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    // LUT Categories
                    ForEach(Array(lutsByCategory.keys.sorted(by: { $0.rawValue < $1.rawValue })), id: \.self) { category in
                        LUTCategorySection(
                            category: category,
                            luts: lutsByCategory[category] ?? [],
                            isSecondary: isSecondary,
                            selectedLUT: isSecondary ? lutManager.selectedSecondaryLUT : lutManager.selectedPrimaryLUT
                        ) { lut in
                            if isSecondary {
                                lutManager.selectSecondaryLUT(lut)
                                print("🎨 Selected secondary LUT: \(lut.displayName)")
                            } else {
                                lutManager.selectPrimaryLUT(lut)
                                print("📷 Selected primary LUT: \(lut.displayName)")
                            }
                            dismiss()
                        }
                    }
                    
                    // Import Custom LUT Button
                    Button {
                        if isSecondary {
                            fileImportManager.isShowingCustomSecondaryLUTImporter = true
                        } else {
                            fileImportManager.isShowingCustomLUTImporter = true
                        }
                        print("📁 Opening custom LUT picker for \(isSecondary ? "secondary" : "primary") LUT")
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.blue)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Import Custom LUT")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                
                                Text("Browse for .cube, .3dl, or other LUT files")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.systemGray6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(.blue.opacity(0.3), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            }
            .navigationTitle(isSecondary ? "Secondary LUT" : "Primary LUT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .fileImporter(
            isPresented: isSecondary ? $fileImportManager.isShowingCustomSecondaryLUTImporter : $fileImportManager.isShowingCustomLUTImporter,
            allowedContentTypes: FileImportManager.SupportedLUTTypes.types,
            allowsMultipleSelection: false
        ) { result in
            print("🗂️ LUTSelectorView: fileImporter triggered for \(isSecondary ? "SECONDARY" : "PRIMARY") LUT")
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    lutManager.importCustomLUT(from: url, isSecondary: isSecondary)
                    print("✅ Successfully imported custom LUT: \(url.lastPathComponent)")
                }
            case .failure(let error):
                fileImportManager.lastImportStatus = .error("Failed to import LUT: \(error.localizedDescription)")
                print("❌ Failed to import custom LUT: \(error.localizedDescription)")
            }
        }
        .onAppear {
            print("👁️ LUTSelectorView appeared - \(isSecondary ? "Secondary" : "Primary") mode")
            print("📊 Current LUT counts:")
            print("   - Primary LUTs: \(lutManager.primaryLUTs.count)")
            print("   - Secondary LUTs: \(lutManager.secondaryLUTs.count)")
            print("🔍 LUTSelectorView: Current picker flags:")
            print("   - isShowingLUTPicker: \(fileImportManager.isShowingLUTPicker)")
            print("   - isShowingSecondaryLUTPicker: \(fileImportManager.isShowingSecondaryLUTPicker)")
        }
    }
}

// MARK: - LUT Category Section
struct LUTCategorySection: View {
    let category: LUTManager.LUTCategory
    let luts: [LUTManager.LUT]
    let isSecondary: Bool
    let selectedLUT: LUTManager.LUT?
    let onLUTSelected: (LUTManager.LUT) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Category Header
            HStack {
                Image(systemName: category.icon)
                    .foregroundStyle(category.color.gradient)
                    .font(.title3)
                
                Text(category.rawValue)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Text("\(luts.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray5))
                    .cornerRadius(12)
            }
            .padding(.horizontal, 4)
            
            // LUTs Grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(luts) { lut in
                    LUTCard(
                        lut: lut,
                        isSelected: selectedLUT == lut,
                        onTap: { onLUTSelected(lut) }
                    )
                }
            }
        }
    }
}

// MARK: - LUT Card
struct LUTCard: View {
    let lut: LUTManager.LUT
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // LUT Icon and Status
                HStack {
                    Image(systemName: lut.category.icon)
                        .font(.title3)
                        .foregroundStyle(lut.category.color.gradient)
                    
                    Spacer()
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.green.gradient)
                            .symbolEffect(.bounce, value: isSelected)
                    }
                }
                
                // LUT Name
                Text(lut.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                
                // LUT Description
                Text(lut.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                
                Spacer()
            }
            .padding(16)
            .frame(height: 120)
            .background(
                .thickMaterial,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isSelected ? Color.green.opacity(0.6) : Color.clear,
                        lineWidth: 2
                    )
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .shadow(
                color: isSelected ? .green.opacity(0.3) : .black.opacity(0.1),
                radius: isSelected ? 8 : 2,
                x: 0,
                y: isSelected ? 4 : 1
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
} 