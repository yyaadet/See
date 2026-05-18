import AppKit
import CommonCrypto
import Foundation

struct ImageItem: Identifiable, Hashable {
    let url: URL
    let id: UUID
    let fileName: String
    let fileSize: Int64
    var previousId: UUID?
    var nextId: UUID?

    init(url: URL) {
        self.url = url
        self.id = Self.id(for: url)
        self.fileName = url.lastPathComponent

        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        self.fileSize = Int64(values?.fileSize ?? 0)
    }

    private static func id(for url: URL) -> UUID {
        let data = url.absoluteString.data(using: .utf8)!
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        let bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (
            hash[0], hash[1], hash[2], hash[3],
            hash[4], hash[5], hash[6], hash[7],
            hash[8], hash[9], hash[10], hash[11],
            hash[12], hash[13], hash[14], hash[15]
        )
        return UUID(uuid: bytes)
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
