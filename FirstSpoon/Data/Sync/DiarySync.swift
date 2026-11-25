import BackgroundTasks
import FirstSpoonCore
import Foundation
import Network
import GRDB
import Observation

private typealias SyncRows = [String: [String: String]]

private struct SyncChange: Encodable {
    var key: String
    var before: [String: String]?
    var row: [String: String]
}

private struct SyncRequest: Encodable {
    var owner: String
    var action: String
    var epoch: String?
    var changes: [SyncChange]
    let version = 1
}

private struct SyncReply: Decodable {
    var enabled: Bool
    var epoch: String?
    var records: SyncRows?
    var conflicts: [String]?
}

private struct SyncLocal: Codable {
    var epoch: String?
    var baseline: SyncRows = [:]
    var conflicts: [String] = []
    var pendingDisable = false
    var lastSync: Date?
}

private struct SyncTable {
    var name: String
    var keys: [String]
    var fields: String
    var columns: [String] { fields.split(separator: " ").map(String.init) + ["created_at", "updated_at", "deleted_at"] }
}

private let syncTables = [
    SyncTable(name: "children", keys: ["id"], fields: "id name birth_date sex profile"),
    SyncTable(name: "custom_products", keys: ["id"], fields: "id name category_id allergen_ids"),
    SyncTable(name: "entries", keys: ["id"], fields: "id child_id product_id date time meal amount reaction symptoms note"),
    SyncTable(name: "child_products", keys: ["child_id", "product_id"], fields: "child_id product_id status liked note"),
]

@MainActor @Observable
final class DiarySync {
    private(set) var enabled = false
    private(set) var joined = false
    private(set) var busy = false
    private(set) var pendingDisable = false
    private(set) var conflicts = false
    private(set) var failed = false
    private(set) var lastSync: Date?
    @ObservationIgnored private let db: AppDatabase
    @ObservationIgnored private let api: ApiClient
    @ObservationIgnored private let tokens: TokenStore
    @ObservationIgnored private let restored: () -> Void
    @ObservationIgnored private let changed: () -> Void
    @ObservationIgnored private var scheduled: Task<Void, Never>?
    @ObservationIgnored private let reachability = NWPathMonitor()
    static let backgroundIdentifier = (Bundle.main.bundleIdentifier ?? "app.littlebite") + ".diary-sync"

