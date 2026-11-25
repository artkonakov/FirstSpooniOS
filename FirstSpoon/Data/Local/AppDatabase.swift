import Foundation
import GRDB

/// Локальная БД (`first_spoon.sqlite`, GRDB/SQLite). Схема пользовательских таблиц — та же, что у Room в Android
/// (`ARCHITECTURE.md` Android-проекта), чтобы синхронизация работала одинаково на обеих платформах:
/// - `id` — UUID-строка (`newId()`), не автоинкремент;
/// - в каждой таблице `created_at`, `updated_at`, `deleted_at` (epoch millis UTC); любое изменение обновляет `updated_at`;
/// - удаление **мягкое** (`deleted_at`), все чтения фильтруют `deleted_at IS NULL`; жёстко стирает только `clearUserData()`;
/// - `entries.product_id` — slug каталога **или** id из `custom_products`, без FK.
/// Каталог в БД не хранится: он read-only и читается из `catalog.json` (`CatalogRepository`).
///
/// Любое изменение схемы — новая миграция в `migrator` (старые не править).
final class AppDatabase {
    let dbQueue: DatabaseQueue

    init(_ dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        try Self.migrator.migrate(dbQueue)
    }

    /// БД приложения в Application Support. Исключена из резервной копии, как в Android (`allowBackup=false`):
    /// токены живут в Keychain только на этом устройстве, а дневник без сессии из бэкапа восстанавливать нельзя.
    static func makeShared() throws -> AppDatabase {
        let fm = FileManager.default
        var dir = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        dir.appendPathComponent("first_spoon.sqlite")
        var config = Configuration()
        config.foreignKeysEnabled = true
        return try AppDatabase(DatabaseQueue(path: dir.path, configuration: config))
    }

    /// БД в памяти — для тестов и превью.
    static func inMemory() throws -> AppDatabase {
        var config = Configuration()
        config.foreignKeysEnabled = true
        return try AppDatabase(DatabaseQueue(configuration: config))
    }

    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "children") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("birth_date", .text)           // ISO yyyy-MM-dd
                t.column("sex", .text)                  // Sex.rawValue
                t.column("profile", .text).notNull().defaults(to: "{}") // JSON ключ вопроса → ответ
                t.column("created_at", .integer).notNull()
                t.column("updated_at", .integer).notNull()
                t.column("deleted_at", .integer)
            }
            try db.create(table: "custom_products") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("category_id", .text)
                t.column("allergen_ids", .text).notNull().defaults(to: "[]") // JSON
                t.column("created_at", .integer).notNull()
                t.column("updated_at", .integer).notNull()
                t.column("deleted_at", .integer)
            }
            try db.create(table: "entries") { t in
                t.primaryKey("id", .text)
                t.column("child_id", .text).notNull().references("children", onDelete: .cascade)
                t.column("product_id", .text).notNull()
                t.column("date", .text).notNull()       // локальная дата yyyy-MM-dd
                t.column("time", .text)                 // HH:mm
                t.column("meal", .text)
                t.column("amount", .text)
                t.column("reaction", .text).notNull().defaults(to: "unknown")
                t.column("symptoms", .text).notNull().defaults(to: "[]") // JSON-список кодов
                t.column("note", .text)
                t.column("created_at", .integer).notNull()
                t.column("updated_at", .integer).notNull()
                t.column("deleted_at", .integer)
            }
            try db.create(index: "index_entries_child_id_date", on: "entries", columns: ["child_id", "date"])
            try db.create(index: "index_entries_child_id_product_id", on: "entries", columns: ["child_id", "product_id"])
            try db.create(table: "child_products") { t in
                t.column("child_id", .text).notNull().references("children", onDelete: .cascade)
                t.column("product_id", .text).notNull()
                t.column("status", .text)               // ProductMark.rawValue или NULL
                t.column("liked", .boolean).notNull().defaults(to: false)
                t.column("note", .text)
                t.column("created_at", .integer).notNull()
                t.column("updated_at", .integer).notNull()
                t.column("deleted_at", .integer)
                t.primaryKey(["child_id", "product_id"])
            }
        }
        // Фото ребёнка и своего продукта: имя файла в Application Support/photos (только на устройстве, не синхронизируется).
        m.registerMigration("v2_photos") { db in
            try db.alter(table: "children") { t in t.add(column: "photo", .text) }
            try db.alter(table: "custom_products") { t in t.add(column: "photo", .text) }
        }
        // Фото пробы: JSON-список имён файлов по порядку (только на устройстве, не синхронизируются).
        m.registerMigration("v3_entry_photos") { db in
            try db.alter(table: "entries") { t in t.add(column: "photos", .text).notNull().defaults(to: "[]") }
        }
        m.registerMigration("v4_assistant_chats") { db in
            try db.create(table: "assistant_chats") { t in
                t.primaryKey("id", .text)
                t.column("child_id", .text).notNull().references("children", onDelete: .cascade)
                t.column("owner_id", .text).notNull()
                t.column("product_id", .text)
                t.column("product_name", .text)
                t.column("title", .text).notNull()
                t.column("updated_at", .integer).notNull()
            }
            try db.create(index: "assistant_chats_scope", on: "assistant_chats", columns: ["child_id", "owner_id", "updated_at"])
            try db.create(table: "assistant_turns") { t in
                t.primaryKey("id", .text)
                t.column("chat_id", .text).notNull().references("assistant_chats", onDelete: .cascade)
                t.column("request_id", .text).notNull()
                t.column("question", .text).notNull()
                t.column("context", .blob).notNull()
                t.column("reply", .blob)
                t.column("failure", .text)
            }
            try db.create(index: "assistant_turns_chat", on: "assistant_turns", columns: ["chat_id"])
        }
        m.registerMigration("v5_diary_sync") { db in
            try db.execute(sql: "CREATE TABLE diary_sync_local (owner TEXT PRIMARY KEY NOT NULL, payload TEXT NOT NULL)")
        }
        m.registerMigration("v6_assistant_reply_actions") { db in
            try db.alter(table: "assistant_turns") { table in
                table.add(column: "stopped", .boolean).notNull().defaults(to: false)
                table.add(column: "feedback", .boolean)
                table.add(column: "replied_at", .integer)
            }
        }
        return m
    }

    /// Все имена файлов фото, на которые ссылается БД (дети, свои продукты, пробы).
    func referencedPhotos() -> Set<String> {
        (try? dbQueue.read { db -> Set<String> in
            var names = Set(try String.fetchAll(db, sql: "SELECT photo FROM children WHERE photo IS NOT NULL"))
            names.formUnion(try String.fetchAll(db, sql: "SELECT photo FROM custom_products WHERE photo IS NOT NULL"))
            for json in try String.fetchAll(db, sql: "SELECT photos FROM entries WHERE photos != '[]'") {
                names.formUnion((try? JSONDecoder().decode([String].self, from: Data(json.utf8))) ?? [])
            }
            return names
        }) ?? []
    }

    /// Жёстко стереть данные пользователя (выход, удаление аккаунта, вход в чужой аккаунт).
    func clearUserData() throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM diary_sync_local; DELETE FROM entries; DELETE FROM child_products; DELETE FROM children; DELETE FROM custom_products;")
        }
    }
}

/// Текущее время в epoch millis UTC — для служебных меток.
func nowMillis() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
