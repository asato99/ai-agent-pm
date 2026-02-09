// Sources/Infrastructure/Database/Migrations/V011_V020_AuditAndAuth.swift
// v11-v20: 監査、ロック、認証、実行ログ、AIタイプ、セッション拡張
// 参照: docs/requirements/AUDIT.md, docs/plan/PHASE3_PULL_ARCHITECTURE.md

import Foundation
import GRDB

extension DatabaseMigrator {

    /// v11〜v20のマイグレーションを登録
    mutating func registerV011toV020() {

        // v11: エージェント階層タイプ追加
        // 参照: docs/requirements/AGENTS.md - エージェントタイプ（Manager/Worker）
        registerMigration("v11_agent_hierarchy_type") { db in
            try db.alter(table: "agents") { t in
                t.add(column: "hierarchy_type", .text).defaults(to: "worker")
            }
        }

        // v12: Internal Audit機能
        // 参照: docs/requirements/AUDIT.md
        registerMigration("v12_internal_audit") { db in
            try db.create(table: "internal_audits", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("description", .text).defaults(to: "")
                t.column("status", .text).notNull().defaults(to: "active")
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }
            try db.create(indexOn: "internal_audits", columns: ["status"])

            try db.create(table: "audit_rules", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("audit_id", .text).notNull()
                    .references("internal_audits", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("trigger_type", .text).notNull()
                t.column("trigger_config", .text) // JSON object
                t.column("workflow_template_id", .text).notNull()
                    .references("workflow_templates", onDelete: .restrict)
                t.column("task_assignments", .text) // JSON array
                t.column("is_enabled", .boolean).notNull().defaults(to: true)
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }
            try db.create(indexOn: "audit_rules", columns: ["audit_id"])
            try db.create(indexOn: "audit_rules", columns: ["trigger_type"])
            try db.create(indexOn: "audit_rules", columns: ["is_enabled"])
        }

        // v13: ロック機能
        // 参照: docs/requirements/AUDIT.md - ロック機能
        registerMigration("v13_lock_functionality") { db in
            try db.alter(table: "tasks") { t in
                t.add(column: "is_locked", .boolean).defaults(to: false)
                t.add(column: "locked_by_audit_id", .text)
                t.add(column: "locked_at", .datetime)
            }
            try db.create(indexOn: "tasks", columns: ["is_locked"])
            try db.create(indexOn: "tasks", columns: ["locked_by_audit_id"])

            try db.alter(table: "agents") { t in
                t.add(column: "is_locked", .boolean).defaults(to: false)
                t.add(column: "locked_by_audit_id", .text)
                t.add(column: "locked_at", .datetime)
            }
            try db.create(indexOn: "agents", columns: ["is_locked"])
            try db.create(indexOn: "agents", columns: ["locked_by_audit_id"])
        }

        // v14: 仕様変更 - WorkflowTemplateはプロジェクトスコープ、AuditRuleはインラインauditTasks
        registerMigration("v14_template_project_scope_and_audit_inline_tasks") { db in
            try db.alter(table: "workflow_templates") { t in
                t.add(column: "project_id", .text)
            }
            try db.create(indexOn: "workflow_templates", columns: ["project_id"])

            // audit_rules テーブルを再構築
            try db.execute(sql: """
                CREATE TABLE audit_rules_new (
                    id TEXT PRIMARY KEY,
                    audit_id TEXT NOT NULL REFERENCES internal_audits(id) ON DELETE CASCADE,
                    name TEXT NOT NULL,
                    trigger_type TEXT NOT NULL,
                    trigger_config TEXT,
                    audit_tasks TEXT,
                    is_enabled INTEGER NOT NULL DEFAULT 1,
                    created_at DATETIME NOT NULL,
                    updated_at DATETIME NOT NULL
                )
            """)

            try db.execute(sql: """
                INSERT INTO audit_rules_new (id, audit_id, name, trigger_type, trigger_config, is_enabled, created_at, updated_at)
                SELECT id, audit_id, name, trigger_type, trigger_config, is_enabled, created_at, updated_at FROM audit_rules
            """)

            try db.drop(table: "audit_rules")
            try db.rename(table: "audit_rules_new", to: "audit_rules")

            try db.create(indexOn: "audit_rules", columns: ["audit_id"])
            try db.create(indexOn: "audit_rules", columns: ["trigger_type"])
            try db.create(indexOn: "audit_rules", columns: ["is_enabled"])
        }

        // v15: 認証基盤（Phase 3-1）
        registerMigration("v15_authentication") { db in
            try db.create(table: "agent_credentials", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("agent_id", .text).notNull().unique()
                    .references("agents", onDelete: .cascade)
                t.column("passkey_hash", .text).notNull()
                t.column("salt", .text).notNull()
                t.column("created_at", .datetime).notNull()
                t.column("last_used_at", .datetime)
            }
            try db.create(indexOn: "agent_credentials", columns: ["agent_id"])

            try db.create(table: "agent_sessions", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("token", .text).notNull().unique()
                t.column("agent_id", .text).notNull()
                    .references("agents", onDelete: .cascade)
                t.column("expires_at", .datetime).notNull()
                t.column("created_at", .datetime).notNull()
            }
            try db.create(indexOn: "agent_sessions", columns: ["token"])
            try db.create(indexOn: "agent_sessions", columns: ["agent_id"])
            try db.create(indexOn: "agent_sessions", columns: ["expires_at"])
        }

        // v16: 実行ログ（Phase 3-3）
        registerMigration("v16_execution_logs") { db in
            try db.create(table: "execution_logs", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("task_id", .text).notNull()
                    .references("tasks", onDelete: .cascade)
                t.column("agent_id", .text).notNull()
                    .references("agents", onDelete: .cascade)
                t.column("status", .text).notNull().defaults(to: "running")
                t.column("started_at", .datetime).notNull()
                t.column("completed_at", .datetime)
                t.column("exit_code", .integer)
                t.column("duration_seconds", .double)
                t.column("log_file_path", .text)
                t.column("error_message", .text)
            }
            try db.create(indexOn: "execution_logs", columns: ["task_id"])
            try db.create(indexOn: "execution_logs", columns: ["agent_id"])
            try db.create(indexOn: "execution_logs", columns: ["status"])
        }

        // v17: AIタイプ追加（マルチAIプロバイダー対応）
        registerMigration("v17_ai_type") { db in
            try db.alter(table: "agents") { t in
                t.add(column: "ai_type", .text)
            }
        }

        // v18: プロジェクト×エージェント割り当てテーブル
        registerMigration("v18_project_agents") { db in
            try db.create(table: "project_agents", ifNotExists: true) { t in
                t.column("project_id", .text).notNull()
                    .references("projects", onDelete: .cascade)
                t.column("agent_id", .text).notNull()
                    .references("agents", onDelete: .cascade)
                t.column("assigned_at", .datetime).notNull()
                t.primaryKey(["project_id", "agent_id"])
            }
            try db.create(indexOn: "project_agents", columns: ["project_id"])
            try db.create(indexOn: "project_agents", columns: ["agent_id"])
        }

        // v19: セッションにプロジェクトID追加
        registerMigration("v19_session_project_id") { db in
            try db.alter(table: "agent_sessions") { t in
                t.add(column: "project_id", .text)
            }
            try db.create(indexOn: "agent_sessions", columns: ["agent_id", "project_id"])
        }

        // v20: モデル検証フィールド追加（AgentSession）
        registerMigration("v20_model_verification") { db in
            try db.alter(table: "agent_sessions") { t in
                t.add(column: "reported_provider", .text)
                t.add(column: "reported_model", .text)
                t.add(column: "model_verified", .boolean)
                t.add(column: "model_verified_at", .datetime)
            }
        }
    }
}
