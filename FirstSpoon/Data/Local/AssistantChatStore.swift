import Foundation
import GRDB

struct AssistantConversation: Identifiable, Hashable {
    let id: String
    let productId: String?
    let productName: String?
    let title: String
}

struct AssistantTurn: Identifiable {
    let id: String
    let requestId: String
    let question: String
    let context: AssistantContext
    let reply: AssistantReply?
    let failure: String?
    var stopped = false
    var feedback: Bool?
    var repliedAt: Int64?
}

struct AssistantChatStore {
    let database: AppDatabase
    let owner: String
    let child: String

    func conversations() throws -> [AssistantConversation] {
        try database.dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM assistant_chats WHERE child_id = ? AND owner_id = ?
                ORDER BY updated_at DESC, rowid DESC
                """, arguments: [child, owner]).map { row in
                AssistantConversation(id: row["id"], productId: row["product_id"], productName: row["product_name"], title: row["title"])
            }
        }
    }

    func messages(_ chat: AssistantConversation) throws -> [AssistantTurn] {
        try database.dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT t.* FROM assistant_turns t JOIN assistant_chats c ON c.id = t.chat_id
                WHERE c.id = ? AND c.child_id = ? AND c.owner_id = ? ORDER BY t.rowid
                """, arguments: [chat.id, child, owner]).map { row in
                let context: Data = row["context"]
                let reply: Data? = row["reply"]
                return AssistantTurn(id: row["id"], requestId: row["request_id"], question: row["question"],
                                     context: try JSONDecoder().decode(AssistantContext.self, from: context),
                                     reply: try reply.map { try JSONDecoder().decode(AssistantReply.self, from: $0) },
                                     failure: row["failure"], stopped: row["stopped"],
                                     feedback: row["feedback"], repliedAt: row["replied_at"])
            }
        }
    }

    func append(_ turn: AssistantTurn, to chat: AssistantConversation, create: Bool) throws {
        let context = try JSONEncoder().encode(turn.context)
        try database.dbQueue.write { db in
            if create {
                try db.execute(sql: """
                    INSERT INTO assistant_chats (id, child_id, owner_id, product_id, product_name, title, updated_at)
                    SELECT ?, id, ?, ?, ?, ?, ? FROM children WHERE id = ? AND deleted_at IS NULL
                    """, arguments: [chat.id, owner, chat.productId, chat.productName, chat.title, nowMillis(), child])
            }
            guard try Int.fetchOne(db, sql: """
                SELECT 1 FROM assistant_chats WHERE id = ? AND child_id = ? AND owner_id = ?
                AND NOT EXISTS (SELECT 1 FROM assistant_turns WHERE chat_id = ? AND reply IS NULL AND stopped = 0)
                """, arguments: [chat.id, child, owner, chat.id]) == 1 else { throw ChatStorageError.unavailable }
            try db.execute(sql: """
                INSERT INTO assistant_turns (id, chat_id, request_id, question, context) VALUES (?, ?, ?, ?, ?)
                """, arguments: [turn.id, chat.id, turn.requestId, turn.question, context])
            try db.execute(sql: "UPDATE assistant_chats SET updated_at = ? WHERE id = ?", arguments: [nowMillis(), chat.id])
        }
    }

    @discardableResult
    func finish(_ turn: AssistantTurn, reply: AssistantReply?, failure: String?) throws -> Bool {
        let replyData = try reply.map { try JSONEncoder().encode($0) }
        let receivedAt = reply == nil ? nil : nowMillis()
        return try database.dbQueue.write { db in
            try db.execute(sql: """
                UPDATE assistant_turns SET request_id = ?, reply = ?, failure = ?, replied_at = ?
                WHERE id = ? AND reply IS NULL AND stopped = 0
                  AND chat_id IN (SELECT id FROM assistant_chats WHERE child_id = ? AND owner_id = ?)
                """, arguments: [turn.requestId, replyData, failure, receivedAt, turn.id, child, owner])
            let changed = db.changesCount == 1
            if let receivedAt, changed {
                try db.execute(sql: """
                    UPDATE assistant_chats SET updated_at = ? WHERE id = (SELECT chat_id FROM assistant_turns WHERE id = ?)
                    """, arguments: [receivedAt, turn.id])
            }
            return changed
        }
    }

    func stop(_ turn: AssistantTurn) throws -> Bool {
        try database.dbQueue.write { db in
            try db.execute(sql: """
                UPDATE assistant_turns SET stopped = 1, failure = NULL WHERE id = ? AND reply IS NULL AND stopped = 0
                  AND chat_id IN (SELECT id FROM assistant_chats WHERE child_id = ? AND owner_id = ?)
                """, arguments: [turn.id, child, owner])
            return db.changesCount == 1
        }
    }

    func toggleFeedback(_ turn: AssistantTurn, positive: Bool) throws -> Bool {
        try database.dbQueue.write { db in
            try db.execute(sql: """
                UPDATE assistant_turns SET feedback = CASE WHEN feedback = ? THEN NULL ELSE ? END
                WHERE id = ? AND reply IS NOT NULL
                  AND chat_id IN (SELECT id FROM assistant_chats WHERE child_id = ? AND owner_id = ?)
                """, arguments: [positive, positive, turn.id, child, owner])
            return db.changesCount == 1
        }
    }

    func delete(_ chat: AssistantConversation) throws {
        try database.dbQueue.write {
            try $0.execute(sql: "DELETE FROM assistant_chats WHERE id = ? AND child_id = ? AND owner_id = ?",
                           arguments: [chat.id, child, owner])
        }
    }

    private enum ChatStorageError: Error { case unavailable }
}
