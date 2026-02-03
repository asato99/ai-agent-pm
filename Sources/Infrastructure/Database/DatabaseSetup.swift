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

        // 既存DBがある場合、外部キー無効状態でクリーンアップを先に実行
        // （マイグレーション前に外部キー違反を解消）
        if FileManager.default.fileExists(atPath: path) {
            try cleanupOrphanedRecords(at: path)
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

    /// 外部キー無効状態で孤立レコードをクリーンアップ
    /// マイグレーション前に外部キー違反を解消する
    private static func cleanupOrphanedRecords(at path: String) throws {
        var cleanupConfig = Configuration()
        cleanupConfig.busyMode = .timeout(5.0)
        cleanupConfig.prepareDatabase { db in
            // 外部キーを無効化した状態でクリーンアップ
            try db.execute(sql: "PRAGMA foreign_keys = OFF")
        }

        let cleanupQueue = try DatabaseQueue(path: path, configuration: cleanupConfig)
        try cleanupQueue.write { db in
            let hasTasks = try tableExists(db, name: "tasks")
            let hasAgents = try tableExists(db, name: "agents")
            let hasProjects = try tableExists(db, name: "projects")

            // execution_logs の孤立レコードを削除
            if try tableExists(db, name: "execution_logs") && hasTasks {
                try db.execute(sql: """
                    DELETE FROM execution_logs
                    WHERE task_id NOT IN (SELECT id FROM tasks)
                """)
            }

            // contexts の孤立レコードを削除
            if try tableExists(db, name: "contexts") && hasTasks {
                try db.execute(sql: """
                    DELETE FROM contexts
                    WHERE task_id NOT IN (SELECT id FROM tasks)
                """)
            }

            // agent_sessions の孤立レコードを削除
            if try tableExists(db, name: "agent_sessions") && hasAgents {
                try db.execute(sql: """
                    DELETE FROM agent_sessions
                    WHERE agent_id NOT IN (SELECT id FROM agents)
                """)
            }

            // handoffs の孤立レコードを削除
            if try tableExists(db, name: "handoffs") && hasTasks {
                try db.execute(sql: """
                    DELETE FROM handoffs
                    WHERE task_id NOT IN (SELECT id FROM tasks)
                """)
            }

            // tasks の孤立レコードを削除（存在しないプロジェクト参照）
            if hasTasks && hasProjects {
                try db.execute(sql: """
                    DELETE FROM tasks
                    WHERE project_id NOT IN (SELECT id FROM projects)
                """)
            }
        }
    }

    /// テーブルが存在するかチェック
    private static func tableExists(_ db: Database, name: String) throws -> Bool {
        try Bool.fetchOne(db, sql: """
            SELECT COUNT(*) > 0 FROM sqlite_master
            WHERE type = 'table' AND name = ?
        """, arguments: [name]) ?? false
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

        // v18: プロジェクト×エージェント割り当てテーブル
        // 参照: docs/requirements/PROJECTS.md - エージェント割り当て
        // 参照: docs/usecase/UC004_MultiProjectSameAgent.md
        migrator.registerMigration("v18_project_agents") { db in
            // project_agents テーブル（多対多関係）
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
        // 参照: docs/plan/PHASE4_COORDINATOR_ARCHITECTURE.md - (agent_id, project_id) 単位のセッション管理
        migrator.registerMigration("v19_session_project_id") { db in
            // project_id カラムを追加
            // Note: 既存データのために NULL 許容、新規作成時は必須
            try db.alter(table: "agent_sessions") { t in
                t.add(column: "project_id", .text)
            }
            // (agent_id, project_id) の組み合わせでインデックスを作成
            try db.create(indexOn: "agent_sessions", columns: ["agent_id", "project_id"])
        }

        // v20: モデル検証フィールド追加（AgentSession）
        // Agent Instanceが申告したモデルをApp側で検証するための情報を保存
        migrator.registerMigration("v20_model_verification") { db in
            try db.alter(table: "agent_sessions") { t in
                // Agent Instanceが申告したプロバイダー（claude, gemini, openai, custom）
                t.add(column: "reported_provider", .text)
                // Agent Instanceが申告したモデルID
                t.add(column: "reported_model", .text)
                // モデル検証結果（nil=未検証, true=一致, false=不一致）
                t.add(column: "model_verified", .boolean)
                // モデル検証日時
                t.add(column: "model_verified_at", .datetime)
            }
        }

        // v21: モデル検証フィールド追加（ExecutionLog）
        // タスク実行ごとにどのモデルが使用されたかを記録
        migrator.registerMigration("v21_execution_log_model_info") { db in
            try db.alter(table: "execution_logs") { t in
                // Agent Instanceが申告したプロバイダー
                t.add(column: "reported_provider", .text)
                // Agent Instanceが申告したモデルID
                t.add(column: "reported_model", .text)
                // モデル検証結果
                t.add(column: "model_verified", .boolean)
            }
        }

        // v22: 起動待ちエージェントの起動理由管理テーブル
        // 参照: docs/design/CHAT_FEATURE.md - MCP連携設計
        // チャットメッセージ送信時に purpose=chat を記録し、
        // Coordinator 経由でエージェント起動 → authenticate 時に参照
        migrator.registerMigration("v22_pending_agent_purposes") { db in
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
        // 参照: docs/design/CHAT_FEATURE.md - セッション管理
        // authenticate時にpending_agent_purposesから取得してセッションに設定
        migrator.registerMigration("v23_session_purpose") { db in
            try db.alter(table: "agent_sessions") { t in
                t.add(column: "purpose", .text).defaults(to: "task")
            }
        }

        // v24: アプリケーション設定テーブル（Coordinator Token保存用）
        migrator.registerMigration("v24_app_settings") { db in
            try db.create(table: "app_settings", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("coordinator_token", .text)
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }
        }

        // v25: 起動済みフラグ追加（複数起動防止）
        // 参照: 案A+C+E - 認証失敗時の複数起動防止
        // - started_at: Coordinatorが起動を開始した時刻（nilなら未起動）
        // - createdAtから5分経過でTTL超過として削除
        migrator.registerMigration("v25_pending_purpose_started_at") { db in
            try db.alter(table: "pending_agent_purposes") { t in
                t.add(column: "started_at", .datetime)
            }
        }

        // v26: Pending Purpose TTL設定を追加
        // 参照: 設定画面でタイムアウト時間を変更可能に
        migrator.registerMigration("v26_app_settings_ttl") { db in
            try db.alter(table: "app_settings") { t in
                t.add(column: "pending_purpose_ttl_seconds", .integer).defaults(to: 300) // デフォルト5分
            }
        }

        // v27: パスキーの平文保存（Coordinatorエクスポート用）
        migrator.registerMigration("v27_credential_raw_passkey") { db in
            try db.alter(table: "agent_credentials") { t in
                t.add(column: "raw_passkey", .text) // NULLable: 既存データは後で再設定が必要
            }
        }

        // v28: ステータス変更追跡フィールド
        // 参照: docs/plan/BLOCKED_TASK_RECOVERY.md
        migrator.registerMigration("v28_status_change_tracking") { db in
            try db.alter(table: "tasks") { t in
                t.add(column: "status_changed_by_agent_id", .text)
                    .references("agents", onDelete: .setNull)
                t.add(column: "status_changed_at", .datetime)
                t.add(column: "blocked_reason", .text)
            }
            try db.create(indexOn: "tasks", columns: ["status_changed_by_agent_id"])
        }

        // v29: provider/model_id 直接保存（Enumパース依存を排除）
        migrator.registerMigration("v29_agent_provider_model") { db in
            try db.alter(table: "agents") { t in
                t.add(column: "provider", .text)   // "claude", "gemini", "openai", etc.
                t.add(column: "model_id", .text)   // "gemini-2.5-pro", "claude-opus-4-20250514", etc.
            }

            // 既存データのマイグレーション: ai_type から provider/model_id を設定
            // claude-* → provider: claude
            try db.execute(sql: """
                UPDATE agents SET provider = 'claude'
                WHERE ai_type LIKE 'claude-%' AND provider IS NULL
            """)
            // gemini-* → provider: gemini
            try db.execute(sql: """
                UPDATE agents SET provider = 'gemini'
                WHERE ai_type LIKE 'gemini-%' AND provider IS NULL
            """)
            // gpt-* → provider: openai
            try db.execute(sql: """
                UPDATE agents SET provider = 'openai'
                WHERE ai_type LIKE 'gpt-%' AND provider IS NULL
            """)
            // その他 → provider: custom
            try db.execute(sql: """
                UPDATE agents SET provider = 'custom'
                WHERE provider IS NULL
            """)

            // model_id: ai_type の値をそのままコピー（日付サフィックス付きのフルIDに更新が必要な場合は別途対応）
            try db.execute(sql: """
                UPDATE agents SET model_id = ai_type
                WHERE model_id IS NULL AND ai_type IS NOT NULL
            """)
        }

        // v30: システムエージェント追加
        // 参照: Sources/Domain/ValueObjects/IDs.swift - AgentID.systemUser, AgentID.systemAuto
        // UIからのステータス変更時に status_changed_by_agent_id に設定される
        migrator.registerMigration("v30_system_agents") { db in
            // system:user - ユーザー（UI）からの操作を示す特別なエージェント
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
            // system:auto - システム自動処理を示す特別なエージェント
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

        // v31: タスク作成者追跡フィールド
        // 委譲タスク判別用: createdByAgentId != assigneeId → 委譲されたタスク
        migrator.registerMigration("v31_task_created_by") { db in
            try db.alter(table: "tasks") { t in
                t.add(column: "created_by_agent_id", .text)
                    .references("agents", onDelete: .setNull)
            }
            try db.create(indexOn: "tasks", columns: ["created_by_agent_id"])
        }

        // v32: リモートアクセス設定
        // 参照: docs/design/MULTI_DEVICE_IMPLEMENTATION_PLAN.md - フェーズ1.1
        // REST APIを0.0.0.0にバインドしてLAN内の別端末からアクセス可能にする
        migrator.registerMigration("v32_allow_remote_access") { db in
            try db.alter(table: "app_settings") { t in
                t.add(column: "allow_remote_access", .boolean).defaults(to: false)
            }
        }

        // v33: エージェントワーキングディレクトリ設定
        // 参照: docs/design/MULTI_DEVICE_IMPLEMENTATION_PLAN.md - フェーズ2.1
        // エージェントごと、プロジェクトごとのワーキングディレクトリを管理
        migrator.registerMigration("v33_agent_working_directories") { db in
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
            // (agent_id, project_id) の組み合わせで一意制約
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
        // 参照: Web UIセッション管理 - アイドルタイムアウト
        // 最終アクティビティ日時を記録し、一定時間操作がなければセッション無効化
        migrator.registerMigration("v34_session_last_activity") { db in
            try db.alter(table: "agent_sessions") { t in
                t.add(column: "last_activity_at", .datetime)
            }
            // 既存セッションは created_at で初期化
            try db.execute(sql: """
                UPDATE agent_sessions SET last_activity_at = created_at
                WHERE last_activity_at IS NULL
            """)
        }

        // v35: 孤立した execution_logs のクリーンアップ
        // 外部キー制約違反を防ぐため、存在しないタスクを参照するレコードを削除
        migrator.registerMigration("v35_cleanup_orphaned_execution_logs") { db in
            try db.execute(sql: """
                DELETE FROM execution_logs
                WHERE task_id NOT IN (SELECT id FROM tasks)
            """)
        }

        // v36: 通知システム
        // 参照: docs/design/NOTIFICATION_SYSTEM.md
        // 参照: docs/usecase/UC010_TaskInterruptByStatusChange.md
        migrator.registerMigration("v36_notifications") { db in
            try db.create(table: "notifications", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("target_agent_id", .text).notNull()
                t.column("target_project_id", .text).notNull()
                t.column("type", .text).notNull() // status_change, interrupt, message
                t.column("action", .text).notNull() // blocked, cancel, pause, user_message, etc.
                t.column("task_id", .text) // Optional: 関連タスクID
                t.column("message", .text).notNull() // 人間可読メッセージ
                t.column("instruction", .text).notNull() // エージェントへの指示
                t.column("created_at", .datetime).notNull()
                t.column("is_read", .boolean).notNull().defaults(to: false)
                t.column("read_at", .datetime)
            }
            // (target_agent_id, target_project_id, is_read) で未読通知を高速検索
            try db.create(
                index: "idx_notifications_unread",
                on: "notifications",
                columns: ["target_agent_id", "target_project_id", "is_read"]
            )
            // created_at でソート用
            try db.create(indexOn: "notifications", columns: ["created_at"])
        }

        // v37: セッション状態フィールド追加（UC015: チャットセッション終了）
        // 参照: docs/design/CHAT_SESSION_MAINTENANCE_MODE.md - Section 6
        // 状態遷移: active → terminating → ended
        migrator.registerMigration("v37_session_state") { db in
            try db.alter(table: "agent_sessions") { t in
                // デフォルト値は "active"（既存データとの互換性）
                t.add(column: "state", .text).defaults(to: "active")
            }
        }

        // v38: AI-to-AI会話管理テーブル（UC016）
        // 参照: docs/design/AI_TO_AI_CONVERSATION.md
        // エージェント間の明示的な会話ライフサイクルを管理
        migrator.registerMigration("v38_conversations") { db in
            // conversations テーブル
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
            // プロジェクト内の会話一覧取得用
            try db.create(indexOn: "conversations", columns: ["project_id"])
            // 特定エージェントの会話検索用
            try db.create(indexOn: "conversations", columns: ["initiator_agent_id"])
            try db.create(indexOn: "conversations", columns: ["participant_agent_id"])
            // アクティブ会話の検索用
            try db.create(indexOn: "conversations", columns: ["state"])

            // pending_agent_purposes に conversation_id を追加
            // AI-to-AI会話開始時に会話IDを紐付け
            try db.alter(table: "pending_agent_purposes") { t in
                t.add(column: "conversation_id", .text)
            }
        }

        // v39: conversations に max_turns を追加
        // AI-to-AI会話のターン数制限機能
        // 参照: docs/design/AI_TO_AI_CONVERSATION.md
        migrator.registerMigration("v39_conversations_max_turns") { db in
            try db.alter(table: "conversations") { t in
                // max_turns: 最大ターン数（1メッセージ = 1ターン）
                // デフォルト20（10往復）、システム上限40（20往復）
                t.add(column: "max_turns", .integer).notNull().defaults(to: 20)
            }
        }

        // v40: タスク依頼・承認機能
        // 参照: docs/design/TASK_REQUEST_APPROVAL.md
        migrator.registerMigration("v40_task_approval") { db in
            try db.alter(table: "tasks") { t in
                // 依頼者のエージェントID（直接作成時はNULL）
                t.add(column: "requester_id", .text)
                // 承認ステータス（approved, pending_approval, rejected）
                t.add(column: "approval_status", .text).notNull().defaults(to: "approved")
                // 却下理由（rejected時のみ）
                t.add(column: "rejected_reason", .text)
                // 承認者のエージェントID
                t.add(column: "approved_by", .text)
                // 承認日時
                t.add(column: "approved_at", .datetime)
            }
            // 承認待ちタスク検索用インデックス
            try db.create(indexOn: "tasks", columns: ["approval_status"])
            try db.create(indexOn: "tasks", columns: ["requester_id"])
        }

        // v41: pending_agent_purposes の主キーに purpose を追加
        // 同一エージェントでタスクとチャットを同時に起動可能にする
        migrator.registerMigration("v41_pending_purpose_composite_key") { db in
            // SQLiteでは主キー変更不可のため、テーブル再作成
            // 1. 新テーブル作成
            try db.create(table: "pending_agent_purposes_new") { t in
                t.column("agent_id", .text).notNull()
                t.column("project_id", .text).notNull()
                t.column("purpose", .text).notNull() // "task" | "chat"
                t.column("created_at", .datetime).notNull()
                t.column("started_at", .datetime)
                t.column("conversation_id", .text)
                // 新しい複合主キー: (agent_id, project_id, purpose)
                t.primaryKey(["agent_id", "project_id", "purpose"])
            }

            // 2. データをコピー
            try db.execute(sql: """
                INSERT INTO pending_agent_purposes_new
                (agent_id, project_id, purpose, created_at, started_at, conversation_id)
                SELECT agent_id, project_id, purpose, created_at, started_at, conversation_id
                FROM pending_agent_purposes
            """)

            // 3. 古いテーブルを削除
            try db.drop(table: "pending_agent_purposes")

            // 4. 新テーブルをリネーム
            try db.rename(table: "pending_agent_purposes_new", to: "pending_agent_purposes")

            // 5. インデックス再作成
            try db.create(indexOn: "pending_agent_purposes", columns: ["agent_id"])
            try db.create(indexOn: "pending_agent_purposes", columns: ["project_id"])
        }

        // v42: project_agents に spawn_started_at 列を追加
        // 参照: docs/design/SESSION_SPAWN_ARCHITECTURE.md
        // 重複スポーン防止のための最小限の構成
        migrator.registerMigration("v42_project_agents_spawn_started_at") { db in
            try db.alter(table: "project_agents") { t in
                // nullable列はデフォルトでNULLになるため.defaults()不要
                t.add(column: "spawn_started_at", .datetime)
            }
        }

        // v43: pending_agent_purposes テーブル削除
        // 参照: docs/design/SESSION_SPAWN_ARCHITECTURE.md
        // spawn_started_at 列で置き換えられたため不要
        migrator.registerMigration("v43_drop_pending_agent_purposes") { db in
            try db.drop(table: "pending_agent_purposes")
        }

        // v44: スキル定義とエージェントスキル割り当て
        // 参照: docs/design/AGENT_SKILLS.md
        // エージェントにスキル（カスタムコマンド）を割り当てる機能
        migrator.registerMigration("v44_skill_definitions") { db in
            // スキル定義テーブル
            try db.create(table: "skill_definitions", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("description", .text).notNull().defaults(to: "")
                t.column("directory_name", .text).notNull().unique()
                t.column("content", .text).notNull()
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }
            // ディレクトリ名で検索用
            try db.create(indexOn: "skill_definitions", columns: ["directory_name"])

            // エージェントスキル割り当てテーブル（多対多）
            try db.create(table: "agent_skill_assignments", ifNotExists: true) { t in
                t.column("agent_id", .text).notNull()
                    .references("agents", onDelete: .cascade)
                t.column("skill_id", .text).notNull()
                    .references("skill_definitions", onDelete: .cascade)
                t.column("assigned_at", .datetime).notNull()
                t.primaryKey(["agent_id", "skill_id"])
            }
            // エージェント別のスキル検索用
            try db.create(indexOn: "agent_skill_assignments", columns: ["agent_id"])
            // スキル別のエージェント検索用
            try db.create(indexOn: "agent_skill_assignments", columns: ["skill_id"])
        }

        // v45: スキル定義をアーカイブ形式に移行
        // 参照: docs/design/AGENT_SKILLS.md - アーカイブ形式
        // content TEXT → archive_data BLOB に変更
        // スクリプト・テンプレート等を含む完全なスキルパッケージをサポート
        migrator.registerMigration("v45_skill_archive_format") { db in
            // 1. 新しいテーブルを作成（archive_data BLOB）
            try db.create(table: "skill_definitions_new") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("description", .text).notNull().defaults(to: "")
                t.column("directory_name", .text).notNull().unique()
                t.column("archive_data", .blob).notNull()
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }

            // 2. 既存データを移行（content をZIPアーカイブに変換）
            // 既存データがある場合、SKILL.md のみを含むZIPを作成
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

                // content を SKILL.md のみを含む ZIP に変換
                let archiveData = Self.createZipArchive(skillMdContent: content)

                try db.execute(sql: """
                    INSERT INTO skill_definitions_new
                    (id, name, description, directory_name, archive_data, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                """, arguments: [id, name, description, directoryName, archiveData, createdAt, updatedAt])
            }

            // 3. 古いテーブルを削除
            try db.drop(table: "skill_definitions")

            // 4. 新テーブルをリネーム
            try db.rename(table: "skill_definitions_new", to: "skill_definitions")

            // 5. インデックス再作成
            try db.create(indexOn: "skill_definitions", columns: ["directory_name"])
        }

        // v46: チャットセッション委譲テーブル
        // タスクセッションからチャットセッションへのコミュニケーション委譲を管理
        // 参照: docs/design/TASK_CHAT_SESSION_SEPARATION.md
        migrator.registerMigration("v46_chat_delegations") { db in
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
            // エージェント×ステータスでの検索用（hasPending、findPendingByAgentId）
            try db.create(indexOn: "chat_delegations", columns: ["agent_id", "project_id", "status"])
            // ステータス別の検索用
            try db.create(indexOn: "chat_delegations", columns: ["status"])
        }

        // v47: タスク会話待機機能のためのtask_idカラム追加
        // 参照: docs/design/TASK_CONVERSATION_AWAIT.md
        migrator.registerMigration("v47_task_conversation_await") { db in
            // agent_sessions に task_id カラムを追加
            try db.execute(sql: """
                ALTER TABLE agent_sessions ADD COLUMN task_id TEXT
                    REFERENCES tasks(id) ON DELETE SET NULL
            """)

            // chat_delegations に task_id カラムを追加
            try db.execute(sql: """
                ALTER TABLE chat_delegations ADD COLUMN task_id TEXT
                    REFERENCES tasks(id) ON DELETE SET NULL
            """)

            // conversations に task_id カラムを追加
            try db.execute(sql: """
                ALTER TABLE conversations ADD COLUMN task_id TEXT
                    REFERENCES tasks(id) ON DELETE SET NULL
            """)

            // task_id での検索用インデックス
            try db.create(indexOn: "conversations", columns: ["task_id"])
        }

        try migrator.migrate(dbQueue)
    }

    /// content文字列からSKILL.mdのみを含むZIPアーカイブを作成
    private static func createZipArchive(skillMdContent: String) -> Data {
        // 簡易的なZIP作成（SKILL.mdのみ、非圧縮）
        // ZIPフォーマット: https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT
        var data = Data()
        let fileName = "SKILL.md"
        let fileNameData = fileName.data(using: .utf8)!
        let contentData = skillMdContent.data(using: .utf8)!

        // Local file header
        data.append(contentsOf: [0x50, 0x4b, 0x03, 0x04]) // signature
        data.append(contentsOf: [0x0a, 0x00]) // version needed (1.0)
        data.append(contentsOf: [0x00, 0x00]) // flags
        data.append(contentsOf: [0x00, 0x00]) // compression (stored)
        data.append(contentsOf: [0x00, 0x00]) // mod time
        data.append(contentsOf: [0x00, 0x00]) // mod date
        let crc = crc32(contentData)
        data.append(contentsOf: withUnsafeBytes(of: crc.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(contentData.count).littleEndian) { Array($0) }) // compressed size
        data.append(contentsOf: withUnsafeBytes(of: UInt32(contentData.count).littleEndian) { Array($0) }) // uncompressed size
        data.append(contentsOf: withUnsafeBytes(of: UInt16(fileNameData.count).littleEndian) { Array($0) }) // file name length
        data.append(contentsOf: [0x00, 0x00]) // extra field length
        data.append(fileNameData)
        let localHeaderOffset = 0
        data.append(contentData)

        // Central directory header
        let centralDirOffset = data.count
        data.append(contentsOf: [0x50, 0x4b, 0x01, 0x02]) // signature
        data.append(contentsOf: [0x14, 0x00]) // version made by
        data.append(contentsOf: [0x0a, 0x00]) // version needed
        data.append(contentsOf: [0x00, 0x00]) // flags
        data.append(contentsOf: [0x00, 0x00]) // compression
        data.append(contentsOf: [0x00, 0x00]) // mod time
        data.append(contentsOf: [0x00, 0x00]) // mod date
        data.append(contentsOf: withUnsafeBytes(of: crc.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(contentData.count).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(contentData.count).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(fileNameData.count).littleEndian) { Array($0) })
        data.append(contentsOf: [0x00, 0x00]) // extra field length
        data.append(contentsOf: [0x00, 0x00]) // file comment length
        data.append(contentsOf: [0x00, 0x00]) // disk number
        data.append(contentsOf: [0x00, 0x00]) // internal file attributes
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // external file attributes
        data.append(contentsOf: withUnsafeBytes(of: UInt32(localHeaderOffset).littleEndian) { Array($0) })
        data.append(fileNameData)
        let centralDirSize = data.count - centralDirOffset

        // End of central directory
        data.append(contentsOf: [0x50, 0x4b, 0x05, 0x06]) // signature
        data.append(contentsOf: [0x00, 0x00]) // disk number
        data.append(contentsOf: [0x00, 0x00]) // disk with central dir
        data.append(contentsOf: [0x01, 0x00]) // entries on disk
        data.append(contentsOf: [0x01, 0x00]) // total entries
        data.append(contentsOf: withUnsafeBytes(of: UInt32(centralDirSize).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(centralDirOffset).littleEndian) { Array($0) })
        data.append(contentsOf: [0x00, 0x00]) // comment length

        return data
    }

    /// CRC-32を計算
    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        let table: [UInt32] = (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}
