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

        // マルチプロセス同時アクセス対応: ビジータイムアウト設定
        // AppとMCPサーバーが同時にDBにアクセスする際のロック待機時間
        configuration.busyMode = .timeout(5.0) // 5秒待機

        configuration.prepareDatabase { db in
            // WALモードを有効化（同時アクセス対応）
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            // 外部キー制約を有効化
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            // 同期モードをNORMALに設定（パフォーマンスと安全性のバランス）
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
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

        // v3: 要件変更 - エージェント階層化、サブタスク削除
        migrator.registerMigration("v3_agent_hierarchy") { db in
            // subtasks テーブルを削除
            try db.drop(table: "subtasks")

            // agents テーブルを再構築（project_id削除、parent_agent_id追加）
            // SQLiteはALTER TABLE DROP COLUMNをサポートしないため、テーブル再構築が必要

            // 1. 一時テーブルを作成（self-referencing FKは後で追加）
            try db.execute(sql: """
                CREATE TABLE agents_new (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    role TEXT NOT NULL,
                    type TEXT NOT NULL,
                    role_type TEXT DEFAULT 'developer',
                    parent_agent_id TEXT,
                    max_parallel_tasks INTEGER DEFAULT 1,
                    capabilities TEXT,
                    system_prompt TEXT,
                    status TEXT DEFAULT 'active',
                    created_at DATETIME,
                    updated_at DATETIME
                )
            """)

            // 2. データを移行（project_idは破棄）
            try db.execute(sql: """
                INSERT INTO agents_new (id, name, role, type, role_type, capabilities, system_prompt, status, created_at, updated_at)
                SELECT id, name, role, type, role_type, capabilities, system_prompt, status, created_at, updated_at FROM agents
            """)

            // 3. 古いテーブルを削除
            try db.drop(table: "agents")

            // 4. 新しいテーブルをリネーム
            try db.rename(table: "agents_new", to: "agents")

            // 5. インデックス再作成
            try db.create(indexOn: "agents", columns: ["parent_agent_id"])
        }

        // v4: エージェントキック設定追加
        migrator.registerMigration("v4_agent_kick_settings") { db in
            // kick_method と kick_command カラムを追加
            try db.alter(table: "agents") { t in
                t.add(column: "kick_method", .text).defaults(to: "cli")
                t.add(column: "kick_command", .text)
            }
        }

        // v5: エージェント認証設定追加
        migrator.registerMigration("v5_agent_auth_settings") { db in
            // auth_level と passkey カラムを追加
            try db.alter(table: "agents") { t in
                t.add(column: "auth_level", .text).defaults(to: "level0")
                t.add(column: "passkey", .text)
            }
        }

        // v6: プロジェクト作業ディレクトリ追加
        migrator.registerMigration("v6_project_working_directory") { db in
            // working_directory カラムを追加（Claude Codeエージェント実行用）
            try db.alter(table: "projects") { t in
                t.add(column: "working_directory", .text)
            }
        }

        // v7: タスク成果物情報追加
        migrator.registerMigration("v7_task_output_info") { db in
            // output_file_name と output_description カラムを追加
            try db.alter(table: "tasks") { t in
                t.add(column: "output_file_name", .text)
                t.add(column: "output_description", .text)
            }
        }

        // v8: 要件変更 - サブタスク不要によりparent_task_idを廃止
        // 参照: docs/requirements/TASKS.md - サブタスクは不要
        // 参照: docs/usecase/UC001_TaskExecutionByAgent.md - タスク間関係はdependenciesで表現
        migrator.registerMigration("v8_remove_parent_task_id") { db in
            // parent_task_idインデックスを削除（インデックスが存在する場合のみ）
            // GRDB命名規則: index_<table>_on_<column>
            try? db.execute(sql: "DROP INDEX IF EXISTS index_tasks_on_parent_task_id")
            // 注意: SQLiteではカラム削除が困難なため、カラム自体は残存
            // TaskRecordからは削除済みのため、アプリケーションレベルでは無視される
        }

        // v9: 要件変更 - output_file_name/output_descriptionを廃止
        // 理由: ファイル名や内容はタスクの指示内容(description)で与えるべき
        // 成果物管理はエージェントの責務であり、PMアプリの責務ではない
        migrator.registerMigration("v9_remove_task_output_fields") { _ in
            // 注意: SQLiteではカラム削除が困難なため、カラム自体は残存
            // TaskRecordからは削除済みのため、アプリケーションレベルでは無視される
        }

        // v10: ワークフローテンプレート機能
        // 参照: docs/requirements/WORKFLOW_TEMPLATES.md
        migrator.registerMigration("v10_workflow_templates") { db in
            // workflow_templates テーブル
            try db.create(table: "workflow_templates", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("description", .text).defaults(to: "")
                t.column("variables", .text) // JSON array
                t.column("status", .text).notNull().defaults(to: "active")
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }
            try db.create(indexOn: "workflow_templates", columns: ["status"])

            // template_tasks テーブル
            try db.create(table: "template_tasks", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("template_id", .text).notNull()
                    .references("workflow_templates", onDelete: .cascade)
                t.column("title", .text).notNull()
                t.column("description", .text).defaults(to: "")
                t.column("order", .integer).notNull()
                t.column("depends_on_orders", .text) // JSON array
                t.column("default_assignee_role", .text)
                t.column("default_priority", .text).notNull().defaults(to: "medium")
                t.column("estimated_minutes", .integer)
            }
            try db.create(indexOn: "template_tasks", columns: ["template_id"])
        }

        // v11: エージェント階層タイプ追加
        // 参照: docs/requirements/AGENTS.md - エージェントタイプ（Manager/Worker）
        migrator.registerMigration("v11_agent_hierarchy_type") { db in
            // hierarchy_type カラムを追加（デフォルト: worker）
            try db.alter(table: "agents") { t in
                t.add(column: "hierarchy_type", .text).defaults(to: "worker")
            }
        }

        // v12: Internal Audit機能
        // 参照: docs/requirements/AUDIT.md
        migrator.registerMigration("v12_internal_audit") { db in
            // internal_audits テーブル
            try db.create(table: "internal_audits", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("description", .text).defaults(to: "")
                t.column("status", .text).notNull().defaults(to: "active")
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }
            try db.create(indexOn: "internal_audits", columns: ["status"])

            // audit_rules テーブル
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
        migrator.registerMigration("v13_lock_functionality") { db in
            // tasks テーブルにロック関連カラムを追加
            try db.alter(table: "tasks") { t in
                t.add(column: "is_locked", .boolean).defaults(to: false)
                t.add(column: "locked_by_audit_id", .text)
                t.add(column: "locked_at", .datetime)
            }
            try db.create(indexOn: "tasks", columns: ["is_locked"])
            try db.create(indexOn: "tasks", columns: ["locked_by_audit_id"])

            // agents テーブルにロック関連カラムを追加
            try db.alter(table: "agents") { t in
                t.add(column: "is_locked", .boolean).defaults(to: false)
                t.add(column: "locked_by_audit_id", .text)
                t.add(column: "locked_at", .datetime)
            }
            try db.create(indexOn: "agents", columns: ["is_locked"])
            try db.create(indexOn: "agents", columns: ["locked_by_audit_id"])
        }

        // v14: 仕様変更 - WorkflowTemplateはプロジェクトスコープ、AuditRuleはインラインauditTasks
        // 参照: docs/requirements/WORKFLOW_TEMPLATES.md - テンプレートはプロジェクトに紐づく
        // 参照: docs/requirements/AUDIT.md - AuditRuleはインラインでタスクを定義
        migrator.registerMigration("v14_template_project_scope_and_audit_inline_tasks") { db in
            // workflow_templates テーブルに project_id を追加
            try db.alter(table: "workflow_templates") { t in
                t.add(column: "project_id", .text)
            }
            try db.create(indexOn: "workflow_templates", columns: ["project_id"])

            // audit_rules テーブルを再構築 (workflow_template_idとtask_assignmentsを削除、audit_tasksを追加)
            // SQLiteはALTER TABLE DROP COLUMNをサポートしないため、テーブル再構築が必要
            // 1. 一時テーブルを作成
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

            // 2. データを移行 (workflow_template_id, task_assignmentsは破棄)
            try db.execute(sql: """
                INSERT INTO audit_rules_new (id, audit_id, name, trigger_type, trigger_config, is_enabled, created_at, updated_at)
                SELECT id, audit_id, name, trigger_type, trigger_config, is_enabled, created_at, updated_at FROM audit_rules
            """)

            // 3. 古いテーブルを削除
            try db.drop(table: "audit_rules")

            // 4. 新しいテーブルをリネーム
            try db.rename(table: "audit_rules_new", to: "audit_rules")

            // 5. インデックス再作成
            try db.create(indexOn: "audit_rules", columns: ["audit_id"])
            try db.create(indexOn: "audit_rules", columns: ["trigger_type"])
            try db.create(indexOn: "audit_rules", columns: ["is_enabled"])
        }

        // v15: 認証基盤（Phase 3-1）
        // 参照: docs/plan/PHASE3_PULL_ARCHITECTURE.md
        migrator.registerMigration("v15_authentication") { db in
            // agent_credentials テーブル
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

            // agent_sessions テーブル
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
        // 参照: docs/plan/PHASE3_PULL_ARCHITECTURE.md - Phase 3-3
        migrator.registerMigration("v16_execution_logs") { db in
            // execution_logs テーブル
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
        // 参照: docs/plan/MULTI_AGENT_USE_CASES.md - AIタイプ
        migrator.registerMigration("v17_ai_type") { db in
            // ai_type カラムを追加（claude, gemini, openai, other）
            try db.alter(table: "agents") { t in
                t.add(column: "ai_type", .text)
            }
        }

        try migrator.migrate(dbQueue)
    }
}
