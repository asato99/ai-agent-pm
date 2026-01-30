-- UC016-B Integration Test Data Seed Script
-- Reference: docs/usecase/UC016_AIToAIConversation.md
--
-- This script sets up test data for UC016-B: Manager-Worker間のAI会話
-- Test flow:
-- 1. Human opens chat with Manager (initiator)
-- 2. Human instructs Manager to start conversation with Worker
-- 3. Manager calls start_conversation(target: uc016b-worker)
-- 4. Worker joins conversation
-- 5. They exchange messages (shiritori 5 rounds)
-- 6. Manager calls end_conversation
-- 7. Manager reports result to Human
--
-- Difference from UC016: Manager → Worker hierarchy (not Worker ⇄ Worker)
--
-- IMPORTANT: Only run against test database!

-- Clear existing UC016-B test data
DELETE FROM conversations WHERE project_id = 'uc016b-project';
DELETE FROM agent_sessions WHERE agent_id LIKE 'uc016b-%';
DELETE FROM tasks WHERE id LIKE 'uc016b-%';
DELETE FROM agent_credentials WHERE agent_id LIKE 'uc016b-%';
DELETE FROM project_agents WHERE project_id = 'uc016b-project';
DELETE FROM agents WHERE id LIKE 'uc016b-%';
DELETE FROM projects WHERE id = 'uc016b-project';

-- Insert test agents for UC016-B
-- Hierarchy: Human → Manager → Worker
INSERT INTO agents (id, name, role, type, status, hierarchy_type, parent_agent_id, role_type, max_parallel_tasks, capabilities, system_prompt, kick_method, created_at, updated_at)
VALUES
  -- Human (project owner for web UI login, instructs Manager)
  ('uc016b-human', 'UC016-B Human', 'Project Owner', 'human', 'active', 'owner', NULL, 'general', 1, NULL, NULL, 'cli', datetime('now'), datetime('now')),
  -- Manager (initiator - starts conversation with Worker, subordinate of Human)
  ('uc016b-manager', 'UC016-B Manager', 'Team Manager', 'ai', 'active', 'manager', 'uc016b-human', 'general', 3, '["chat","conversation","delegation"]', NULL, 'cli', datetime('now'), datetime('now')),
  -- Worker (participant - joins conversation when invited, subordinate of Manager)
  ('uc016b-worker', 'UC016-B Worker', 'Team Worker', 'ai', 'active', 'worker', 'uc016b-manager', 'general', 1, '["chat","conversation"]', NULL, 'cli', datetime('now'), datetime('now'));

-- Insert agent credentials
INSERT INTO agent_credentials (id, agent_id, passkey_hash, salt, raw_passkey, created_at)
VALUES
  ('cred-uc016b-human', 'uc016b-human', '2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519', 'salt', 'test-passkey', datetime('now')),
  ('cred-uc016b-manager', 'uc016b-manager', '2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519', 'salt', 'test-passkey', datetime('now')),
  ('cred-uc016b-worker', 'uc016b-worker', '2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519', 'salt', 'test-passkey', datetime('now'));

-- Insert test project
INSERT INTO projects (id, name, description, status, working_directory, created_at, updated_at)
VALUES
  ('uc016b-project', 'UC016-B Manager-Worker Conversation Test', 'Manager-Worker間AI会話テスト用プロジェクト', 'active', '/tmp/uc016b', datetime('now'), datetime('now'));

-- Assign agents to project
INSERT INTO project_agents (project_id, agent_id, assigned_at)
VALUES
  ('uc016b-project', 'uc016b-human', datetime('now')),
  ('uc016b-project', 'uc016b-manager', datetime('now')),
  ('uc016b-project', 'uc016b-worker', datetime('now'));

-- Note: No tasks are needed - Human instructs Manager via chat message
