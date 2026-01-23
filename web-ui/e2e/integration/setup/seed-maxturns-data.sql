-- Max Turns Integration Test Data Seed Script
-- Reference: docs/design/AI_TO_AI_CONVERSATION.md
--
-- This script sets up test data for max_turns auto-termination test
-- Test flow:
-- 1. Human opens chat with Worker-A (initiator)
-- 2. Human instructs Worker-A to start conversation with Worker-B for 11 rounds
-- 3. Worker-A calls start_conversation with max_turns=20
-- 4. They exchange messages (shiritori)
-- 5. At 20 messages (10 rounds), conversation auto-terminates
-- 6. Worker-A receives warning about auto-termination
--
-- IMPORTANT: Only run against test database!

-- Clear existing maxturns test data
DELETE FROM conversations WHERE project_id = 'maxturns-project';
DELETE FROM pending_agent_purposes WHERE project_id = 'maxturns-project';
DELETE FROM agent_sessions WHERE agent_id LIKE 'maxturns-%';
DELETE FROM tasks WHERE id LIKE 'maxturns-%';
DELETE FROM agent_credentials WHERE agent_id LIKE 'maxturns-%';
DELETE FROM project_agents WHERE project_id = 'maxturns-project';
DELETE FROM agents WHERE id LIKE 'maxturns-%';
DELETE FROM projects WHERE id = 'maxturns-project';

-- Insert test agents for max_turns test
-- NOTE: system_prompt is NULL - all instructions come from Human's chat message
INSERT INTO agents (id, name, role, type, status, hierarchy_type, parent_agent_id, role_type, max_parallel_tasks, capabilities, system_prompt, kick_method, created_at, updated_at)
VALUES
  -- Human (project owner for web UI login)
  ('maxturns-human', 'MaxTurns Human', 'Project Owner', 'human', 'active', 'owner', NULL, 'general', 1, NULL, NULL, 'cli', datetime('now'), datetime('now')),
  -- Worker-A (initiator)
  ('maxturns-initiator', 'MaxTurns Initiator', 'Conversation Initiator', 'ai', 'active', 'worker', 'maxturns-human', 'general', 1, '["chat","conversation"]', NULL, 'cli', datetime('now'), datetime('now')),
  -- Worker-B (participant)
  ('maxturns-participant', 'MaxTurns Participant', 'Conversation Participant', 'ai', 'active', 'worker', 'maxturns-human', 'general', 1, '["chat","conversation"]', NULL, 'cli', datetime('now'), datetime('now'));

-- Insert agent credentials
INSERT INTO agent_credentials (id, agent_id, passkey_hash, salt, raw_passkey, created_at)
VALUES
  ('cred-maxturns-human', 'maxturns-human', '2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519', 'salt', 'test-passkey', datetime('now')),
  ('cred-maxturns-initiator', 'maxturns-initiator', '2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519', 'salt', 'test-passkey', datetime('now')),
  ('cred-maxturns-participant', 'maxturns-participant', '2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519', 'salt', 'test-passkey', datetime('now'));

-- Insert test project
INSERT INTO projects (id, name, description, status, working_directory, created_at, updated_at)
VALUES
  ('maxturns-project', 'MaxTurns Test Project', 'max_turns制限テスト用プロジェクト', 'active', '/tmp/maxturns', datetime('now'), datetime('now'));

-- Assign agents to project
INSERT INTO project_agents (project_id, agent_id, assigned_at)
VALUES
  ('maxturns-project', 'maxturns-human', datetime('now')),
  ('maxturns-project', 'maxturns-initiator', datetime('now')),
  ('maxturns-project', 'maxturns-participant', datetime('now'));

-- Note: No tasks needed - Human instructs Worker-A via chat message