    init(db: AppDatabase, api: ApiClient, tokens: TokenStore, restored: @escaping () -> Void, changed: @escaping () -> Void) {
        self.db = db
        self.api = api
        self.tokens = tokens
        self.restored = restored
        self.changed = changed
        reachability.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in self?.schedule() }
        }
        reachability.start(queue: DispatchQueue(label: "app.littlebite.diary-sync-network"))
    }

    func refresh() async { await run("refresh") }
    func enable() async { await run("enable") }
    func disable() async { await run("disable") }
    func resolve(useCloud: Bool) async { await run(useCloud ? "cloud" : "local") }

    func scheduleBackground() {
        guard joined || pendingDisable else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    func schedule() {
        scheduled?.cancel()
        scheduled = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(750))
            if !Task.isCancelled { await self?.refresh() }
        }
    }

    private func run(_ action: String) async {
        guard let owner = tokens.userId, tokens.email != nil else {
            enabled = false
            joined = false
            conflicts = false
            pendingDisable = false
            failed = false
            lastSync = nil
            return
        }
        guard !busy else { return }
        busy = true
        failed = false
        defer { busy = false }
        func requireOwner() throws {
            if tokens.userId != owner { throw CancellationError() }
        }
        func publish(_ local: SyncLocal) {
            joined = local.epoch != nil
            conflicts = !local.conflicts.isEmpty
            pendingDisable = local.pendingDisable
            lastSync = local.lastSync
        }
        do {
            var local = try read { try Self.readLocal($0, owner: owner) }
            publish(local)
            if action == "disable" {
                guard local.epoch != nil else { return }
                local.pendingDisable = true
                try write { try Self.writeLocal($0, owner: owner, value: local) }
                publish(local)
            }
            let remote = try await call(owner, "status")
            try requireOwner()
            enabled = remote.enabled
            if local.pendingDisable && (!remote.enabled || remote.epoch != local.epoch) {
                try write { try Self.writeLocal($0, owner: owner, value: SyncLocal()) }
                publish(SyncLocal())
                return
            }
            if (action == "disable" || local.pendingDisable) && remote.enabled {
                let reply = try await call(owner, "disable", epoch: remote.epoch)
                try requireOwner()
                try write { try Self.writeLocal($0, owner: owner, value: SyncLocal()) }
                enabled = reply.enabled
                publish(SyncLocal())
                if !reply.enabled { Analytics.track(.diarySyncDisabled) }
                return
            }
            if let epoch = local.epoch, epoch != remote.epoch {
                local = SyncLocal()
                try write { try Self.writeLocal($0, owner: owner, value: local) }
            }
            if action == "enable" && local.epoch == nil {
                let reply = remote.enabled ? remote : try await call(owner, "enable", epoch: remote.epoch)
                try requireOwner()
                enabled = reply.enabled
                local = SyncLocal(epoch: reply.epoch)
                try write { try Self.writeLocal($0, owner: owner, value: local) }
                if reply.enabled && local.epoch != nil { Analytics.track(.diarySyncEnabled) }
            }
            publish(local)
            guard let epoch = local.epoch, enabled else { return }
            guard local.conflicts.isEmpty || action == "cloud" || action == "local" else { return }
            let sent = try read { try Self.readRecords($0) }
            let changes = sent.compactMap { key, row -> SyncChange? in
                let baseline = local.baseline[key]
                if baseline == row || (action == "cloud" && local.conflicts.contains(key)) { return nil }
                return SyncChange(key: key, before: baseline, row: row)
            }
            let remoteState = try await call(owner, "exchange", epoch: epoch, changes: changes)
            try requireOwner()
            guard let records = remoteState.records else { throw SyncError.invalid }
            var didChange = false
            try write { connection in
                let current = try Self.readRecords(connection)
                var blocked = Set(remoteState.conflicts ?? [])
                for (key, row) in records where current[key] != sent[key] && row != local.baseline[key]
                    && row != current[key] && row != sent[key] {
                    blocked.insert(key)
                }
                for key in Array(blocked) {
                    guard let childID = current[key]?["child_id"] else { continue }
                    let childKey = "children/" + childID
                    if records[childKey]?["deleted_at"] != nil && current[childKey] != nil { blocked.insert(childKey) }
                }
                for table in syncTables {
                    for (key, row) in records where key.hasPrefix(table.name + "/") {
                        if current[key] != sent[key] || blocked.contains(key) || row == current[key] { continue }
                        try Self.apply(connection, table: table, row: row)
                        didChange = true
                    }
                }
                if action == "cloud" {
                    for key in local.conflicts where records[key] == nil && current[key] == sent[key] {
                        if let row = current[key], let table = syncTables.first(where: { key.hasPrefix($0.name + "/") }) {
                            try Self.delete(connection, table: table, row: row)
                            didChange = true
                        }
                    }
                }
                var baseline = records
                for (key, row) in records where !blocked.contains(key) && current[key] != sent[key] {
                    baseline[key] = sent[key] ?? row
                }
                local.baseline = baseline
                local.conflicts = blocked.sorted()
                local.lastSync = Date()
                try Self.writeLocal(connection, owner: owner, value: local)
            }
            publish(local)
            if didChange { changed() }
            if action == "enable" && records.keys.contains(where: { $0.hasPrefix("children/") }) { restored() }
        } catch is CancellationError {
            return
        } catch {
            if tokens.userId == owner { failed = true }
        }
    }

    private func call(_ owner: String, _ action: String, epoch: String? = nil, changes: [SyncChange] = []) async throws -> SyncReply {
        guard tokens.userId == owner else { throw CancellationError() }
        let result: ApiResult<SyncReply> = await api.call(
            "POST", "sync/diary", body: SyncRequest(owner: owner, action: action, epoch: epoch, changes: changes),
            authorized: true, expectedOwner: owner
        )
        switch result {
        case .success(let data): return data
        case .failure(let error): throw error
        }
    }

    private func read<T>(_ work: (Database) throws -> T) throws -> T {
        try db.dbQueue.read(work)
    }

    private func write<T>(_ work: (Database) throws -> T) throws -> T {
        try db.dbQueue.write(work)
    }

    private enum SyncError: Error { case invalid }

    nonisolated private static func readLocal(_ db: Database, owner: String) throws -> SyncLocal {
        if let json = try String.fetchOne(db, sql: "SELECT payload FROM diary_sync_local WHERE owner = ?", arguments: [owner]) {
            return try JSONDecoder().decode(SyncLocal.self, from: Data(json.utf8))
        }
        return SyncLocal()
    }

    nonisolated private static func writeLocal(_ db: Database, owner: String, value: SyncLocal) throws {
        let payload = String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
        try db.execute(sql: "INSERT OR REPLACE INTO diary_sync_local (owner, payload) VALUES (?, ?)", arguments: [owner, payload])
    }

    nonisolated private static func readRecords(_ db: Database) throws -> SyncRows {
        var snapshot: SyncRows = [:]
        for table in syncTables {
            let columns = table.columns.map { "CAST(\($0) AS TEXT) AS \($0)" }.joined(separator: ", ")
            for row in try Row.fetchAll(db, sql: "SELECT \(columns) FROM \(table.name)") {
                var values: [String: String] = [:]
                for field in table.columns {
                    let value: String? = row[field]
                    values[field] = value
                }
                let parts = table.keys.compactMap { values[$0] }
                guard parts.count == table.keys.count else { throw SyncError.invalid }
                snapshot[table.name + "/" + parts.joined(separator: ":")] = values
            }
        }
        return snapshot
    }

    nonisolated private static func delete(_ db: Database, table: SyncTable, row: [String: String]) throws {
        let predicate = table.keys.map { "\($0) = ?" }.joined(separator: " AND ")
        try db.execute(sql: "DELETE FROM \(table.name) WHERE \(predicate)",
                       arguments: StatementArguments(table.keys.map { row[$0] }))
    }

    nonisolated private static func apply(_ db: Database, table: SyncTable, row: [String: String]) throws {
        let fields = table.columns
        guard Set(row.keys).isSubset(of: Set(fields)) else { throw SyncError.invalid }
        let columns = fields.joined(separator: ",")
        let placeholders = fields.map { _ in "?" }.joined(separator: ",")
        let update = fields.filter { !table.keys.contains($0) }.map { "\($0) = excluded.\($0)" }.joined(separator: ",")
        let keys = table.keys.joined(separator: ",")
        try db.execute(sql: """
            INSERT INTO \(table.name) (\(columns)) VALUES (\(placeholders))
            ON CONFLICT (\(keys)) DO UPDATE SET \(update)
            """, arguments: StatementArguments(fields.map { row[$0] }))
    }
}
