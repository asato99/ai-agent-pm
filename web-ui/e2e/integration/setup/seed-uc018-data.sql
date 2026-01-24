-- UC018 Chat Task Request Integration Test Data
-- Reference: docs/usecase/UC018_ChatTaskRequest.md
--
-- This script sets up test data for chat-based task request flow:
-- - 田中 (human PO): requester - sends chat message to Worker-01
-- - Worker-01 (AI): worker - receives request, creates task via MCP
-- - 佐藤 (human Tech Lead): approver - Worker-01's parent, receives notification
--
-- IMPORTANT: Only run against test database!
--
-- ⚠️⚠️⚠️ 警告: 期待結果のシードは絶対禁止 ⚠️⚠️⚠️
--
-- このファイルには「前提条件」のみをシードすること。
-- テストで検証すべきデータ（タスク作成、ステータス変更等）は絶対にシードしない。
--
-- ❌ 禁止: タスクをシードして「タスクが作成される」テストを通す
-- ❌ 禁止: approvedステータスをシードして「自動承認される」テストを通す
-- ✅ 許可: エージェント、プロジェクト、セッション等の前提条件のみ
--
-- 違反すると統合テストの価値がゼロになる。

-- Clear existing UC018 test data
DELETE FROM agent_sessions WHERE agent_id IN ('uc018-tanaka', 'uc018-worker-01', 'uc018-sato');
DELETE FROM tasks WHERE id LIKE 'uc018-%';
DELETE FROM agent_credentials WHERE agent_id IN ('uc018-tanaka', 'uc018-worker-01', 'uc018-sato');
DELETE FROM agents WHERE id IN ('uc018-tanaka', 'uc018-worker-01', 'uc018-sato');
DELETE FROM project_agents WHERE project_id = 'uc018-project';
DELETE FROM projects WHERE id = 'uc018-project';

-- Insert test agents
-- 佐藤: Tech Lead (human), approver, Worker-01's parent
-- Worker-01: AI worker, subordinate of 佐藤
-- 田中: PO (human), requester, not in hierarchy with Worker-01
INSERT INTO agents (id, name, role, type, status, hierarchy_type, parent_agent_id, role_type, max_parallel_tasks, capabilities, system_prompt, kick_method, created_at, updated_at)
VALUES
  ('uc018-sato', '佐藤', 'Tech Lead', 'human', 'active', 'manager', NULL, 'general', 5, '["management", "review"]', 'You are a tech lead.', 'mcp', datetime('now'), datetime('now')),
  ('uc018-worker-01', 'Worker-01', 'Developer', 'ai', 'active', 'worker', 'uc018-sato', 'general', 3, '["coding", "implementation"]', 'You are an AI developer.', 'mcp', datetime('now'), datetime('now')),
  ('uc018-tanaka', '田中', 'Product Owner', 'human', 'active', 'worker', NULL, 'general', 1, '["planning"]', 'You are a product owner.', 'mcp', datetime('now'), datetime('now'));

-- Insert agent credentials
-- Hash: SHA256("test-passkeysalt") = 2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519
INSERT INTO agent_credentials (id, agent_id, passkey_hash, salt, raw_passkey, created_at)
VALUES
  ('cred-uc018-sato', 'uc018-sato', '2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519', 'salt', 'test-passkey', datetime('now')),
  ('cred-uc018-worker-01', 'uc018-worker-01', '2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519', 'salt', 'test-passkey', datetime('now')),
  ('cred-uc018-tanaka', 'uc018-tanaka', '2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519', 'salt', 'test-passkey', datetime('now'));

-- Insert test project
INSERT INTO projects (id, name, description, status, working_directory, created_at, updated_at)
VALUES
  ('uc018-project', 'Chat Task Request Test Project', 'Project for UC018 chat-based task request testing', 'active', '/tmp/uc018_webui_work', datetime('now'), datetime('now'));

-- Assign all agents to project
INSERT INTO project_agents (project_id, agent_id, assigned_at)
VALUES
  ('uc018-project', 'uc018-sato', datetime('now')),
  ('uc018-project', 'uc018-worker-01', datetime('now')),
  ('uc018-project', 'uc018-tanaka', datetime('now'));

-- ⚠️ chat sessionはシードしない
-- チャットパネルを開くとPOST /chat/startが呼ばれ、セッションが作成される
-- Coordinatorがエージェントをspawnするのは、セッションがwaiting_for_kickの状態のとき
-- セッションを事前にactiveでシードすると、Coordinatorはalready_runningと判断してspawnしない

-- ⚠️ タスクはシードしない
-- Worker-01がrequest_taskを呼び出したとき、タスクがpending_approvalで作成されるべき
-- この機能が未実装の場合、テストStep 3が失敗する（それが正しい動作）
