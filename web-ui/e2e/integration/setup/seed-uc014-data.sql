-- UC014 Integration Test Data Seed Script
-- Reference: docs/usecase/UC014_ChatSessionImmediateResponse.md
--
-- This script sets up test data for UC014: チャットセッション即時応答
-- Test flow:
-- 1. User opens chat panel for worker agent
-- 2. System calls POST /chat/start to initiate session
-- 3. Coordinator spawns agent, agent enters wait_for_messages loop
-- 4. Send button becomes enabled (session ready)
-- 5. User sends message
-- 6. Agent responds within 5 seconds
--
-- IMPORTANT: Only run against test database!

-- Clear existing UC014 test data
DELETE FROM agent_sessions WHERE agent_id LIKE 'uc014-%';
DELETE FROM tasks WHERE id LIKE 'uc014-%';
DELETE FROM agent_credentials WHERE agent_id LIKE 'uc014-%';
DELETE FROM project_agents WHERE project_id = 'uc014-project';
DELETE FROM agents WHERE id LIKE 'uc014-%';
DELETE FROM projects WHERE id = 'uc014-project';

-- Create working directory marker
-- Note: Actual directory creation happens in setup script

-- Insert test agents for UC014
INSERT INTO agents (id, name, role, type, status, hierarchy_type, parent_agent_id, role_type, max_parallel_tasks, capabilities, system_prompt, kick_method, created_at, updated_at)
VALUES
  -- Human (project owner for web UI login)
  ('uc014-human', 'UC014 Human', 'Project Owner', 'human', 'active', 'owner', NULL, 'general', 1, NULL, NULL, 'cli', datetime('now'), datetime('now')),
  -- Worker (chat responder)
  ('uc014-worker', 'UC014 Worker', 'Chat Responder', 'ai', 'active', 'worker', 'uc014-human', 'general', 1, '["chat"]',
   'あなたはチャット対応ワーカーです。

ユーザーからのメッセージに対して、簡潔に応答してください。
get_pending_messages でメッセージを取得し、respond_chat で応答を送信してください。

応答は短く、的確に。例:
- 「進捗を教えて」→「現在の進捗は80%です。詳細をお伝えしましょうか？」
- 「こんにちは」→「こんにちは！何かお手伝いできますか？」

get_next_action が wait_for_messages を返した場合は、wait_seconds の値に従って待機後に再度 get_next_action を呼び出してください。',
   'cli', datetime('now'), datetime('now'));

-- Insert agent credentials
INSERT INTO agent_credentials (id, agent_id, passkey_hash, salt, raw_passkey, created_at)
VALUES
  ('cred-uc014-human', 'uc014-human', '2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519', 'salt', 'test-passkey', datetime('now')),
  ('cred-uc014-worker', 'uc014-worker', '2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519', 'salt', 'test-passkey', datetime('now'));

-- Insert test project
INSERT INTO projects (id, name, description, status, working_directory, created_at, updated_at)
VALUES
  ('uc014-project', 'UC014 Chat Session Test', 'チャットセッション即時応答テスト用プロジェクト', 'active', '/tmp/uc014', datetime('now'), datetime('now'));

-- Assign agents to project
INSERT INTO project_agents (project_id, agent_id, assigned_at)
VALUES
  ('uc014-project', 'uc014-human', datetime('now')),
  ('uc014-project', 'uc014-worker', datetime('now'));

-- Note: No tasks are needed for UC014 - this is a pure chat session test
