-- UC012 Integration Test Data Seed Script
-- Reference: docs/usecase/UC012_SendMessageFromTaskSession.md
--
-- This script sets up test data for UC012: タスクセッションからのメッセージ送信
-- Test flow:
-- 1. Worker executes task
-- 2. Worker sends message to Human using send_message tool
-- 3. Web UI shows unread indicator on Human agent
-- 4. User opens chat panel and sees the message
--
-- IMPORTANT: Only run against test database!

-- Clear existing UC012 test data
DELETE FROM tasks WHERE id LIKE 'uc012-%';
DELETE FROM agent_credentials WHERE agent_id LIKE 'uc012-%';
DELETE FROM project_agents WHERE project_id = 'uc012-project';
DELETE FROM agents WHERE id LIKE 'uc012-%';
DELETE FROM projects WHERE id = 'uc012-project';

-- Create working directory marker
-- Note: Actual directory creation happens in setup script

-- Insert test agents for UC012
INSERT INTO agents (id, name, role, type, status, hierarchy_type, parent_agent_id, role_type, max_parallel_tasks, capabilities, system_prompt, kick_method, created_at, updated_at)
VALUES
  -- Human (message receiver, owner for web UI login)
  ('uc012-human', 'UC012 Human', 'Project Owner', 'human', 'active', 'owner', NULL, 'general', 1, NULL, NULL, 'cli', datetime('now'), datetime('now')),
  -- Worker (task executor, message sender)
  ('uc012-worker', 'UC012 Worker', 'Task Worker', 'ai', 'active', 'worker', 'uc012-human', 'developer', 1, '["coding","messaging"]',
   'あなたはタスク実行ワーカーです。

タスクの指示に従ってください。
send_messageツールを使用する指示がある場合は、指定されたエージェントにメッセージを送信してください。
タスク完了後は必ずreport_completed(result="success")を呼び出してください。',
   'cli', datetime('now'), datetime('now'));

-- Insert agent credentials
INSERT INTO agent_credentials (id, agent_id, passkey_hash, salt, raw_passkey, created_at)
VALUES
  ('cred-uc012-human', 'uc012-human', '2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519', 'salt', 'test-passkey', datetime('now')),
  ('cred-uc012-worker', 'uc012-worker', '2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519', 'salt', 'test-passkey', datetime('now'));

-- Insert test project
INSERT INTO projects (id, name, description, status, working_directory, created_at, updated_at)
VALUES
  ('uc012-project', 'UC012 SendMessage Test', 'タスクセッションからのメッセージ送信テスト用プロジェクト', 'active', '/tmp/uc012', datetime('now'), datetime('now'));

-- Assign agents to project
INSERT INTO project_agents (project_id, agent_id, assigned_at)
VALUES
  ('uc012-project', 'uc012-human', datetime('now')),
  ('uc012-project', 'uc012-worker', datetime('now'));

-- Insert task for UC012 testing
-- Task instructs worker to send a message using send_message tool
INSERT INTO tasks (id, project_id, title, description, status, priority, assignee_id, created_by_agent_id, dependencies, created_at, updated_at)
VALUES
  ('uc012-task-sendmsg', 'uc012-project', 'メッセージ送信テストタスク',
   '以下の手順で作業してください:

1. このタスクを確認
2. send_message ツールで uc012-human にメッセージを送信してください
   - target_agent_id: "uc012-human"
   - content: "タスク実行中からの報告です。処理が正常に完了しました。"
3. report_completed(result="success") で完了報告

重要: send_messageの呼び出しを忘れないでください。',
   'todo', 'medium', 'uc012-worker', 'uc012-human', '[]', datetime('now'), datetime('now'));
