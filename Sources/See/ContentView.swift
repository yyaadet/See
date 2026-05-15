import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: ImageLibraryStore
    @EnvironmentObject var settings: LLMSettings
    @State private var descriptionText: String?
    @State private var describing = false
    @State private var descriptionError: String?
    @State private var showSettings = false
    @State private var folderRows: [FolderRow] = []

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 240)
                .background(Color(NSColor.separatorColor))

            Divider()

            VStack(spacing: 0) {
                toolbarBar

                if let selected = store.selectedImage {
                    imageArea(for: selected)
                } else if store.images.isEmpty && store.folderURL == nil {
                    emptyState
                } else if let error = store.scanError {
                    errorState(message: error)
                } else {
                    emptyState
                }

                statusBar
            }
            .overlay(alignment: .center) {
                if store.isScanning {
                    scanningOverlay
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("Add Folder") {
                    store.chooseFolder()
                }
            }

            ToolbarItem(placement: .navigation) {
                Button("Settings") {
                    showSettings = true
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(settings)
        }
        .onAppear {
            folderRows = store.folderURLs.map(FolderRow.init)
        }
        .onChange(of: store.folderURLs) {
            folderRows = store.folderURLs.map(FolderRow.init)
        }
        .onChange(of: store.selectedImageID) {
            descriptionText = nil
            descriptionError = nil
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Library")
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.top, 8)

                Spacer()

                Text("(\(store.images.count))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.trailing, 8)
                    .padding(.top, 8)
            }

            TextField("Search", text: $store.searchText)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .padding(.horizontal, 8)
                .padding(.top, 4)

            Divider()

            SectionView(title: "Folders") {
                if store.folderURLs.isEmpty {
                    Text("No folders added")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                } else {
                    ForEach(Array(folderRows.enumerated()), id: \.element.id) { _, row in
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.caption)
                                .foregroundColor(.orange)

                            Text(row.name)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Spacer()

                            Button {
                                store.removeFolder(row.url)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .opacity(0.6)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                    }
                }
            }

            Divider()

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(store.filteredImages) { item in
                        thumbnailRow(for: item)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func SectionView<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 8)
                .padding(.top, 8)

            content()
        }
    }

    private func thumbnailRow(for item: ImageItem) -> some View {
        let isSelected = store.selectedImageID == item.id

        return Button(action: {
            store.select(item)
        }, label: {
            thumbnailView(for: item)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                        .cornerRadius(4)
                )
        })
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.blue.opacity(0.15) : Color.clear)
    }

    private func thumbnailView(for item: ImageItem) -> some View {
        AsyncImage(url: item.url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 200, height: 140)
                    .clipped()
                    .cornerRadius(4)
            case .failure:
                placeholderView
            case .empty:
                placeholderView
            @unknown default:
                placeholderView
            }
        }
        .frame(width: 200, height: 140)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var placeholderView: some View {
        Rectangle()
            .fill(Color(nsColor: .placeholderTextColor))
            .frame(width: 200, height: 140)
            .cornerRadius(4)
    }

    // MARK: - Toolbar bar

    private var toolbarBar: some View {
        HStack(spacing: 12) {
            Button {
                store.selectPrevious()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!store.canNavigateBackward)
            .keyboardShortcut(.leftArrow)

            Text("\(((store.selectedIndex ?? 0) + 1)) / \(store.images.count)")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize()

            Button {
                store.selectNext()
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!store.canNavigateForward)
            .keyboardShortcut(.rightArrow)

            Spacer()

            if store.selectedImage != nil, descriptionText != nil {
                Button("Explain") {
                    Task {
                        await getExplanation()
                    }
                }
                .disabled(describing)
            } else if store.selectedImage != nil {
                Button("Describe") {
                    Task {
                        await getDescribe()
                    }
                }
                .disabled(describing)
            }

            Button {
                if describing {
                    describing = false
                }
            } label: {
                Image(systemName: "xmark")
            }
            .disabled(!describing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Image area

    private func imageArea(for item: ImageItem) -> some View {
        return VStack(spacing: 0) {
            AsyncImage(url: item.url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if store.canNavigateForward {
                                store.selectNext()
                            }
                        }
                        .transition(.opacity)
                case .failure:
                    failedPlaceholder
                case .empty:
                    loadingPlaceholder
                @unknown default:
                    loadingPlaceholder
                }
            }
            .transition(.opacity)

            Divider()

            if let desc = descriptionText {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Description")
                        .font(.headline)
                        .font(.system(.caption, design: .serif))
                    Text(desc)
                        .font(.subheadline)
                        .textSelection(.enabled)
                    if let err = descriptionError {
                        Text(err)
                            .font(.subheadline)
                            .foregroundColor(.red)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .underPageBackgroundColor))
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var scanningOverlay: some View {
        VStack(spacing: 12) {
            ProgressView()
            if let progress = store.scanProgress {
                Text("Scanning \(progress.folderName)")
                    .font(.caption)
                    .fontWeight(.medium)

                Text("\(progress.scannedFileCount) files scanned, \(progress.foundImageCount) images found")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Scanning for images...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.9))
        .cornerRadius(8)
        .shadow(radius: 12)
    }

    private var failedPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("Cannot load image")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }

    private var loadingPlaceholder: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
    }

    // MARK: - Empty & error states

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            Text("Add a folder to start viewing images")
                .font(.title2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text("Failed to scan folder")
                .font(.title2)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack {
            if let selected = store.selectedImage {
                Text(selected.fullPath)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(selected.formattedFileSize)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let px = selected.pixelSize {
                    Text("\(Int(px.width)) x \(Int(px.height))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - LLM actions

    private func getDescribe() async {
        guard let selected = store.selectedImage else { return }

        describing = true

        let descript = ImageDescriber(settings: settings)
        do {
            let text = try await descript.describe(imageURL: selected.url)
            descriptionText = text
        } catch {
            descriptionError = error.localizedDescription
        }
        describing = false
    }

    private func getExplanation() async {
        guard let selected = store.selectedImage,
              let currentDesc = descriptionText else { return }

        describing = true
        descriptionError = nil

        let descript = ImageDescriber(settings: settings)
        do {
            let message = """
            I already have a description of this image:
            \(currentDesc)

            Please explain this image in more detail. What is the context, mood, and story behind it?
            Respond in the same language as the original description.
            """

            let text = try await descript.describe(imageURL: selected.url, prompt: message)
            await MainActor.run {
                self.descriptionText = currentDesc + "\n\n**Explanation:**\n" + text
                self.describing = false
            }
        } catch {
            await MainActor.run {
                self.descriptionText = currentDesc
                self.descriptionError = error.localizedDescription
                self.describing = false
            }
        }
    }
}

private struct FolderRow: Identifiable {
    let id: UUID = UUID()
    let url: URL
    let name: String

    init(_ url: URL) {
        self.url = url
        self.name = url.lastPathComponent
    }
}
