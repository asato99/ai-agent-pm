-- UC013 Integration Test Data Seed Script
-- Reference: docs/usecase/UC013_WorkerToWorkerMessageRelay.md
--
-- This script sets up test data for UC013: Worker間メッセージ連携
-- Test flow:
-- 1. Worker-A executes task
-- 2. Worker-A sends message to Worker-B using send_message tool
-- 3. Worker-A completes task
-- 4. Worker-B starts (chat session) due to pending message
-- 5. Worker-B receives message via get_pending_messages
-- 6. Worker-B relays message to Human using respond_chat
-- 7. Human sees message in Web UI
--
-- IMPORTANT: Only run against test database!

-- Clear existing UC013 test data
DELETE FROM tasks WHERE id LIKE 'uc013-%';
DELETE FROM agent_credentials WHERE agent_id LIKE 'uc013-%';
DELETE FROM project_agents WHERE project_id = 'uc013-project';
DELETE FROM agents WHERE id LIKE 'uc013-%';
DELETE FROM projects WHERE id = 'uc013-project';

-- Insert test agents for UC013
INSERT INTO agents (id, name, role, type, status, hierarchy_type, parent_agent_id, role_type, max_parallel_tasks, capabilities, system_prompt, kick_method, created_at, updated_at)
VALUES
  -- Human (final message receiver, owner for web UI login)
  ('uc013-human', 'UC013 Human', 'Project Owner', 'human', 'active', 'owner', NULL, 'general', 1, NULL, NULL, 'cli', datetime('now'), datetime('now')),
  -- Worker-A (task executor, message sender to Worker-B)
  ('uc013-worker-a', 'UC013 Task Worker', 'Task Worker', 'ai', 'active', 'worker', 'uc013-human', 'developer', 1, '["coding","messaging"]',
   'あなたはタスク実行ワーカーです。

タスクの指示に従ってください。
1. データ処理を実行（シミュレーション）
2. send_message ツールで uc013-worker-b に結果を報告
3. report_completed(result="success") で完了報告

重要: send_messageの呼び出しを忘れないでください。',
   'cli', datetime('now'), datetime('now')),
  -- Worker-B (message relay agent, receives from Worker-A, sends to Human)
  ('uc013-worker-b', 'UC013 Relay Worker', 'Message Relay', 'ai', 'active', 'worker', 'uc013-human', 'developer', 1, '["messaging","relay"]',
   'あなたはメッセージ中継エージェントです。

他のエージェントからメッセージを受け取ったら、その内容を人間 (uc013-human) に respond_chat で報告してください。

手順:
1. get_pending_messages で受信メッセージを確認
2. メッセージがあれば respond_chat で uc013-human に転送
   - target_agent_id: "uc013-human" を必ず指定
   - content: "Worker-Aからの報告: [受信したメッセージ内容]"
3. 完了したらセッションを終了

重要: respond_chat の target_agent_id パラメータで "uc013-human" を明示的に指定してください。省略すると送信元に返信されてしまいます。',
   'cli', datetime('now'), datetime('now'));

-- Insert agent credentials
INSERT INTO agent_credentials (id, agent_id, passkey_hash, salt, raw_passkey, created_at)
VALUES
  ('cred-uc013-human', 'uc013-human', '2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519', 'salt', 'test-passkey', datetime('now')),
  ('cred-uc013-worker-a', 'uc013-worker-a', '2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519', 'salt', 'test-passkey', datetime('now')),
  ('cred-uc013-worker-b', 'uc013-worker-b', '2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519', 'salt', 'test-passkey', datetime('now'));

-- Insert test project
INSERT INTO projects (id, name, description, status, working_directory, created_at, updated_at)
VALUES
  ('uc013-project', 'UC013 Message Relay Test', 'Worker間メッセージ連携テスト用プロジェクト', 'active', '/tmp/uc013', datetime('now'), datetime('now'));

-- Assign agents to project
INSERT INTO project_agents (project_id, agent_id, assigned_at)
VALUES
  ('uc013-project', 'uc013-human', datetime('now')),
  ('uc013-project', 'uc013-worker-a', datetime('now')),
  ('uc013-project', 'uc013-worker-b', datetime('now'));

-- Insert task for UC013 testing (Worker-A's task)
-- Task instructs worker-a to send a message to worker-b
INSERT INTO tasks (id, project_id, title, description, status, priority, assignee_id, created_by_agent_id, dependencies, created_at, updated_at)
VALUES
  ('uc013-task-data', 'uc013-project', 'データ処理タスク',
   '以下の手順で作業してください:

1. データ処理を実行（シミュレーション：特に実際の処理は不要）
2. send_message ツールで uc013-worker-b に結果を報告
   - target_agent_id: "uc013-worker-b"
   - content: "データ処理が完了しました。処理件数: 100件"
3. report_completed(result="success") で完了報告

重要: send_messageの呼び出しを忘れないでください。Worker-Bが人間に報告を中継します。',
   'todo', 'medium', 'uc013-worker-a', 'uc013-human', '[]', datetime('now'), datetime('now'));
