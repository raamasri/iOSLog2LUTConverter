import SwiftUI
import UniformTypeIdentifiers

struct BatchProcessingView: View {
    @ObservedObject var projectState: ProjectState
    @State private var showingFilePicker = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            headerSection
            
            // Queue Management
            queueSection
            
            // Progress Section
            if projectState.isBatchProcessing {
                progressSection
            }
            
            // Controls
            controlsSection
            
            Spacer()
        }
        .padding()
        .navigationTitle("Batch Processing")
        .navigationBarTitleDisplayMode(.large)
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.movie, .video],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
        .alert("Batch Processing", isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "square.stack.3d.up")
                    .font(.title2)
                    .foregroundStyle(.blue)
                
                Text("Batch Processing")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            Text(projectState.batchProcessingStatusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(Color.gray.opacity(0.2))
        .cornerRadius(12)
    }
    
    // MARK: - Queue Section
    private var queueSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Video Queue")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("\(projectState.batchQueue.count) videos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if projectState.batchQueue.isEmpty {
                emptyQueueView
            } else {
                queueListView
            }
        }
    }
    
    private var emptyQueueView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("No videos in queue")
                .font(.title3)
                .foregroundStyle(.secondary)
            
            Text("Add videos to start batch processing")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(Color.gray.opacity(0.2))
        .cornerRadius(12)
    }
    
    private var queueListView: some View {
        List {
            ForEach(0..<projectState.batchQueue.count, id: \.self) { index in
                BatchVideoItemView(item: projectState.batchQueue[index], index: index) {
                    projectState.removeVideoFromBatch(at: index)
                }
            }
            .onMove { source, destination in
                projectState.reorderBatchQueue(from: source, to: destination)
            }
        }
        .frame(maxHeight: 300)
        .listStyle(PlainListStyle())
    }
    
    // MARK: - Progress Section
    private var progressSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Processing Progress")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("\(Int(projectState.batchProgress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            ProgressView(value: projectState.batchProgress)
                .progressViewStyle(LinearProgressViewStyle())
                .scaleEffect(y: 2)
            
            Text(projectState.batchProcessingStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(Color.gray.opacity(0.2))
        .cornerRadius(12)
    }
    
    // MARK: - Controls Section
    private var controlsSection: some View {
        HStack(spacing: 12) {
            // Add Videos Button
            Button(action: {
                showingFilePicker = true
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Videos")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .cornerRadius(12)
            }
            .disabled(projectState.isBatchProcessing)
            
            // Clear Queue Button
            Button(action: {
                projectState.clearBatchQueue()
            }) {
                HStack {
                    Image(systemName: "trash.circle.fill")
                    Text("Clear")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red)
                .cornerRadius(12)
            }
            .disabled(projectState.isBatchProcessing || projectState.batchQueue.isEmpty)
        }
    }
    
    // MARK: - Helper Methods
    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            projectState.addVideosToBatch(urls)
            alertMessage = "Added \(urls.count) videos to batch queue"
            showingAlert = true
        case .failure(let error):
            alertMessage = "Failed to import videos: \(error.localizedDescription)"
            showingAlert = true
        }
    }
}

// MARK: - Batch Video Item View
struct BatchVideoItemView: View {
    let item: ProjectState.BatchVideoItem
    let index: Int
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Status Icon
            statusIcon
            
            // Video Info
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.headline)
                    .lineLimit(1)
                
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Progress
            if item.status == .processing {
                VStack(spacing: 4) {
                    ProgressView(value: item.progress)
                        .frame(width: 60)
                    
                    Text("\(Int(item.progress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Remove Button
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.title3)
            }
            .disabled(item.status == .processing)
        }
        .padding(.vertical, 8)
    }
    
    private var statusIcon: some View {
        Group {
            switch item.status {
            case .pending:
                Image(systemName: "clock")
                    .foregroundStyle(.orange)
            case .processing:
                Image(systemName: "gearshape.2")
                    .foregroundStyle(.blue)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
        .font(.title3)
    }
    
    private var statusText: String {
        switch item.status {
        case .pending:
            return "Waiting to process"
        case .processing:
            return "Processing..."
        case .completed:
            return "Completed successfully"
        case .failed:
            return item.errorMessage ?? "Processing failed"
        }
    }
}

// MARK: - Preview
struct BatchProcessingView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            BatchProcessingView(projectState: ProjectState())
        }
    }
} 