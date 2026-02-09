// Sources/Infrastructure/Database/Migrations/V021_V030_SessionAndAgent.swift
// v21-v30: モデル検証、チャット基盤、アプリ設定、ステータス追跡、システムエージェント
// 参照: docs/design/CHAT_FEATURE.md, docs/plan/BLOCKED_TASK_RECOVERY.md

import Foundation
import GRDB

extension DatabaseMigrator {

    /// v21〜v30のマイグレーションを登録
    mutating func registerV021toV030() {

        // v21: モデル検証フィールド追加（ExecutionLog）
        registerMigration("v21_execution_log_model_info") { db in
            try db.alter(table: "execution_logs") { t in
                t.add(column: "reported_provider", .text)
                t.add(column: "reported_model", .text)
                t.add(column: "model_verified", .boolean)
            }
        }

        // v22: 起動待ちエージェントの起動理由管理テーブル
        // 参照: docs/design/CHAT_FEATURE.md - MCP連携設計
        registerMigration("v22_pending_agent_purposes") { db in
            try db.create(table: "pending_agent_purposes", ifNotExists: true) { t in
                t.column("agent_id", .text).notNull()
                t.column("project_id", .text).notNull()
                t.column("purpose", .text).notNull() // "task" | "chat"
                t.column("created_at", .datetime).notNull()
                t.primaryKey(["agent_id", "project_id"])
            }
            try db.create(indexOn: "pending_agent_purposes", columns: ["agent_id"])
            try db.create(indexOn: "pending_agent_purposes", columns: ["project_id"])
        }

        // v23: セッションに起動理由(purpose)フィールド追加
        registerMigration("v23_session_purpose") { db in
            try db.alter(table: "agent_sessions") { t in
                t.add(column: "purpose", .text).defaults(to: "task")
            }
        }

        // v24: アプリケーション設定テーブル（Coordinator Token保存用）
        registerMigration("v24_app_settings") { db in
            try db.create(table: "app_settings", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("coordinator_token", .text)
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }
        }

        // v25: 起動済みフラグ追加（複数起動防止）
        registerMigration("v25_pending_purpose_started_at") { db in
            try db.alter(table: "pending_agent_purposes") { t in
                t.add(column: "started_at", .datetime)
            }
        }

        // v26: Pending Purpose TTL設定を追加
        registerMigration("v26_app_settings_ttl") { db in
            try db.alter(table: "app_settings") { t in
                t.add(column: "pending_purpose_ttl_seconds", .integer).defaults(to: 300)
            }
        }

        // v27: パスキーの平文保存（Coordinatorエクスポート用）
        registerMigration("v27_credential_raw_passkey") { db in
            try db.alter(table: "agent_credentials") { t in
                t.add(column: "raw_passkey", .text)
            }
        }

        // v28: ステータス変更追跡フィールド
        // 参照: docs/plan/BLOCKED_TASK_RECOVERY.md
        registerMigration("v28_status_change_tracking") { db in
            try db.alter(table: "tasks") { t in
                t.add(column: "status_changed_by_agent_id", .text)
                    .references("agents", onDelete: .setNull)
                t.add(column: "status_changed_at", .datetime)
                t.add(column: "blocked_reason", .text)
            }
            try db.create(indexOn: "tasks", columns: ["status_changed_by_agent_id"])
        }

        // v29: provider/model_id 直接保存（Enumパース依存を排除）
        registerMigration("v29_agent_provider_model") { db in
            try db.alter(table: "agents") { t in
                t.add(column: "provider", .text)
                t.add(column: "model_id", .text)
            }

            // 既存データのマイグレーション: ai_type から provider/model_id を設定
            try db.execute(sql: """
                UPDATE agents SET provider = 'claude'
                WHERE ai_type LIKE 'claude-%' AND provider IS NULL
            """)
            try db.execute(sql: """
                UPDATE agents SET provider = 'gemini'
                WHERE ai_type LIKE 'gemini-%' AND provider IS NULL
            """)
            try db.execute(sql: """
                UPDATE agents SET provider = 'openai'
                WHERE ai_type LIKE 'gpt-%' AND provider IS NULL
            """)
            try db.execute(sql: """
                UPDATE agents SET provider = 'custom'
                WHERE provider IS NULL
            """)
            try db.execute(sql: """
                UPDATE agents SET model_id = ai_type
                WHERE model_id IS NULL AND ai_type IS NOT NULL
            """)
        }

        // v30: システムエージェント追加
        // 参照: Sources/Domain/ValueObjects/IDs.swift - AgentID.systemUser, AgentID.systemAuto
        registerMigration("v30_system_agents") { db in
            let now = ISO8601DateFormatter().string(from: Date())
            try db.execute(sql: """
                INSERT OR IGNORE INTO agents (
                    id, name, role, type, role_type, capabilities, system_prompt,
                    status, created_at, updated_at, kick_method, provider
                ) VALUES (
                    'system:user', 'System User', 'UI操作を表す仮想エージェント', 'human', 'developer',
                    '[]', NULL, 'inactive', '\(now)', '\(now)', 'none', NULL
                )
            """)
            try db.execute(sql: """
                INSERT OR IGNORE INTO agents (
                    id, name, role, type, role_type, capabilities, system_prompt,
                    status, created_at, updated_at, kick_method, provider
                ) VALUES (
                    'system:auto', 'System Auto', '自動処理を表す仮想エージェント', 'human', 'developer',
                    '[]', NULL, 'inactive', '\(now)', '\(now)', 'none', NULL
                )
            """)
        }
    }
}
