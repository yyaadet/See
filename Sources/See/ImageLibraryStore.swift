import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class ImageLibraryStore: ObservableObject {
    @Published private(set) var folderURL: URL?
    @Published private(set) var images: [ImageItem] = []
    @Published var selectedImageID: ImageItem.ID?
    @Published var searchText = ""
    @Published var scanError: String?
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
        images.first { $0.id == selectedImageID }
    }

    var filteredImages: [ImageItem] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return images
        }

        return images.filter { $0.fileName.localizedCaseInsensitiveContains(trimmed) }
    }

    var selectedIndex: Int? {
        guard let selectedImageID else {
            return nil
        }

        return images.firstIndex { $0.id == selectedImageID }
    }

    var canNavigateBackward: Bool {
        guard let selectedIndex else {
            return false
        }

        return selectedIndex > 0
    }

    var canNavigateForward: Bool {
        guard let selectedIndex else {
            return false
        }

        return selectedIndex < images.count - 1
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
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var urls: [URL] = []
        var scannedFileCount = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: resourceKeys)
            guard values?.isRegularFile == true else {
                continue
            }

            scannedFileCount += 1
            if Self._isSupported(url.pathExtension.lowercased(), contentType: values?.contentType) {
                urls.append(url)
            }

            if scannedFileCount == 1 || scannedFileCount.isMultiple(of: 25) {
                progress(scannedFileCount, urls.count)
            }
        }

        if scannedFileCount > 0 {
            progress(scannedFileCount, urls.count)
        }

        return urls.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
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

        self.images = items
        self.isScanning = false
        self.scanProgress = nil
        if self.selectedImageID == nil {
            self.selectedImageID = items.first?.id
        }
    }

    func select(_ item: ImageItem) {
        selectedImageID = item.id
    }

    func selectPrevious() {
        guard canNavigateBackward, let selectedIndex else {
            return
        }

        selectedImageID = images[selectedIndex - 1].id
    }

    func selectNext() {
        guard canNavigateForward, let selectedIndex else {
            return
        }

        selectedImageID = images[selectedIndex + 1].id
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
