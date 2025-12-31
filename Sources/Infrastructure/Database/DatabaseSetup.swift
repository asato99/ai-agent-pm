// Sources/Infrastructure/Database/DatabaseSetup.swift
// 参照: docs/architecture/DATABASE_SCHEMA.md - スキーマ定義
// 参照: docs/guide/CLEAN_ARCHITECTURE.md - Infrastructure層

import Foundation
import GRDB

/// データベースのセットアップとマイグレーションを管理
public final class DatabaseSetup {

    /// データベースを作成または開く
    /// - Parameter path: データベースファイルのパス
    /// - Returns: 設定済みのDatabaseQueue
    public static func createDatabase(at path: String) throws -> DatabaseQueue {
        // ディレクトリが存在しない場合は作成
        let directory = (path as NSString).deletingLastPathComponent
        if !FileManager.default.fileExists(atPath: directory) {
            try FileManager.default.createDirectory(
                atPath: directory,
                withIntermediateDirectories: true
            )
        }

        // WALモードを有効化した設定を作成
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            // WALモードを有効化（同時アクセス対応）
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            // 外部キー制約を有効化
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }

        let dbQueue = try DatabaseQueue(path: path, configuration: configuration)

        // マイグレーション実行
        try migrate(dbQueue)

        return dbQueue
    }

    /// マイグレーションを実行
    private static func migrate(_ dbQueue: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()

        // v1: 初期スキーマ
        migrator.registerMigration("v1_initial") { db in
            // projects テーブル
            try db.create(table: "projects", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
            }

            // agents テーブル
            try db.create(table: "agents", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("project_id", .text).notNull()
                    .references("projects", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("role", .text).notNull()
                t.column("type", .text).notNull()
            }
            try db.create(indexOn: "agents", columns: ["project_id"])

            // tasks テーブル
            try db.create(table: "tasks", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("project_id", .text).notNull()
                    .references("projects", onDelete: .cascade)
                t.column("title", .text).notNull()
                t.column("status", .text).notNull().defaults(to: "backlog")
                t.column("assignee_id", .text)
                    .references("agents", onDelete: .setNull)
            }
            try db.create(indexOn: "tasks", columns: ["project_id", "status"])
            try db.create(indexOn: "tasks", columns: ["assignee_id"])
        }

        // v2: Phase 2 フルスキーマ
        migrator.registerMigration("v2_full_schema") { db in
            // 固定のデフォルト日時 (SQLiteはALTER TABLEで非定数デフォルト値をサポートしない)
            let defaultDate = "2024-01-01 00:00:00"

            // projects テーブル拡張
            try db.alter(table: "projects") { t in
                t.add(column: "description", .text).defaults(to: "")
                t.add(column: "status", .text).defaults(to: "active")
            }
            // 日時カラムは手動で追加（定数デフォルト値を使用）
            try db.execute(sql: """
                ALTER TABLE projects ADD COLUMN created_at DATETIME DEFAULT '\(defaultDate)'
            """)
            try db.execute(sql: """
                ALTER TABLE projects ADD COLUMN updated_at DATETIME DEFAULT '\(defaultDate)'
            """)

            // agents テーブル拡張
            try db.alter(table: "agents") { t in
                t.add(column: "role_type", .text).defaults(to: "developer")
                t.add(column: "capabilities", .text) // JSON array
                t.add(column: "system_prompt", .text)
                t.add(column: "status", .text).defaults(to: "active")
            }
            try db.execute(sql: """
                ALTER TABLE agents ADD COLUMN created_at DATETIME DEFAULT '\(defaultDate)'
            """)
            try db.execute(sql: """
                ALTER TABLE agents ADD COLUMN updated_at DATETIME DEFAULT '\(defaultDate)'
            """)

            // tasks テーブル拡張
            try db.alter(table: "tasks") { t in
                t.add(column: "description", .text).defaults(to: "")
                t.add(column: "priority", .text).defaults(to: "medium")
                t.add(column: "parent_task_id", .text)
                t.add(column: "dependencies", .text) // JSON array
                t.add(column: "estimated_minutes", .integer)
                t.add(column: "actual_minutes", .integer)
                t.add(column: "completed_at", .datetime)
            }
            try db.execute(sql: """
                ALTER TABLE tasks ADD COLUMN created_at DATETIME DEFAULT '\(defaultDate)'
            """)
            try db.execute(sql: """
                ALTER TABLE tasks ADD COLUMN updated_at DATETIME DEFAULT '\(defaultDate)'
            """)
            try db.create(indexOn: "tasks", columns: ["parent_task_id"])

            // sessions テーブル
            try db.create(table: "sessions", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("project_id", .text).notNull()
                    .references("projects", onDelete: .cascade)
                t.column("agent_id", .text).notNull()
                    .references("agents", onDelete: .cascade)
                t.column("started_at", .datetime).notNull()
                t.column("ended_at", .datetime)
                t.column("status", .text).notNull().defaults(to: "active")
            }
            try db.create(indexOn: "sessions", columns: ["agent_id", "status"])
            try db.create(indexOn: "sessions", columns: ["project_id"])

            // contexts テーブル
            try db.create(table: "contexts", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("task_id", .text).notNull()
                    .references("tasks", onDelete: .cascade)
                t.column("session_id", .text).notNull()
                    .references("sessions", onDelete: .cascade)
                t.column("agent_id", .text).notNull()
                    .references("agents", onDelete: .cascade)
                t.column("progress", .text)
                t.column("findings", .text)
                t.column("blockers", .text)
                t.column("next_steps", .text)
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }
            try db.create(indexOn: "contexts", columns: ["task_id"])
            try db.create(indexOn: "contexts", columns: ["session_id"])

            // handoffs テーブル
            try db.create(table: "handoffs", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("task_id", .text).notNull()
                    .references("tasks", onDelete: .cascade)
                t.column("from_agent_id", .text).notNull()
                    .references("agents", onDelete: .cascade)
                t.column("to_agent_id", .text)
                    .references("agents", onDelete: .setNull)
                t.column("summary", .text).notNull()
                t.column("context", .text)
                t.column("recommendations", .text)
                t.column("accepted_at", .datetime)
                t.column("created_at", .datetime).notNull()
            }
            try db.create(indexOn: "handoffs", columns: ["task_id"])
            try db.create(indexOn: "handoffs", columns: ["to_agent_id"])

            // subtasks テーブル
            try db.create(table: "subtasks", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("task_id", .text).notNull()
                    .references("tasks", onDelete: .cascade)
                t.column("title", .text).notNull()
                t.column("is_completed", .boolean).notNull().defaults(to: false)
                t.column("order", .integer).notNull().defaults(to: 0)
                t.column("created_at", .datetime).notNull()
                t.column("completed_at", .datetime)
            }
            try db.create(indexOn: "subtasks", columns: ["task_id"])

            // state_change_events テーブル
            try db.create(table: "state_change_events", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("project_id", .text).notNull()
                    .references("projects", onDelete: .cascade)
                t.column("entity_type", .text).notNull()
                t.column("entity_id", .text).notNull()
                t.column("event_type", .text).notNull()
                t.column("agent_id", .text)
                t.column("session_id", .text)
                t.column("previous_state", .text)
                t.column("new_state", .text)
                t.column("reason", .text)
                t.column("metadata", .text) // JSON object
                t.column("timestamp", .datetime).notNull()
            }
            try db.create(indexOn: "state_change_events", columns: ["project_id", "timestamp"])
            try db.create(indexOn: "state_change_events", columns: ["entity_type", "entity_id"])
        }

        try migrator.migrate(dbQueue)
    }
}
