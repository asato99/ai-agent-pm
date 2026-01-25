-- E2E Test Data Seed Script
-- This script inserts test data required for E2E tests
--
-- IMPORTANT: This script should ONLY be run against the test database!
-- Use setup-test-data.sh which ensures the correct database is used.
-- NEVER run this directly against the production database.

-- Clear existing test data (if any)
DELETE FROM contexts WHERE id LIKE 'ctx-%';
DELETE FROM execution_logs WHERE id LIKE 'log-%';
DELETE FROM sessions WHERE id LIKE 'session-%';
DELETE FROM tasks WHERE id LIKE 'task-%' OR id LIKE 'task-2%';
DELETE FROM agent_credentials WHERE agent_id IN ('manager-1', 'worker-1', 'worker-2', 'owner-1');
DELETE FROM agents WHERE id IN ('manager-1', 'worker-1', 'worker-2', 'owner-1');
DELETE FROM projects WHERE id IN ('project-1', 'project-2');

-- Insert test agents
INSERT INTO agents (id, name, role, type, status, hierarchy_type, parent_agent_id, role_type, max_parallel_tasks, capabilities, system_prompt, kick_method, created_at, updated_at)
VALUES
  ('owner-1', 'Owner', 'System Owner', 'human', 'active', 'owner', NULL, 'general', 1, NULL, NULL, 'cli', datetime('now'), datetime('now')),
  ('manager-1', 'Manager A', 'Backend Manager', 'ai', 'active', 'manager', 'owner-1', 'general', 5, '["management","review"]', 'You are a backend manager.', 'mcp', datetime('now'), datetime('now')),
  ('worker-1', 'Worker 1', 'Backend Developer', 'ai', 'active', 'worker', 'manager-1', 'general', 3, '["coding","testing"]', 'You are a backend developer.', 'mcp', datetime('now'), datetime('now')),
  ('worker-2', 'Worker 2', 'Frontend Developer', 'ai', 'inactive', 'worker', 'manager-1', 'general', 3, '["coding","ui"]', 'You are a frontend developer.', 'mcp', datetime('now'), datetime('now'));

-- Insert agent credentials
-- Hash is SHA256(passkey + salt) where passkey="test-passkey" and salt="salt"
-- Hash: SHA256("test-passkeysalt") = 2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519
INSERT INTO agent_credentials (id, agent_id, passkey_hash, salt, raw_passkey, created_at)
VALUES
  ('cred-owner-1', 'owner-1', '2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519', 'salt', 'test-passkey', datetime('now')),
  ('cred-manager-1', 'manager-1', '2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519', 'salt', 'test-passkey', datetime('now')),
  ('cred-worker-1', 'worker-1', '2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519', 'salt', 'test-passkey', datetime('now')),
  ('cred-worker-2', 'worker-2', '2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519', 'salt', 'test-passkey', datetime('now'));

-- Insert test projects
INSERT INTO projects (id, name, description, status, created_at, updated_at)
VALUES
  ('project-1', 'ECサイト開発', 'ECサイトの新規開発プロジェクト', 'active', datetime('now'), datetime('now')),
  ('project-2', 'モバイルアプリ', 'iOSアプリ開発', 'active', datetime('now'), datetime('now'));

-- Insert test tasks for project-1 (12 total)
-- Hierarchy structure for testing:
--   task-1 (API実装) - L0 root, has dependency on task-2
--     └── task-3 (エンドポイント実装) - L1 child of task-1
--           └── task-4 (ユーザーAPI) - L2 grandchild
--   task-5 (ブロックされたタスク) - blocked by task-1
INSERT INTO tasks (id, project_id, title, description, status, priority, assignee_id, created_by_agent_id, dependencies, parent_task_id, created_at, updated_at)
VALUES
  ('task-1', 'project-1', 'API実装', 'REST APIエンドポイントの実装', 'in_progress', 'high', 'worker-1', 'manager-1', '["task-2"]', NULL, datetime('now'), datetime('now')),
  ('task-2', 'project-1', 'DB設計', 'データベーススキーマの設計', 'done', 'medium', 'worker-2', 'manager-1', '[]', NULL, datetime('now'), datetime('now')),
  ('task-3', 'project-1', 'エンドポイント実装', 'REST APIエンドポイントの詳細実装', 'todo', 'medium', 'worker-1', 'manager-1', '[]', 'task-1', datetime('now'), datetime('now')),
  ('task-4', 'project-1', 'ユーザーAPI', 'ユーザー関連APIの実装', 'backlog', 'low', NULL, 'manager-1', '[]', 'task-3', datetime('now'), datetime('now')),
  ('task-5', 'project-1', 'ブロックされたタスク', '依存関係でブロック中', 'blocked', 'high', 'worker-1', 'manager-1', '["task-1"]', NULL, datetime('now'), datetime('now')),
  ('task-6', 'project-1', 'カート機能', 'ショッピングカートの実装', 'done', 'high', 'worker-2', 'manager-1', '[]', NULL, datetime('now'), datetime('now')),
  ('task-7', 'project-1', '決済連携', '外部決済サービスとの連携', 'in_progress', 'high', 'manager-1', 'manager-1', '["task-6"]', NULL, datetime('now'), datetime('now')),
  ('task-8', 'project-1', '商品管理', '商品CRUD機能', 'done', 'medium', 'worker-1', 'manager-1', '[]', NULL, datetime('now'), datetime('now')),
  ('task-9', 'project-1', '注文管理', '注文処理フロー', 'in_progress', 'medium', 'manager-1', 'manager-1', '["task-7"]', NULL, datetime('now'), datetime('now')),
  ('task-10', 'project-1', 'メール通知', '注文確認メールの送信', 'blocked', 'medium', 'worker-2', 'manager-1', '["task-9"]', NULL, datetime('now'), datetime('now')),
  ('task-11', 'project-1', 'レスポンシブ対応', 'モバイル対応UI', 'todo', 'low', NULL, 'manager-1', '["task-3"]', NULL, datetime('now'), datetime('now')),
  ('task-12', 'project-1', 'パフォーマンス最適化', 'クエリ最適化・キャッシュ', 'backlog', 'low', NULL, 'manager-1', '[]', NULL, datetime('now'), datetime('now'));

