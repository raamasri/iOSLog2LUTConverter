import SwiftUI

// MARK: - Project Management View
struct ProjectManagementView: View {
    @StateObject private var projectManager = ProjectManager()
    @ObservedObject var projectState: ProjectState
    @ObservedObject var lutManager: LUTManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    @State private var selectedTab = 0
    @State private var showingSaveDialog = false
    @State private var newProjectName = ""
    @State private var showingDeleteConfirmation = false
    @State private var projectToDelete: SavedProject?
    @State private var searchText = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                headerView
                
                // Tab Picker
                tabPickerView
                
                // Content
                TabView(selection: $selectedTab) {
                    templatesView
                        .tag(0)
                    
                    savedProjectsView
                        .tag(1)
                    
                    favoritesView
                        .tag(2)
                    
                    recentProjectsView
                        .tag(3)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            }
            .navigationBarHidden(true)
            .background(Color(.systemGroupedBackground))
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .sheet(isPresented: $showingSaveDialog) {
            saveProjectDialog
        }
        .alert("Delete Project", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let project = projectToDelete {
                    Task {
                        await projectManager.deleteProject(project)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete '\(projectToDelete?.name ?? "this project")'? This action cannot be undone.")
        }
    }
    
    // MARK: - Header View
    private var headerView: some View {
        HStack {
            Button("Close") {
                dismiss()
            }
            .foregroundColor(.blue)
            
            Spacer()
            
            Text("Project Management")
                .font(.headline)
                .fontWeight(.semibold)
            
            Spacer()
            
            Button("Save Current") {
                showingSaveDialog = true
            }
            .foregroundColor(.blue)
            .disabled(projectState.videoURLs.isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }
    
    // MARK: - Tab Picker View
    private var tabPickerView: some View {
        HStack {
            ForEach([
                ("Templates", "doc.text.fill", 0),
                ("Saved", "folder.fill", 1),
                ("Favorites", "heart.fill", 2),
                ("Recent", "clock.fill", 3)
            ], id: \.2) { title, icon, index in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        selectedTab = index
                    }
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .medium))
                        Text(title)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(selectedTab == index ? .blue : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        Rectangle()
                            .fill(selectedTab == index ? Color.blue.opacity(0.1) : Color.clear)
                            .animation(.easeInOut(duration: 0.3), value: selectedTab)
                    )
                }
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    // MARK: - Templates View
    private var templatesView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(ProjectTemplate.TemplateCategory.allCases, id: \.self) { category in
                    let categoryTemplates = projectManager.projectTemplates.filter { $0.category == category }
                    
                    if !categoryTemplates.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            categoryHeaderView(category)
                            
                            LazyVGrid(columns: gridColumns, spacing: 12) {
                                ForEach(categoryTemplates) { template in
                                    TemplateCard(template: template) {
                                        applyTemplate(template)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
        .searchable(text: $searchText, prompt: "Search templates...")
    }
    
    // MARK: - Saved Projects View
    private var savedProjectsView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if projectManager.savedProjects.isEmpty {
                    emptyStateView(
                        icon: "folder.fill",
                        title: "No Saved Projects",
                        description: "Save your current project configuration to access it later"
                    )
                } else {
                    ForEach(filteredSavedProjects) { project in
                        ProjectCard(
                            project: project,
                            isFavorite: projectManager.favoriteProjects.contains(project.id)
                        ) {
                            loadProject(project)
                        } onFavorite: {
                            projectManager.toggleFavorite(project)
                        } onDelete: {
                            projectToDelete = project
                            showingDeleteConfirmation = true
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical)
        }
        .searchable(text: $searchText, prompt: "Search saved projects...")
    }
    
    // MARK: - Favorites View
    private var favoritesView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if projectManager.favoriteProjectsList.isEmpty {
                    emptyStateView(
                        icon: "heart.fill",
                        title: "No Favorite Projects",
                        description: "Mark projects as favorites to quickly access them here"
                    )
                } else {
                    ForEach(projectManager.favoriteProjectsList) { project in
                        ProjectCard(
                            project: project,
                            isFavorite: true
                        ) {
                            loadProject(project)
                        } onFavorite: {
                            projectManager.toggleFavorite(project)
                        } onDelete: {
                            projectToDelete = project
                            showingDeleteConfirmation = true
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical)
        }
        .searchable(text: $searchText, prompt: "Search favorite projects...")
    }
    
    // MARK: - Recent Projects View
    private var recentProjectsView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if projectManager.recentProjects.isEmpty {
                    emptyStateView(
                        icon: "clock.fill",
                        title: "No Recent Projects",
                        description: "Projects you've recently worked on will appear here"
                    )
                } else {
                    ForEach(projectManager.recentProjects) { recentItem in
                        if let project = projectManager.savedProjects.first(where: { $0.id == recentItem.projectId }) {
                            RecentProjectCard(
                                project: project,
                                recentItem: recentItem,
                                isFavorite: projectManager.favoriteProjects.contains(project.id)
                            ) {
                                loadProject(project)
                            } onFavorite: {
                                projectManager.toggleFavorite(project)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical)
        }
        .searchable(text: $searchText, prompt: "Search recent projects...")
    }
    
    // MARK: - Save Project Dialog
    private var saveProjectDialog: some View {
        NavigationView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Project Name")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    TextField("Enter project name", text: $newProjectName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocorrectionDisabled()
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Current Configuration")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Videos:")
                            Spacer()
                            Text("\(projectState.videoURLs.count) file(s)")
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Primary LUT:")
                            Spacer()
                            Text(lutManager.selectedPrimaryLUT?.displayName ?? "None")
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Secondary LUT:")
                            Spacer()
                            Text(lutManager.selectedSecondaryLUT?.displayName ?? "None")
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Export Quality:")
                            Spacer()
                            Text(projectState.exportQuality.rawValue)
                                .foregroundColor(.secondary)
                        }
                    }
                    .font(.subheadline)
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Save Project")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Cancel") {
                    showingSaveDialog = false
                    newProjectName = ""
                },
                trailing: Button("Save") {
                    Task {
                        let success = await projectManager.saveProject(
                            name: newProjectName,
                            projectState: projectState,
                            lutManager: lutManager
                        )
                        if success {
                            showingSaveDialog = false
                            newProjectName = ""
                        }
                    }
                }
                .disabled(newProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            )
        }
    }
    
    // MARK: - Helper Views
    private func categoryHeaderView(_ category: ProjectTemplate.TemplateCategory) -> some View {
        HStack {
            Image(systemName: category.icon)
                .foregroundColor(category.color)
                .font(.title2)
            
            Text(category.rawValue)
                .font(.headline)
                .fontWeight(.semibold)
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    private func emptyStateView(icon: String, title: String, description: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            
            Text(description)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 60)
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Computed Properties
    private var gridColumns: [GridItem] {
        let columns = horizontalSizeClass == .regular ? 2 : 1
        return Array(repeating: GridItem(.flexible()), count: columns)
    }
    
    private var filteredSavedProjects: [SavedProject] {
        if searchText.isEmpty {
            return projectManager.savedProjects
        } else {
            return projectManager.savedProjects.filter { project in
                project.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    // MARK: - Actions
    private func applyTemplate(_ template: ProjectTemplate) {
        Task {
            let success = await projectManager.applyTemplate(template, to: projectState, lutManager: lutManager)
            if success {
                dismiss()
            }
        }
    }
    
    private func loadProject(_ project: SavedProject) {
        Task {
            let success = await projectManager.loadProject(project, into: projectState, lutManager: lutManager)
            if success {
                dismiss()
            }
        }
    }
}

// MARK: - Template Card
struct TemplateCard: View {
    let template: ProjectTemplate
    let onApply: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: template.icon)
                    .font(.title2)
                    .foregroundColor(template.category.color)
                
                Spacer()
                
                Button("Apply") {
                    onApply()
                }
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(template.category.color.opacity(0.1))
                .foregroundColor(template.category.color)
                .clipShape(Capsule())
            }
            
            Text(template.name)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Text(template.description)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(3)
            
            VStack(alignment: .leading, spacing: 4) {
                if let secondary = template.secondaryLUTName {
                    Text("• \(template.primaryLUTName)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("• \(secondary)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text("• \(template.primaryLUTName)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Project Card
struct ProjectCard: View {
    let project: SavedProject
    let isFavorite: Bool
    let onLoad: () -> Void
    let onFavorite: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text(DateFormatter.projectDateFormatter.string(from: project.createdAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    Button(action: onFavorite) {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                            .foregroundColor(isFavorite ? .red : .secondary)
                    }
                    
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                }
            }
            
            if let thumbnailData = project.previewThumbnail,
               let thumbnail = UIImage(data: thumbnailData) {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                if let primaryLUT = project.primaryLUTName {
                    Text("Primary: \(primaryLUT)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let secondaryLUT = project.secondaryLUTName {
                    Text("Secondary: \(secondaryLUT)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text("Videos: \(project.videoURLs.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Button("Load Project") {
                onLoad()
            }
            .font(.subheadline)
            .fontWeight(.medium)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.blue.opacity(0.1))
            .foregroundColor(.blue)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Recent Project Card
struct RecentProjectCard: View {
    let project: SavedProject
    let recentItem: RecentProjectItem
    let isFavorite: Bool
    let onLoad: () -> Void
    let onFavorite: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            if let thumbnailData = recentItem.thumbnailData,
               let thumbnail = UIImage(data: thumbnailData) {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: "video")
                            .foregroundColor(.secondary)
                    )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(recentItem.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text("Last accessed: \(DateFormatter.recentDateFormatter.string(from: recentItem.lastAccessed))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                Button(action: onFavorite) {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .foregroundColor(isFavorite ? .red : .secondary)
                }
                
                Button("Load") {
                    onLoad()
                }
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .foregroundColor(.blue)
                .clipShape(Capsule())
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Extensions
extension DateFormatter {
    static let projectDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    static let recentDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

// MARK: - Preview
struct ProjectManagementView_Previews: PreviewProvider {
    static var previews: some View {
        ProjectManagementView(
            projectState: ProjectState(),
            lutManager: LUTManager()
        )
    }
} 