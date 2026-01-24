-- UC018-B: Parent Agent Auto-Approval Test Data
-- 上位エージェント（親）がチャットで依頼した場合、タスクは自動承認される
--
-- シナリオ:
-- - 佐藤 (human Tech Lead): Worker-01の親エージェント、依頼者
-- - Worker-01 (AI): worker - 依頼を受けてタスクを作成
-- - タスクは自動的にapprovedになる（pending_approvalではない）
--
-- IMPORTANT: Only run against test database!
--
-- ⚠️⚠️⚠️ 警告: 期待結果のシードは絶対禁止 ⚠️⚠️⚠️
--
-- このファイルには「前提条件」のみをシードすること。
-- テストで検証すべきデータ（タスク作成、ステータス変更等）は絶対にシードしない。
--
-- ❌ 禁止: approvedステータスのタスクをシードして「自動承認される」テストを通す
-- ✅ 許可: エージェント、プロジェクト、セッション等の前提条件のみ
--
-- 違反すると統合テストの価値がゼロになる。

-- Clear existing UC018B test data
-- Note: chat_messages don't exist in DB (stored in files), cleared by test script
DELETE FROM pending_agent_purposes WHERE project_id = 'uc018b-project';
DELETE FROM agent_sessions WHERE agent_id IN ('uc018b-sato', 'uc018b-worker-01');
DELETE FROM tasks WHERE id LIKE 'uc018b-%' OR project_id = 'uc018b-project';
DELETE FROM agent_credentials WHERE agent_id IN ('uc018b-sato', 'uc018b-worker-01');
DELETE FROM agents WHERE id IN ('uc018b-sato', 'uc018b-worker-01');
DELETE FROM project_agents WHERE project_id = 'uc018b-project';
DELETE FROM projects WHERE id = 'uc018b-project';

-- Insert test agents
-- 佐藤: Tech Lead (human), Worker-01の親エージェント
-- Worker-01: AI worker, 佐藤の部下
INSERT INTO agents (id, name, role, type, status, hierarchy_type, parent_agent_id, role_type, max_parallel_tasks, capabilities, system_prompt, kick_method, created_at, updated_at)
VALUES
  ('uc018b-sato', '佐藤', 'Tech Lead', 'human', 'active', 'manager', NULL, 'general', 5, '["management", "review"]', 'You are a tech lead.', 'mcp', datetime('now'), datetime('now')),
  ('uc018b-worker-01', 'Worker-01', 'Developer', 'ai', 'active', 'worker', 'uc018b-sato', 'general', 3, '["coding", "implementation"]', 'You are an AI developer.', 'mcp', datetime('now'), datetime('now'));

-- Insert agent credentials
-- Hash: SHA256("test-passkeysalt") = 2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519
INSERT INTO agent_credentials (id, agent_id, passkey_hash, salt, raw_passkey, created_at)
VALUES
  ('cred-uc018b-sato', 'uc018b-sato', '2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519', 'salt', 'test-passkey', datetime('now')),
  ('cred-uc018b-worker-01', 'uc018b-worker-01', '2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519', 'salt', 'test-passkey', datetime('now'));

-- Insert test project
INSERT INTO projects (id, name, description, status, working_directory, created_at, updated_at)
VALUES
  ('uc018b-project', 'Parent Auto-Approval Test Project', 'Project for UC018-B parent agent auto-approval testing', 'active', '/tmp/uc018b_webui_work', datetime('now'), datetime('now'));

-- Assign all agents to project
INSERT INTO project_agents (project_id, agent_id, assigned_at)
VALUES
  ('uc018b-project', 'uc018b-sato', datetime('now')),
  ('uc018b-project', 'uc018b-worker-01', datetime('now'));

-- ⚠️ chat sessionはシードしない
-- チャットパネルを開くとPOST /chat/startが呼ばれ、セッションが作成される
-- Coordinatorがエージェントをspawnするのは、セッションがwaiting_for_kickの状態のとき
-- セッションを事前にactiveでシードすると、Coordinatorはalready_runningと判断してspawnしない

-- タスクはシードしない
-- Worker-01がrequest_taskを呼び出したとき、上位（佐藤）からの依頼なら
-- approval_status = 'approved' で作成されるべき
-- この機能が未実装の場合、テストStep 3が失敗する