-- Tasks for project-2 (8 total)
INSERT INTO tasks (id, project_id, title, description, status, priority, assignee_id, created_by_agent_id, dependencies, created_at, updated_at)
VALUES
  ('task-201', 'project-2', 'UI設計', 'アプリUI/UXの設計', 'done', 'high', 'manager-1', 'manager-1', '[]', datetime('now'), datetime('now')),
  ('task-202', 'project-2', 'ホーム画面', 'ホーム画面の実装', 'done', 'high', 'worker-1', 'manager-1', '["task-201"]', datetime('now'), datetime('now')),
  ('task-203', 'project-2', 'プロフィール画面', 'プロフィール画面の実装', 'done', 'medium', 'worker-1', 'manager-1', '["task-201"]', datetime('now'), datetime('now')),
  ('task-204', 'project-2', '設定画面', '設定画面の実装', 'done', 'medium', 'worker-2', 'manager-1', '["task-201"]', datetime('now'), datetime('now')),
  ('task-205', 'project-2', 'API連携', 'バックエンドAPI連携', 'done', 'high', 'worker-1', 'manager-1', '["task-202"]', datetime('now'), datetime('now')),
  ('task-206', 'project-2', 'プッシュ通知', 'プッシュ通知の実装', 'done', 'medium', 'worker-2', 'manager-1', '["task-205"]', datetime('now'), datetime('now')),
  ('task-207', 'project-2', 'オフライン対応', 'オフライン時の対応', 'done', 'low', 'worker-1', 'manager-1', '["task-205"]', datetime('now'), datetime('now')),
  ('task-208', 'project-2', 'App Store申請', 'App Store審査準備', 'in_progress', 'high', 'manager-1', 'manager-1', '["task-202","task-203","task-204"]', datetime('now'), datetime('now'));

-- Insert test sessions for execution logs and contexts
INSERT INTO sessions (id, project_id, agent_id, started_at, ended_at, status)
VALUES
  ('session-1', 'project-1', 'worker-1', datetime('now', '-2 hours'), datetime('now', '-1 hour'), 'ended'),
  ('session-2', 'project-1', 'worker-1', datetime('now', '-1 hour'), NULL, 'active'),
  ('session-3', 'project-1', 'manager-1', datetime('now', '-30 minutes'), NULL, 'active');

-- Insert test execution logs for task-1 (API実装)
INSERT INTO execution_logs (id, task_id, agent_id, status, started_at, completed_at, exit_code, duration_seconds, log_file_path, error_message, reported_provider, reported_model, model_verified)
VALUES
  ('log-1', 'task-1', 'worker-1', 'completed', datetime('now', '-2 hours'), datetime('now', '-1 hour 45 minutes'), 0, 900.5, '/logs/task-1/log-1.txt', NULL, 'anthropic', 'claude-sonnet-4-20250514', 1),
  ('log-2', 'task-1', 'worker-1', 'failed', datetime('now', '-1 hour 30 minutes'), datetime('now', '-1 hour 25 minutes'), 1, 300.0, '/logs/task-1/log-2.txt', 'Test failure: assertion failed at line 42', 'anthropic', 'claude-sonnet-4-20250514', 1),
  ('log-3', 'task-1', 'worker-1', 'running', datetime('now', '-10 minutes'), NULL, NULL, NULL, NULL, NULL, 'anthropic', 'claude-sonnet-4-20250514', NULL);

-- Insert test contexts for task-1 (API実装)
INSERT INTO contexts (id, task_id, session_id, agent_id, progress, findings, blockers, next_steps, created_at, updated_at)
VALUES
  ('ctx-1', 'task-1', 'session-1', 'worker-1', 'エンドポイント設計完了', 'REST API設計パターンを採用', NULL, 'コントローラー実装を開始', datetime('now', '-2 hours'), datetime('now', '-1 hour 45 minutes')),
  ('ctx-2', 'task-1', 'session-2', 'worker-1', 'コントローラー実装中', 'バリデーション層の追加が必要', 'テストデータの準備が必要', 'バリデーション実装後、テスト作成', datetime('now', '-1 hour'), datetime('now', '-30 minutes')),
  ('ctx-3', 'task-1', 'session-3', 'manager-1', NULL, NULL, 'Worker-1のテストデータ待ち', 'テストデータ準備を依頼済み', datetime('now', '-20 minutes'), datetime('now', '-20 minutes'));
