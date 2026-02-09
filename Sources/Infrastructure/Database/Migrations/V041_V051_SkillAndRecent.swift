// Sources/Infrastructure/Database/Migrations/V041_V051_SkillAndRecent.swift
// v41-v51: スキル、チャット委譲、タスク完了、モデルサフィックス除去
// 参照: docs/design/AGENT_SKILLS.md, docs/design/TASK_CHAT_SESSION_SEPARATION.md

import Foundation
import GRDB

extension DatabaseMigrator {

    /// v41〜v51のマイグレーションを登録
    mutating func registerV041toV051() {

        // v41: pending_agent_purposes の主キーに purpose を追加
        registerMigration("v41_pending_purpose_composite_key") { db in
            try db.create(table: "pending_agent_purposes_new") { t in
                t.column("agent_id", .text).notNull()
                t.column("project_id", .text).notNull()
                t.column("purpose", .text).notNull()
                t.column("created_at", .datetime).notNull()
                t.column("started_at", .datetime)
                t.column("conversation_id", .text)
                t.primaryKey(["agent_id", "project_id", "purpose"])
            }

            try db.execute(sql: """
                INSERT INTO pending_agent_purposes_new
                (agent_id, project_id, purpose, created_at, started_at, conversation_id)
                SELECT agent_id, project_id, purpose, created_at, started_at, conversation_id
                FROM pending_agent_purposes
            """)

            try db.drop(table: "pending_agent_purposes")
            try db.rename(table: "pending_agent_purposes_new", to: "pending_agent_purposes")

            try db.create(indexOn: "pending_agent_purposes", columns: ["agent_id"])
            try db.create(indexOn: "pending_agent_purposes", columns: ["project_id"])
        }

        // v42: project_agents に spawn_started_at 列を追加
        // 参照: docs/design/SESSION_SPAWN_ARCHITECTURE.md
        registerMigration("v42_project_agents_spawn_started_at") { db in
            try db.alter(table: "project_agents") { t in
                t.add(column: "spawn_started_at", .datetime)
            }
        }

        // v43: pending_agent_purposes テーブル削除
        registerMigration("v43_drop_pending_agent_purposes") { db in
            try db.drop(table: "pending_agent_purposes")
        }

        // v44: スキル定義とエージェントスキル割り当て
        // 参照: docs/design/AGENT_SKILLS.md
        registerMigration("v44_skill_definitions") { db in
            try db.create(table: "skill_definitions", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("description", .text).notNull().defaults(to: "")
                t.column("directory_name", .text).notNull().unique()
                t.column("content", .text).notNull()
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }
            try db.create(indexOn: "skill_definitions", columns: ["directory_name"])

            try db.create(table: "agent_skill_assignments", ifNotExists: true) { t in
                t.column("agent_id", .text).notNull()
                    .references("agents", onDelete: .cascade)
                t.column("skill_id", .text).notNull()
                    .references("skill_definitions", onDelete: .cascade)
                t.column("assigned_at", .datetime).notNull()
                t.primaryKey(["agent_id", "skill_id"])
            }
            try db.create(indexOn: "agent_skill_assignments", columns: ["agent_id"])
            try db.create(indexOn: "agent_skill_assignments", columns: ["skill_id"])
        }

        // v45: スキル定義をアーカイブ形式に移行
        // 参照: docs/design/AGENT_SKILLS.md - アーカイブ形式
        registerMigration("v45_skill_archive_format") { db in
            try db.create(table: "skill_definitions_new") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("description", .text).notNull().defaults(to: "")
                t.column("directory_name", .text).notNull().unique()
                t.column("archive_data", .blob).notNull()
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }

            let rows = try Row.fetchAll(db, sql: """
                SELECT id, name, description, directory_name, content, created_at, updated_at
                FROM skill_definitions
            """)

            for row in rows {
                let id: String = row["id"]
                let name: String = row["name"]
                let description: String = row["description"]
                let directoryName: String = row["directory_name"]
                let content: String = row["content"]
                let createdAt: String = row["created_at"]
                let updatedAt: String = row["updated_at"]

                let archiveData = DatabaseSetup.createZipArchive(skillMdContent: content)

                try db.execute(sql: """
                    INSERT INTO skill_definitions_new
                    (id, name, description, directory_name, archive_data, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                """, arguments: [id, name, description, directoryName, archiveData, createdAt, updatedAt])
            }

            try db.drop(table: "skill_definitions")
            try db.rename(table: "skill_definitions_new", to: "skill_definitions")
            try db.create(indexOn: "skill_definitions", columns: ["directory_name"])
        }

        // v46: チャットセッション委譲テーブル
        // 参照: docs/design/TASK_CHAT_SESSION_SEPARATION.md
        registerMigration("v46_chat_delegations") { db in
            try db.create(table: "chat_delegations", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("agent_id", .text).notNull()
                    .references("agents", onDelete: .cascade)
                t.column("project_id", .text).notNull()
                    .references("projects", onDelete: .cascade)
                t.column("target_agent_id", .text).notNull()
                    .references("agents", onDelete: .cascade)
                t.column("purpose", .text).notNull()
                t.column("context", .text)
                t.column("status", .text).notNull().defaults(to: "pending")
                t.column("created_at", .datetime).notNull()
                t.column("processed_at", .datetime)
                t.column("result", .text)
            }
            try db.create(indexOn: "chat_delegations", columns: ["agent_id", "project_id", "status"])
            try db.create(indexOn: "chat_delegations", columns: ["status"])
        }

        // v47: タスク会話待機機能のためのtask_idカラム追加
        // 参照: docs/design/TASK_CONVERSATION_AWAIT.md
        registerMigration("v47_task_conversation_await") { db in
            try db.execute(sql: """
                ALTER TABLE agent_sessions ADD COLUMN task_id TEXT
                    REFERENCES tasks(id) ON DELETE SET NULL
            """)
            try db.execute(sql: """
                ALTER TABLE chat_delegations ADD COLUMN task_id TEXT
                    REFERENCES tasks(id) ON DELETE SET NULL
            """)
            try db.execute(sql: """
                ALTER TABLE conversations ADD COLUMN task_id TEXT
                    REFERENCES tasks(id) ON DELETE SET NULL
            """)
            try db.create(indexOn: "conversations", columns: ["task_id"])
        }

        // v48: エージェントベースプロンプト設定
        registerMigration("v48_agent_base_prompt") { db in
            try db.execute(sql: """
                ALTER TABLE app_settings ADD COLUMN agent_base_prompt TEXT
            """)
        }

        // v49: タスク完了結果フィールド追加
        registerMigration("v49_task_completion_result") { db in
            try db.alter(table: "tasks") { t in
                t.add(column: "completion_result", .text)
                t.add(column: "completion_summary", .text)
            }
        }

        // v50: 通知に会話ID追加
        registerMigration("v50_notification_conversation_id") { db in
            try db.alter(table: "notifications") { t in
                t.add(column: "conversation_id", .text)
            }
        }

        // v51: モデルIDから日付サフィックスを除去
        registerMigration("v51_remove_model_date_suffix") { db in
            try db.execute(sql: """
                UPDATE agents SET model_id = 'claude-opus-4'
                WHERE model_id = 'claude-opus-4-20250514'
            """)
            try db.execute(sql: """
                UPDATE agents SET model_id = 'claude-sonnet-4-5'
                WHERE model_id = 'claude-sonnet-4-5-20250929'
            """)
            try db.execute(sql: """
                UPDATE agents SET model_id = 'claude-sonnet-4'
                WHERE model_id = 'claude-sonnet-4-20250514'
            """)
        }
    }
}
