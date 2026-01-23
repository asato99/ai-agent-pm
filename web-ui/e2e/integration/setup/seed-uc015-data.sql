-- UC015 Integration Test Data Seed Script
-- Reference: docs/usecase/UC015_ChatSessionClose.md
--            docs/design/CHAT_SESSION_MAINTENANCE_MODE.md - Section 6
--
-- This script sets up test data for UC015: チャットセッション終了
-- Test flow:
-- 1. User opens chat panel (session starts, state = active)
-- 2. User closes chat panel
-- 3. POST /chat/end is called → session state = terminating
-- 4. Agent's next getNextAction returns exit action
-- 5. Agent calls logout → session state = ended
--
-- IMPORTANT: Only run against test database!

-- Clear existing UC015 test data
DELETE FROM agent_sessions WHERE agent_id LIKE 'uc015-%';
DELETE FROM tasks WHERE id LIKE 'uc015-%';
DELETE FROM agent_credentials WHERE agent_id LIKE 'uc015-%';
DELETE FROM project_agents WHERE project_id = 'uc015-project';
DELETE FROM agents WHERE id LIKE 'uc015-%';
DELETE FROM projects WHERE id = 'uc015-project';

-- Create working directory marker
-- Note: Actual directory creation happens in setup script

-- Insert test agents for UC015
INSERT INTO agents (id, name, role, type, status, hierarchy_type, parent_agent_id, role_type, max_parallel_tasks, capabilities, system_prompt, kick_method, created_at, updated_at)
VALUES
  -- Human (project owner for web UI login)
  ('uc015-human', 'UC015 Human', 'Project Owner', 'human', 'active', 'owner', NULL, 'general', 1, NULL, NULL, 'cli', datetime('now'), datetime('now')),
  -- Worker (chat responder)
  ('uc015-worker', 'UC015 Worker', 'Chat Responder', 'ai', 'active', 'worker', 'uc015-human', 'general', 1, '["chat"]',
   'あなたはチャット対応ワーカーです。

ユーザーからのメッセージに対して、簡潔に応答してください。
get_pending_messages でメッセージを取得し、respond_chat で応答を送信してください。

応答は短く、的確に。例:
- 「進捗を教えて」→「現在の進捗は80%です。詳細をお伝えしましょうか？」
- 「こんにちは」→「こんにちは！何かお手伝いできますか？」

get_next_action が exit を返した場合は、logout を呼び出してセッションを終了してください。
これはユーザーがチャットパネルを閉じたことを意味します。',
   'cli', datetime('now'), datetime('now'));

-- Insert agent credentials
INSERT INTO agent_credentials (id, agent_id, passkey_hash, salt, raw_passkey, created_at)
VALUES
  ('cred-uc015-human', 'uc015-human', '2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519', 'salt', 'test-passkey', datetime('now')),
  ('cred-uc015-worker', 'uc015-worker', '2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519', 'salt', 'test-passkey', datetime('now'));

-- Insert test project
INSERT INTO projects (id, name, description, status, working_directory, created_at, updated_at)
VALUES
  ('uc015-project', 'UC015 Chat Session Close Test', 'チャットセッション終了テスト用プロジェクト', 'active', '/tmp/uc015', datetime('now'), datetime('now'));

-- Assign agents to project
INSERT INTO project_agents (project_id, agent_id, assigned_at)
VALUES
  ('uc015-project', 'uc015-human', datetime('now')),
  ('uc015-project', 'uc015-worker', datetime('now'));

-- Note: No tasks are needed for UC015 - this is a pure chat session close test
