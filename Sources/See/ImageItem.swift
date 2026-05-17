import AppKit
import Foundation

struct ImageItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let fileName: String
    let fileSize: Int64
    var previousId: UUID?
    var nextId: UUID?

    init(url: URL) {
        self.url = url
        self.fileName = url.lastPathComponent

        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        self.fileSize = Int64(values?.fileSize ?? 0)
    }

    var pixelSize: CGSize? {
        // Lazy load: only compute when first accessed
        if let image = NSImage(contentsOf: url) {
            return image.pixelSize
        }
        return nil
    }

    var displaySize: String {
        guard let pixelSize else {
            return "Unknown size"
        }

        return "\(Int(pixelSize.width)) x \(Int(pixelSize.height))"
    }

    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var fullPath: String {
        url.path
    }
}

extension NSImage {
    var pixelSize: CGSize {
        if let bitmap = representations.compactMap({ $0 as? NSBitmapImageRep }).first {
            return CGSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        }

        return size
    }
}
