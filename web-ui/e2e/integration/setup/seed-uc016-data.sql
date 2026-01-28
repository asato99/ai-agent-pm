-- UC016 Integration Test Data Seed Script
-- Reference: docs/usecase/UC016_AIToAIConversation.md
--
-- This script sets up test data for UC016: AIエージェント間会話
-- Test flow:
-- 1. Human opens chat with Worker-A (initiator)
-- 2. Human instructs Worker-A to start conversation with Worker-B
-- 3. Worker-A calls start_conversation(target: uc016-participant)
-- 4. Worker-B joins conversation
-- 5. They exchange messages (shiritori 5 rounds)
-- 6. Worker-A calls end_conversation
-- 7. Worker-A reports result to Human
--
-- IMPORTANT: Only run against test database!

-- Clear existing UC016 test data
DELETE FROM conversations WHERE project_id = 'uc016-project';
DELETE FROM agent_sessions WHERE agent_id LIKE 'uc016-%';
DELETE FROM tasks WHERE id LIKE 'uc016-%';
DELETE FROM agent_credentials WHERE agent_id LIKE 'uc016-%';
DELETE FROM project_agents WHERE project_id = 'uc016-project';
DELETE FROM agents WHERE id LIKE 'uc016-%';
DELETE FROM projects WHERE id = 'uc016-project';

-- Create working directory marker
-- Note: Actual directory creation happens in setup script

-- Insert test agents for UC016
-- NOTE: system_prompt is NULL - all instructions come from Human's chat message
INSERT INTO agents (id, name, role, type, status, hierarchy_type, parent_agent_id, role_type, max_parallel_tasks, capabilities, system_prompt, kick_method, created_at, updated_at)
VALUES
  -- Human (project owner for web UI login, instructs Worker-A)
  ('uc016-human', 'UC016 Human', 'Project Owner', 'human', 'active', 'owner', NULL, 'general', 1, NULL, NULL, 'cli', datetime('now'), datetime('now')),
  -- Worker-A (initiator - starts conversation with Worker-B)
  ('uc016-initiator', 'UC016 Initiator', 'Conversation Initiator', 'ai', 'active', 'worker', 'uc016-human', 'general', 1, '["chat","conversation"]', NULL, 'cli', datetime('now'), datetime('now')),
  -- Worker-B (participant - joins conversation when invited)
  ('uc016-participant', 'UC016 Participant', 'Conversation Participant', 'ai', 'active', 'worker', 'uc016-human', 'general', 1, '["chat","conversation"]', NULL, 'cli', datetime('now'), datetime('now'));

-- Insert agent credentials
INSERT INTO agent_credentials (id, agent_id, passkey_hash, salt, raw_passkey, created_at)
VALUES
  ('cred-uc016-human', 'uc016-human', '2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519', 'salt', 'test-passkey', datetime('now')),
  ('cred-uc016-initiator', 'uc016-initiator', '2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519', 'salt', 'test-passkey', datetime('now')),
  ('cred-uc016-participant', 'uc016-participant', '2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519', 'salt', 'test-passkey', datetime('now'));

-- Insert test project
INSERT INTO projects (id, name, description, status, working_directory, created_at, updated_at)
VALUES
  ('uc016-project', 'UC016 AI Conversation Test', 'AIエージェント間会話テスト用プロジェクト', 'active', '/tmp/uc016', datetime('now'), datetime('now'));

-- Assign agents to project
INSERT INTO project_agents (project_id, agent_id, assigned_at)
VALUES
  ('uc016-project', 'uc016-human', datetime('now')),
  ('uc016-project', 'uc016-initiator', datetime('now')),
  ('uc016-project', 'uc016-participant', datetime('now'));

-- Note: No tasks are needed for UC016 - Human instructs Worker-A via chat message
