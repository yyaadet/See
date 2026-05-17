import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: ImageLibraryStore
    @EnvironmentObject var settings: LLMSettings
    @State private var descriptionText: String?
    @State private var describing = false
    @State private var descriptionError: String?
    @State private var showSettings = false
    @State private var zoom: CGFloat = 1.0
    @State private var cropRegion: CGRect?
    @State private var cropMode = false
    @State private var imageCache = ImageCache()
    @State private var descriptionFontSize: CGFloat = 15.0
     @State private var descriptionVisible = true
    @State private var explanationText: String?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(minWidth: 240, maxWidth: 320)
                .background(Color(NSColor.separatorColor))

            Divider()

            VStack(spacing: 0) {
                toolbarBar
                
                Spacer()

                if let selected = store.selectedImage {
                    imageArea(for: selected)
                        .overlay {
                            if describing {
                                descriptionOverlay
                            } else if let error = descriptionError {
                                errorOverlay(error)
                            } else if descriptionText != nil {
                                descriptionOverlay
                            }
                        }
                } else if store.filteredImages.isEmpty && store.folderURLs.isEmpty {
                    emptyState
                } else if let error = store.scanError {
                    errorState(message: error)
                } else if store.filteredImages.isEmpty {
                    noImagesMessage
                } else {
                    emptyState
                }

                Spacer()

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
        .onChange(of: store.filteredFolder) {
            descriptionText = nil
            descriptionError = nil
        }
        .onChange(of: store.selectedImageID) {
            descriptionText = nil
            descriptionError = nil
            zoom = 1.0
            cropRegion = nil
            cropMode = false
            panOffset = .zero
            descriptionFontSize = 15.0
            descriptionVisible = true
            if let selected = store.selectedImage {
                descriptionText = imageCache.description(for: selected.url.path)
                explanationText = imageCache.explanation(for: selected.url.path)
            }
        }
        .onChange(of: zoom) {
            panOffset = .zero
        }
    }

    // MARK: - Sidebar

    private var sidebarImages: [ImageItem] {
        guard let selected = store.selectedImage,
              let index = store.filteredImages.firstIndex(where: { $0.id == selected.id }) else {
            // selected not in filtered list or no selection — show first 10 of filtered
            return Array(store.filteredImages.prefix(10))
        }

        let start = max(0, index - 5)
        let end = min(store.filteredImages.count, index + 6)
        guard start < end else { return [] }
        return Array(store.filteredImages[start..<end])
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Library")
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.top, 8)

                Spacer()

                Text("(\(store.filteredImages.count))")
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

            if store.folderURLs.isEmpty {
                Text("No folders added")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                FolderTreeNavigator()
            }

            Divider()

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(sidebarImages) { item in
                        thumbnailRow(for: item)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noImagesMessage: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No images in this folder")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Folder Tree Navigator

    private struct FolderTreeNavigator: View {
        @EnvironmentObject var store: ImageLibraryStore
        @State private var expandedFolders: Set<URL> = []

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text("Folders")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)

                // "All" row to clear filter
                Button {
                    store.setFilteredFolder(nil)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: store.filteredFolder == nil ? "folder.fill" : "folder")
                            .font(.caption)
                            .foregroundColor(store.filteredFolder == nil ? .blue : .orange)
                        Text("All")
                            .font(.caption)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
                .foregroundColor(.primary)

                ForEach(store.folderURLs, id: \.self) { url in
                    let node = store.buildDirectoryTree(for: url)
                    FolderTreeNode(node: node, depth: 0, expandedFolders: $expandedFolders)
                }
            }
        }
    }

    private struct FolderTreeNode: View {
        let node: ImageLibraryStore.DirectoryNode
        let depth: Int
        @Binding var expandedFolders: Set<URL>
        @EnvironmentObject var store: ImageLibraryStore

        private var isExpanded: Bool {
            expandedFolders.contains(node.url)
        }

        private var isSelected: Bool {
            store.filteredFolder == node.url
        }

        private var hasSubfolders: Bool {
            !node.children.isEmpty
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 3) {
                    // Chevron for expand/collapse
                    if hasSubfolders {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(width: 12)
                    } else {
                        Spacer().frame(width: 12)
                    }

                    Spacer(minLength: 0)

                    // Folder icon
                    Image(systemName: isSelected ? "folder.fill" : "folder")
                        .font(.caption)
                        .foregroundColor(isSelected ? .blue : .orange)

                    // Folder name
                    Text(node.name)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    // Image count badge
                    Text("\(node.imageCount)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8 + CGFloat(depth * 12))
                .padding(.vertical, 2)
                .contentShape(Rectangle())
                .onTapGesture {
                    if hasSubfolders {
                        toggle()
                    }
                    store.setFilteredFolder(node.url)
                }

                // Expand: show children with animation
                if hasSubfolders && isExpanded {
                    ForEach(node.children, id: \.url) { child in
                        FolderTreeNode(node: child, depth: depth + 1, expandedFolders: $expandedFolders)
                    }
                }
            }
        }

        private func toggle() {
            if isExpanded {
                expandedFolders.remove(node.url)
            } else {
                expandedFolders.insert(node.url)
            }
        }
    }

    // MARK: - Thumbnail

    private func thumbnailRow(for item: ImageItem) -> some View {
        let isSelected = store.selectedImageID == item.id

        return Button(action: {
            store.select(item)
        }, label: {
            ZStack {
                if let nsImage = NSImage(contentsOf: item.url) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 200, height: 140)
                } else {
                    Rectangle()
                        .fill(Color(nsColor: .placeholderTextColor))
                        .frame(width: 200, height: 140)
                }
            }
            .clipped()
            .cornerRadius(4)
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
        .id(item.id)
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
            .keyboardShortcut(.leftArrow, modifiers: .numericPad)

            Text("\(((store.selectedIndex ?? 0) + 1)) / \(store.filteredImages.count)")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize()

            Button {
                store.selectNext()
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!store.canNavigateForward)
            .keyboardShortcut(.rightArrow, modifiers: .numericPad)

            Spacer()

            // Zoom controls
            Button {
                zoom = max(0.1, zoom / 1.25)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .disabled(zoom <= 0.1)
            .keyboardShortcut("-")

            Text("\(Int(zoom * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 48)

            Button {
                zoom = min(5.0, zoom * 1.25)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .disabled(zoom >= 5.0)
            .keyboardShortcut("+")

            Button {
                zoom = 1.0
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(abs(zoom - 1.0) < 0.01)
            .keyboardShortcut("0", modifiers: .command)

            // Crop mode toggle
            Button {
                cropMode.toggle()
                if cropMode {
                    cropRegion = nil
                }
            } label: {
                Image(systemName: cropMode ? "scissors.badge.checkmark" : "scissors")
            }
            .foregroundColor(cropMode ? .blue : .primary)

            // Clear crop
            if cropRegion != nil {
                Button {
                    cropRegion = nil
                    cropMode = false
                    zoom = 1.0
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
            }

            // Export menu
            Menu {
                Button("Export as PNG...") {
                    exportImage(as: .png)
                }
                .disabled(store.selectedImage == nil)

                Button("Export as JPEG...") {
                    exportImage(as: .jpeg)
                }
                .disabled(store.selectedImage == nil)
            } label: {
                Image(systemName: "square.and.arrow.up")
            }

            if store.selectedImage != nil {
                Button("Describe") {
                    Task {
                        await getDescribe()
                    }
                }
                .disabled(describing)

                Button("Explain") {
                    Task {
                        await getExplanation()
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

    @State private var _dragRect: CGRect?
    @State private var panOffset: CGSize = .zero
    @GestureState private var gestureTranslation: CGSize = .zero
    @State private var loadedImage: NSImage?

    private var canPan: Bool {
        zoom > 1.0
    }

    private func imageArea(for item: ImageItem) -> some View {
        GeometryReader { geometry in
            let bounds = geometry.frame(in: .local)

            if let nsImage = loadedImage {
                ZStack {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(zoom)
                        .offset(CGSize(
                            width: panOffset.width + gestureTranslation.width,
                            height: panOffset.height + gestureTranslation.height
                        ))
                        .offset(cropOffset(for: bounds, zoom: zoom))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($gestureTranslation) { value, state, _ in
                            state = value.translation
                        }
                        .onChanged { value in
                            guard !cropMode else { return }
                        }
                        .onEnded { value in
                            panOffset = CGSize(
                                width: panOffset.width + value.translation.width,
                                height: panOffset.height + value.translation.height
                            )
                        }
                )
                .overlay {
                    if canPan {
                        Color.clear
                    }
                }
                .onHover { isHovering in
                    guard canPan else { return }
                    if isHovering {
                        NSCursor.openHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .overlay {
                    if cropMode {
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        self._dragRect = self._rectFrom(value)
                                    }
                                    .onEnded { value in
                                        let rect = self._rectFrom(value)
                                        self._dragRect = nil
                                        if rect.width > 5 && rect.height > 5 {
                                            self.cropRegion = rect
                                            self.zoom = max(bounds.width / rect.width, bounds.height / rect.height)
                                        }
                                    }
                            )
                    }
                }
                .overlay {
                    if let rect = _dragRect, rect.width > 1, rect.height > 1 {
                        GeometryReader { _ in
                            ZStack(alignment: .topLeading) {
                                Rectangle().fill(Color.black.opacity(0.4))
                                Rectangle()
                                    .stroke(Color.white, lineWidth: 2)
                                    .frame(width: rect.width, height: rect.height)
                                    .offset(x: rect.minX, y: rect.minY)
                            }
                        }
                    }
                }
                .transition(.opacity)
            } else {
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading image...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: item.id) {
            loadedImage = NSImage(contentsOf: item.url)
        }
    }

    private func _rectFrom(_ value: DragGesture.Value) -> CGRect {
        let start = value.startLocation
        let end = value.location
        return CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    private func cropOffset(for bounds: CGRect, zoom: CGFloat) -> CGSize {
        guard let region = cropRegion else { return .zero }
        let viewCenterX = bounds.midX
        let viewCenterY = bounds.midY
        let regionCenterX = region.midX
        let regionCenterY = region.midY
        return CGSize(
            width: -(regionCenterX - viewCenterX) / zoom,
            height: -(regionCenterY - viewCenterY) / zoom
        )
    }

    private func navigationStrip(for item: ImageItem) -> some View {
        HStack(spacing: 12) {
            Spacer()

            // Previous thumbnail
            if let prevId = item.previousId,
               let prevItem = store.idImageMap[prevId.uuidString] {
                navThumbnail(for: prevItem, label: "Previous")
                    .onTapGesture {
                        store.select(prevItem)
                    }
            }

            // Next thumbnail
            if let nextId = item.nextId,
               let nextItem = store.idImageMap[nextId.uuidString] {
                navThumbnail(for: nextItem, label: "Next")
                    .onTapGesture {
                        store.select(nextItem)
                    }
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }

    private func navThumbnail(for item: ImageItem, label: String) -> some View {
        Group {
            if let nsImage = NSImage(contentsOf: item.url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 64, height: 64)
            } else {
                Rectangle()
                    .fill(Color(nsColor: .placeholderTextColor))
                    .frame(width: 64, height: 64)
            }
        }
        .clipped()
        .cornerRadius(4)
        .overlay(
            Text(item.fileName.prefix(12) + (item.fileName.count > 12 ? "..." : ""))
                .font(.caption2)
                .foregroundColor(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.6))
                .cornerRadius(3),
            alignment: .bottomTrailing
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
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

    // MARK: - Export

    private enum ExportFormat { case png, jpeg }

    private func exportImage(as format: ExportFormat) {
        guard let selected = store.selectedImage,
              let nsImage = NSImage(contentsOf: selected.url) else { return }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = format == .png ? [.png] : [.jpeg]
        savePanel.nameFieldStringValue = URL(fileURLWithPath: selected.fileName).deletingPathExtension().lastPathComponent + (format == .png ? ".png" : ".jpg")
        savePanel.prompt = "Export"

        guard savePanel.runModal() == .OK, let url = savePanel.url else { return }

        guard let bitmap = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let representation = NSBitmapImageRep(cgImage: bitmap)

        let properties: [NSBitmapImageRep.PropertyKey: Any] = format == .png ? [:] : [
            .compressionFactor: 0.9
        ]

        if let tiffData = representation.representation(using: format == .png ? .png : .jpeg, properties: properties) {
            try? tiffData.write(to: url)
        }
    }

    // MARK: - Description overlay

    private var descriptionOverlay: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top bar with controls
            HStack(spacing: 8) {
                if describing {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Describing...")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                } else {
                    @State var isHovered = false

                    Button {
                        descriptionText = nil
                        explanationText = nil
                        descriptionError = nil
                        Task {
                            await getDescribe()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .font(.body)
                    .help("Regenerate")
                    .buttonStyle(.plain)
                    .background(isHovered ? Color.white.opacity(0.15) : Color.clear)
                    .cornerRadius(4)
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isHovered = hovering
                        }
                    }

                    @State var isHoveredMinus = false

                    Button {
                        descriptionFontSize = max(8, descriptionFontSize - 1)
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .font(.body)
                    .help("Decrease text size")
                    .buttonStyle(.plain)
                    .background(isHoveredMinus ? Color.white.opacity(0.15) : Color.clear)
                    .cornerRadius(4)
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isHoveredMinus = hovering
                        }
                    }

                    Text("\(Int(descriptionFontSize))")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .fixedSize()

                    @State var isHoveredPlus = false

                    Button {
                        descriptionFontSize = min(36, descriptionFontSize + 1)
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .font(.body)
                    .help("Increase text size")
                    .buttonStyle(.plain)
                    .background(isHoveredPlus ? Color.white.opacity(0.15) : Color.clear)
                    .cornerRadius(4)
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isHoveredPlus = hovering
                        }
                    }

                    @State var isHoveredEye = false

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            descriptionVisible.toggle()
                        }
                    } label: {
                        Image(systemName: descriptionVisible ? "eye.slash" : "eye")
                    }
                    .font(.body)
                    .help(descriptionVisible ? "Hide description" : "Show description")
                    .buttonStyle(.plain)
                    .background(isHoveredEye ? Color.white.opacity(0.15) : Color.clear)
                    .cornerRadius(4)
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isHoveredEye = hovering
                        }
                    }

                    Spacer()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.5))
            .cornerRadius(8)
            .padding(.top, 8)
            .padding(.leading, 12)
            .frame(maxWidth: 320)

            // Description text
            if descriptionVisible {
                if let text = descriptionText, !describing {
                    MarkdownText(text: text, fontSize: descriptionFontSize, textColor: NSColor.labelColor)
                        .frame(maxWidth: 350, maxHeight: .infinity, alignment: .leading)
                        .padding(.leading, 12)
                }
                if let text = explanationText, !describing {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Explanation")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                        MarkdownText(text: text, fontSize: descriptionFontSize, textColor: NSColor.systemPurple)
                            .frame(maxWidth: 350, maxHeight: .infinity, alignment: .leading)
                            .padding(.leading, 12)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func errorOverlay(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text(error)
                    .font(.body)
                    .foregroundColor(.white)
                    .lineLimit(3)
                Spacer()
                Button("Retry") {
                    Task {
                        await getDescribe()
                    }
                }
                .font(.caption2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.6))
            .cornerRadius(8)
            .padding(.top, 12)
            .padding(.leading, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - LLM actions

    private func getDescribe() async {
        guard let selected = store.selectedImage else { return }

        if imageCache.hasDescription(for: selected.url.path) {
            descriptionText = imageCache.description(for: selected.url.path)
            explanationText = imageCache.explanation(for: selected.url.path)
            return
        }

        describing = true

        let descript = ImageDescriber(settings: settings, cache: imageCache)
        do {
            let text = try await descript.describe(imageURL: selected.url)
            descriptionText = text
            explanationText = nil
        } catch {
            descriptionError = error.localizedDescription
        }
        describing = false
    }

    private func getExplanation() async {
        guard let selected = store.selectedImage else { return }

        describing = true
        descriptionError = nil

        let descript = ImageDescriber(settings: settings, cache: imageCache)
        do {
            let explanation = try await descript.explain(imageURL: selected.url)
            await MainActor.run {
                self.explanationText = explanation
                self.describing = false
            }
        } catch {
            await MainActor.run {
                self.descriptionError = error.localizedDescription
                self.describing = false
            }
        }
    }
}

extension String {
    func truncated(to max: Int) -> String {
        count <= max ? self : String(prefix(max - 3)) + "..."
    }
}

// MARK: - MarkdownText

struct MarkdownText: View {
    let text: String
    let fontSize: CGFloat
    let textColor: NSColor

    var body: some View {
        MarkdownTextView(text: text, fontSize: fontSize, textColor: textColor)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MarkdownTextView: NSViewRepresentable {
    let text: String
    let fontSize: CGFloat
    let textColor: NSColor

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.contentView.clipsToBounds = true

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = true
        textView.font = NSFont.systemFont(ofSize: fontSize)
        textView.textColor = textColor
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.textContainer?.lineFragmentPadding = 0
        scrollView.documentView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = scrollView.documentView as? NSTextView
        guard let textView else { return }
        textView.font = NSFont.systemFont(ofSize: fontSize)
        textView.textColor = textColor
        let attr = renderMarkdown(text)
        textView.textStorage?.setAttributedString(attr)
    }

    private func renderMarkdown(_ text: String) -> NSAttributedString {
        let attr = markdownToNSAttributedString(text)
        guard let attr else { return NSAttributedString(string: text) }
        let result = NSMutableAttributedString(attributedString: attr)
        result.addAttribute(NSAttributedString.Key.font, value: NSFont.systemFont(ofSize: fontSize), range: NSRange(location: 0, length: result.length))
        result.addAttribute(NSAttributedString.Key.foregroundColor, value: textColor, range: NSRange(location: 0, length: result.length))
        result.addAttribute(NSAttributedString.Key.backgroundColor, value: NSColor.white.withAlphaComponent(0.08), range: NSRange(location: 0, length: result.length))
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.paragraphSpacing = 12
        result.addAttribute(NSAttributedString.Key.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: result.length))
        return result
    }
}
