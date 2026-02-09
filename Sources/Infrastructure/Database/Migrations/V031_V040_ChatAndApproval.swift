// Sources/Infrastructure/Database/Migrations/V031_V040_ChatAndApproval.swift
// v31-v40: タスク作成者追跡、リモートアクセス、通知、会話、承認
// 参照: docs/design/MULTI_DEVICE_IMPLEMENTATION_PLAN.md, docs/design/AI_TO_AI_CONVERSATION.md

import Foundation
import GRDB

extension DatabaseMigrator {

    /// v31〜v40のマイグレーションを登録
    mutating func registerV031toV040() {

        // v31: タスク作成者追跡フィールド
        registerMigration("v31_task_created_by") { db in
            try db.alter(table: "tasks") { t in
                t.add(column: "created_by_agent_id", .text)
                    .references("agents", onDelete: .setNull)
            }
            try db.create(indexOn: "tasks", columns: ["created_by_agent_id"])
        }

        // v32: リモートアクセス設定
        // 参照: docs/design/MULTI_DEVICE_IMPLEMENTATION_PLAN.md - フェーズ1.1
        registerMigration("v32_allow_remote_access") { db in
            try db.alter(table: "app_settings") { t in
                t.add(column: "allow_remote_access", .boolean).defaults(to: false)
            }
        }

        // v33: エージェントワーキングディレクトリ設定
        // 参照: docs/design/MULTI_DEVICE_IMPLEMENTATION_PLAN.md - フェーズ2.1
        registerMigration("v33_agent_working_directories") { db in
            try db.create(table: "agent_working_directories", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("agent_id", .text).notNull()
                    .references("agents", onDelete: .cascade)
                t.column("project_id", .text).notNull()
                    .references("projects", onDelete: .cascade)
                t.column("working_directory", .text).notNull()
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }
            try db.create(
                index: "idx_agent_working_directories_unique",
                on: "agent_working_directories",
                columns: ["agent_id", "project_id"],
                unique: true
            )
            try db.create(indexOn: "agent_working_directories", columns: ["agent_id"])
            try db.create(indexOn: "agent_working_directories", columns: ["project_id"])
        }

        // v34: セッションアイドルタイムアウト管理
        registerMigration("v34_session_last_activity") { db in
            try db.alter(table: "agent_sessions") { t in
                t.add(column: "last_activity_at", .datetime)
            }
            try db.execute(sql: """
                UPDATE agent_sessions SET last_activity_at = created_at
                WHERE last_activity_at IS NULL
            """)
        }

        // v35: 孤立した execution_logs のクリーンアップ
        registerMigration("v35_cleanup_orphaned_execution_logs") { db in
            try db.execute(sql: """
                DELETE FROM execution_logs
                WHERE task_id NOT IN (SELECT id FROM tasks)
            """)
        }

        // v36: 通知システム
        // 参照: docs/design/NOTIFICATION_SYSTEM.md
        registerMigration("v36_notifications") { db in
            try db.create(table: "notifications", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("target_agent_id", .text).notNull()
                t.column("target_project_id", .text).notNull()
                t.column("type", .text).notNull()
                t.column("action", .text).notNull()
                t.column("task_id", .text)
                t.column("message", .text).notNull()
                t.column("instruction", .text).notNull()
                t.column("created_at", .datetime).notNull()
                t.column("is_read", .boolean).notNull().defaults(to: false)
                t.column("read_at", .datetime)
            }
            try db.create(
                index: "idx_notifications_unread",
                on: "notifications",
                columns: ["target_agent_id", "target_project_id", "is_read"]
            )
            try db.create(indexOn: "notifications", columns: ["created_at"])
        }

        // v37: セッション状態フィールド追加（UC015: チャットセッション終了）
        registerMigration("v37_session_state") { db in
            try db.alter(table: "agent_sessions") { t in
                t.add(column: "state", .text).defaults(to: "active")
            }
        }

        // v38: AI-to-AI会話管理テーブル（UC016）
        // 参照: docs/design/AI_TO_AI_CONVERSATION.md
        registerMigration("v38_conversations") { db in
            try db.create(table: "conversations", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("project_id", .text).notNull()
                    .references("projects", onDelete: .cascade)
                t.column("initiator_agent_id", .text).notNull()
                    .references("agents", onDelete: .cascade)
                t.column("participant_agent_id", .text).notNull()
                    .references("agents", onDelete: .cascade)
                t.column("state", .text).notNull().defaults(to: "pending")
                t.column("purpose", .text)
                t.column("created_at", .datetime).notNull()
                t.column("ended_at", .datetime)
            }
            try db.create(indexOn: "conversations", columns: ["project_id"])
            try db.create(indexOn: "conversations", columns: ["initiator_agent_id"])
            try db.create(indexOn: "conversations", columns: ["participant_agent_id"])
            try db.create(indexOn: "conversations", columns: ["state"])

            try db.alter(table: "pending_agent_purposes") { t in
                t.add(column: "conversation_id", .text)
            }
        }

        // v39: conversations に max_turns を追加
        registerMigration("v39_conversations_max_turns") { db in
            try db.alter(table: "conversations") { t in
                t.add(column: "max_turns", .integer).notNull().defaults(to: 20)
            }
        }

        // v40: タスク依頼・承認機能
        // 参照: docs/design/TASK_REQUEST_APPROVAL.md
        registerMigration("v40_task_approval") { db in
            try db.alter(table: "tasks") { t in
                t.add(column: "requester_id", .text)
                t.add(column: "approval_status", .text).notNull().defaults(to: "approved")
                t.add(column: "rejected_reason", .text)
                t.add(column: "approved_by", .text)
                t.add(column: "approved_at", .datetime)
            }
            try db.create(indexOn: "tasks", columns: ["approval_status"])
            try db.create(indexOn: "tasks", columns: ["requester_id"])
        }
    }
}
