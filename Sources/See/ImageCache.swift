import Foundation
import SQLite

@MainActor
final class ImageCache {
    static let shared = ImageCache()

    private var db: Connection?

    private let table: Table
    private let pathCol: SQLite.Expression<String>
    private let descriptionCol: SQLite.Expression<String?>
    private let explanationCol: SQLite.Expression<String?>
    private let updatedAtCol: SQLite.Expression<Int64>

    init() {
        let docsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbDir = docsDir.appendingPathComponent("See")
        try? FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
        let dbURL = dbDir.appendingPathComponent("cache.db")

        table = Table("image_descriptions")
        pathCol = SQLite.Expression<String>("path")
        descriptionCol = SQLite.Expression<String?>("description")
        explanationCol = SQLite.Expression<String?>("explanation")
        updatedAtCol = SQLite.Expression<Int64>("updated_at")

        do {
            db = try Connection(dbURL.path, readonly: false)
        } catch {
            print("[ImageCache] Failed to open database: \(error)")
        }

        do {
            try db!.run(table.create(ifNotExists: true) { t in
                t.column(pathCol, primaryKey: true)
                t.column(descriptionCol)
                t.column(explanationCol)
                t.column(updatedAtCol, defaultValue: 0)
            })
        } catch {
            print("[ImageCache] Failed to create table: \(error)")
        }
    }

    func hasDescription(for path: String) -> Bool {
        guard let db = db else { return false }
        do {
            let exists = try db.scalar(table.filter(pathCol == path).count) > 0
            return exists
        } catch {
            print("[ImageCache] hasDescription error: \(error)")
            return false
        }
    }

    func description(for path: String) -> String? {
        guard let db = db else { return nil }
        do {
            if let row = try db.pluck(table.filter(pathCol == path).select(descriptionCol)) {
                return row[descriptionCol]
            }
            return nil
        } catch {
            print("[ImageCache] description error: \(error)")
            return nil
        }
    }

    func explanation(for path: String) -> String? {
        guard let db = db else { return nil }
        do {
            if let row = try db.pluck(table.filter(pathCol == path).select(explanationCol)) {
                return row[explanationCol]
            }
            return nil
        } catch {
            print("[ImageCache] explanation error: \(error)")
            return nil
        }
    }

    func saveDescription(_ description: String, for path: String) {
        guard let db = db else { return }
        do {
            let updatedAt = Int64(Date().timeIntervalSince1970)
            try db.run(
                table.insert(or: .replace,
                    pathCol <- path,
                    descriptionCol <- description,
                    updatedAtCol <- updatedAt
                )
            )
        } catch {
            print("[ImageCache] saveDescription error: \(error)")
        }
    }

    func saveExplanation(_ explanation: String, for path: String) {
        guard let db = db else { return }
        do {
            let updatedAt = Int64(Date().timeIntervalSince1970)
            try db.run(
                table.filter(pathCol == path).update(
                    explanationCol <- explanation,
                    updatedAtCol <- updatedAt
                )
            )
        } catch {
            print("[ImageCache] saveExplanation error: \(error)")
        }
    }
}
