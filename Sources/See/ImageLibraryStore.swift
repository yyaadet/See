import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class ImageLibraryStore: ObservableObject {
    @Published private(set) var folderURL: URL?
    @Published private(set) var images: [ImageItem] = []
    @Published var idImageMap: [String: ImageItem] = [:]
    @Published var selectedImageID: ImageItem.ID?
    @Published var searchText = ""
    @Published var scanError: String?
    @Published var filteredFolder: URL?
    @Published var filteredImages: [ImageItem] = []
    @Published var folderURLs: [URL] = []
    @Published var isScanning = false
    @Published private(set) var scanProgress: ScanProgress?

    private let supportedExtensions = Set(["jpg", "jpeg", "png", "gif", "heic", "heif", "tif", "tiff", "bmp", "webp"])

    init() {
        loadFolders()
        for url in folderURLs {
            scan(folder: url)
        }
    }

    private func loadFolders() {
        if let urls = UserDefaults.standard.array(forKey: Keys.folderURLs) as? [String] {
            folderURLs = urls.compactMap { URL(string: $0) }
        }
    }

    private func saveFolders() {
        UserDefaults.standard.set(folderURLs.map { $0.absoluteString }, forKey: Keys.folderURLs)
    }

    var selectedImage: ImageItem? {
        idImageMap[selectedImageID?.uuidString ?? ""]
    }

    var selectedIndex: Int? {
        guard let selectedImageID else {
            return nil
        }

        return filteredImages.firstIndex { $0.id == selectedImageID }
    }

    var canNavigateBackward: Bool {
        guard let selectedImage = idImageMap[selectedImageID?.uuidString ?? ""] else {
            return false
        }

        return selectedImage.previousId != nil
    }

    var canNavigateForward: Bool {
        guard let selectedImage = idImageMap[selectedImageID?.uuidString ?? ""] else {
            return false
        }

        return selectedImage.nextId != nil
    }
    
    func updateFilteredImages() {
        var result = images

        if let folder = filteredFolder {
            result = result.filter { $0.url.path.hasPrefix(folder.path) }
        }

        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            result = result.filter { $0.fileName.localizedCaseInsensitiveContains(trimmed) }
        }

        self.filteredImages = result
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Folder"
        panel.message = "Choose a folder to scan for images."

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        addFolder(url)
    }

    func addFolder(_ url: URL) {
        if !folderURLs.contains(url) {
            folderURLs.append(url)
            saveFolders()
        }
        scan(folder: url)
    }

    func removeFolder(_ url: URL) {
        folderURLs.removeAll { $0 == url }
        saveFolders()
    }

    func rescanAll() {
        for url in folderURLs {
            scan(folder: url)
        }
    }

    func scan(folder: URL) {
        folderURL = folder
        scanError = nil
        isScanning = true
        scanProgress = ScanProgress(folderName: folder.lastPathComponent, scannedFileCount: 0, foundImageCount: 0)

        Task.detached { [weak self] in
            guard let self else { return }
            let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .contentTypeKey, .localizedNameKey]
            let urls = Self._scanFolder(folder, resourceKeys: resourceKeys) { scannedFileCount, foundImageCount in
                Task { @MainActor in
                    self.updateScanProgress(
                        folder: folder,
                        scannedFileCount: scannedFileCount,
                        foundImageCount: foundImageCount
                    )
                }
            }
            let items = urls.map(ImageItem.init(url:))
            await self.finishScan(items, for: folder)
        }
    }

    private nonisolated static func _scanFolder(
        _ folder: URL,
        resourceKeys: Set<URLResourceKey>,
        progress: @escaping @Sendable (_ scannedFileCount: Int, _ foundImageCount: Int) -> Void
    ) -> [URL] {
        var queue: [URL] = [folder]
        var imageUrls: [URL] = []
        var scannedFileCount = 0

        while !queue.isEmpty {
            let current = queue.removeFirst()
            guard let entries = try? FileManager.default.contentsOfDirectory(at: current, includingPropertiesForKeys: nil).filter({ !$0.lastPathComponent.hasPrefix(".") }) else {
                continue
            }

            var subdirs: [URL] = []
            for entry in entries {
                let values = try? entry.resourceValues(forKeys: resourceKeys)
                if entry.hasDirectoryPath {
                    subdirs.append(entry)
                } else if values?.isRegularFile == true {
                    scannedFileCount += 1
                    if Self._isSupported(entry.pathExtension.lowercased(), contentType: values?.contentType) {
                        imageUrls.append(entry)
                    }
                    if scannedFileCount == 1 || scannedFileCount.isMultiple(of: 25) {
                        progress(scannedFileCount, imageUrls.count)
                    }
                }
            }

            queue.append(contentsOf: subdirs.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending })
        }

        if scannedFileCount > 0 {
            progress(scannedFileCount, imageUrls.count)
        }

        return imageUrls
    }

    private func updateScanProgress(folder: URL, scannedFileCount: Int, foundImageCount: Int) {
        guard folderURL == folder, isScanning else {
            return
        }

        scanProgress = ScanProgress(
            folderName: folder.lastPathComponent,
            scannedFileCount: scannedFileCount,
            foundImageCount: foundImageCount
        )
    }

    private nonisolated static func _isSupported(_ ext: String, contentType: UTType?) -> Bool {
        if contentType?.conforms(to: .image) == true {
            return true
        }
        return supportedExts.contains(ext)
    }

    private nonisolated static let supportedExts = Set(["jpg", "jpeg", "png", "gif", "heic", "heif", "tif", "tiff", "bmp", "webp"])

    func finishScan(_ items: [ImageItem], for folder: URL) {
        guard folderURL == folder else {
            return
        }

        var linked = items
        for i in 0..<linked.count {
            linked[i].previousId = (i > 0) ? linked[i - 1].id : nil
            linked[i].nextId = (i < linked.count - 1) ? linked[i + 1].id : nil
            self.idImageMap[linked[i].id.uuidString] = linked[i]
        }

        self.images = linked
        self.filteredImages = images
        self.isScanning = false
        self.scanProgress = nil
        if self.selectedImageID == nil {
            self.selectedImageID = linked.first?.id
        }
    }

    func select(_ item: ImageItem) {
        selectedImageID = item.id
    }

    func setFilteredFolder(_ url: URL?) {
        filteredFolder = url
        updateFilteredImages()
        if !filteredImages.isEmpty {
            selectedImageID = filteredImages[0].id
        }
    }

    struct DirectoryNode {
        let url: URL
        let name: String
        let children: [DirectoryNode]
        let imageCount: Int
    }

    func buildDirectoryTree(for rootURL: URL) -> DirectoryNode {
        let (subdirs, directImages) = collectDirectoriesAndImages(under: rootURL)
        let children = subdirs.map { buildDirectoryTree(for: $0) }
        return DirectoryNode(url: rootURL, name: rootURL.lastPathComponent, children: children, imageCount: directImages)
    }

    private func collectDirectoriesAndImages(under url: URL) -> (subdirs: [URL], imageCount: Int) {
        var subdirs: [URL] = []
        var imageCount = 0

        do {
            let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            for item in contents {
                if item.hasDirectoryPath {
                    subdirs.append(item)
                } else if Self._isSupported(item.pathExtension.lowercased(), contentType: nil) {
                    imageCount += 1
                }
            }
        } catch {
            return ([], 0)
        }

        return (subdirs.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }, imageCount)
    }

    func selectPrevious() {
        guard canNavigateBackward else {
            return
        }
        
        if let current = idImageMap[selectedImageID!.uuidString] {
            if current.previousId == nil {
                return
            }
            selectedImageID = idImageMap[current.previousId!.uuidString]!.id
        }

    }

    func selectNext() {
        guard canNavigateForward else {
            return
        }
        
        if let current = idImageMap[selectedImageID!.uuidString] {
            if current.nextId == nil {
                return
            }
            selectedImageID = idImageMap[current.nextId!.uuidString]!.id
        }

    }

    private enum Keys {
        static let folderURLs = "see.folderURLs"
    }
}

struct ScanProgress {
    let folderName: String
    let scannedFileCount: Int
    let foundImageCount: Int
}
