-- UC019 Integration Test Data Seed Script
-- Reference: docs/usecase/UC019_ChatTaskSimultaneousExecution.md
--
-- This script sets up test data for UC019: チャットとタスクの同時実行
-- Test flow:
-- 1. Owner logs in via Web UI
-- 2. Owner opens chat with Worker (chat session starts)
-- 3. Owner requests task creation via chat
-- 4. Worker creates task in backlog
-- 5. Owner moves task to in_progress (task session starts)
-- 6. Owner sends progress check message via chat (while task is running)
-- 7. Worker responds to chat (verifies both sessions work simultaneously)
-- 8. Task completes
--
-- Key verification points:
-- - Chat session is maintained when task moves to in_progress
-- - Both chat and task sessions can run simultaneously for the same agent
-- - Chat responses work during task execution
--
-- IMPORTANT: Only run against test database!

-- Clear existing UC019 test data
-- Note: Some tables may not exist in all environments, so we use conditional deletes
DELETE FROM pending_agent_purposes WHERE agent_id LIKE 'uc019-%';
DELETE FROM agent_sessions WHERE agent_id LIKE 'uc019-%';
DELETE FROM tasks WHERE id LIKE 'uc019-%' OR project_id = 'uc019-project';
DELETE FROM agent_credentials WHERE agent_id LIKE 'uc019-%';
DELETE FROM project_agents WHERE project_id = 'uc019-project';
DELETE FROM agents WHERE id LIKE 'uc019-%';
DELETE FROM projects WHERE id = 'uc019-project';

-- Insert test agents for UC019
INSERT INTO agents (id, name, role, type, status, hierarchy_type, parent_agent_id, role_type, max_parallel_tasks, capabilities, system_prompt, kick_method, created_at, updated_at)
VALUES
  -- Human Owner (project owner for web UI login)
  ('uc019-owner', 'UC019 Owner', 'Project Owner', 'human', 'active', 'owner', NULL, 'general', 1, NULL, NULL, 'cli', datetime('now'), datetime('now')),
  -- AI Worker (handles both chat and task)
  ('uc019-worker', 'UC019 Worker', 'Developer', 'ai', 'active', 'worker', 'uc019-owner', 'general', 1, '["chat", "task", "code"]',
   'あなたは開発ワーカーです。チャット応答とタスク実行の両方を担当します。

## チャット応答時 (purpose=chat)
get_pending_messages でメッセージを取得し、respond_chat で応答を送信してください。

タスク作成依頼を受けた場合:
1. create_task でタスクを作成（status: backlog, assignee: 自分）
2. 「タスクを作成しました」と応答

進捗確認メッセージの場合:
- 「現在タスクを実行中です」など簡潔に応答

get_next_action が exit を返した場合は logout してください。

## タスク実行時 (purpose=task)
get_next_action でタスク情報を取得し、タスクを実行してください。
タスク完了後は update_task_status で done に更新してください。

【重要】チャットとタスクは別セッションで同時に実行されます。
それぞれのセッションで適切に応答してください。',
   'cli', datetime('now'), datetime('now'));

-- Insert agent credentials (passkey: test-passkey)
-- Hash is SHA256 of 'test-passkey' with salt 'salt'
INSERT INTO agent_credentials (id, agent_id, passkey_hash, salt, raw_passkey, created_at)
VALUES
  ('cred-uc019-owner', 'uc019-owner', '2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519', 'salt', 'test-passkey', datetime('now')),
  ('cred-uc019-worker', 'uc019-worker', '2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519', 'salt', 'test-passkey', datetime('now'));

-- Insert test project
INSERT INTO projects (id, name, description, status, working_directory, created_at, updated_at)
VALUES
  ('uc019-project', 'UC019 Chat+Task Simultaneous Test', 'チャットとタスクの同時実行テスト用プロジェクト', 'active', '/tmp/uc019', datetime('now'), datetime('now'));

-- Assign agents to project
INSERT INTO project_agents (project_id, agent_id, assigned_at)
VALUES
  ('uc019-project', 'uc019-owner', datetime('now')),
  ('uc019-project', 'uc019-worker', datetime('now'));

-- Note: Tasks will be created dynamically during test via chat request
-- No pre-existing tasks needed
