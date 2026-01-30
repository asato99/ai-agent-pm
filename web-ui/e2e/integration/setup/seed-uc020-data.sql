-- UC020 Integration Test Data Seed Script
-- Task-based AI-to-AI Conversation (Worker-Worker)
--
-- This script sets up test data for UC020: タスクベースAI-to-AI会話
-- Test flow:
-- 1. Human views task in Web UI and changes status to in_progress
-- 2. Coordinator detects and spawns Worker-A
-- 3. Worker-A calls start_conversation(target: worker-b)
-- 4. Worker-B joins conversation
-- 5. They exchange messages (shiritori 6 rounds)
-- 6. Worker-A calls end_conversation
-- 7. Worker-A calls report_completed to finish task
--
-- Difference from UC016: Task-based (not chat-based)
-- - Instructions come from task description (not chat message)
-- - Task status transitions: todo → in_progress → done
--
-- IMPORTANT: Only run against test database!

-- Clear existing UC020 test data
DELETE FROM conversations WHERE project_id = 'uc020-project';
DELETE FROM agent_sessions WHERE agent_id LIKE 'uc020-%';
DELETE FROM tasks WHERE id LIKE 'uc020-%' OR project_id = 'uc020-project';
DELETE FROM agent_credentials WHERE agent_id LIKE 'uc020-%';
DELETE FROM project_agents WHERE project_id = 'uc020-project';
DELETE FROM agents WHERE id LIKE 'uc020-%';
DELETE FROM projects WHERE id = 'uc020-project';

-- Insert test agents for UC020
-- Hierarchy: Human → Worker-A, Worker-B (both workers under Human)
INSERT INTO agents (id, name, role, type, status, hierarchy_type, parent_agent_id, role_type, max_parallel_tasks, capabilities, system_prompt, kick_method, created_at, updated_at)
VALUES
  -- Human (project owner for web UI login)
  ('uc020-human', 'UC020 Human', 'Project Owner', 'human', 'active', 'owner', NULL, 'general', 1, NULL, NULL, 'cli', datetime('now'), datetime('now')),
  -- Worker-A (executes task, initiates conversation with Worker-B)
  ('uc020-worker-a', 'UC020 Worker-A', 'Task Executor', 'ai', 'active', 'worker', 'uc020-human', 'general', 1, '["task","conversation"]', NULL, 'cli', datetime('now'), datetime('now')),
  -- Worker-B (conversation participant)
  ('uc020-worker-b', 'UC020 Worker-B', 'Conversation Partner', 'ai', 'active', 'worker', 'uc020-human', 'general', 1, '["conversation"]', NULL, 'cli', datetime('now'), datetime('now'));

-- Insert agent credentials
INSERT INTO agent_credentials (id, agent_id, passkey_hash, salt, raw_passkey, created_at)
VALUES
  ('cred-uc020-human', 'uc020-human', '2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519', 'salt', 'test-passkey', datetime('now')),
  ('cred-uc020-worker-a', 'uc020-worker-a', '2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519', 'salt', 'test-passkey', datetime('now')),
  ('cred-uc020-worker-b', 'uc020-worker-b', '2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519', 'salt', 'test-passkey', datetime('now'));

-- Insert test project
INSERT INTO projects (id, name, description, status, working_directory, created_at, updated_at)
VALUES
  ('uc020-project', 'UC020 Task-based Conversation Test', 'タスクベースAI-to-AI会話テスト用プロジェクト', 'active', '/tmp/uc020', datetime('now'), datetime('now'));

-- Assign agents to project
INSERT INTO project_agents (project_id, agent_id, assigned_at)
VALUES
  ('uc020-project', 'uc020-human', datetime('now')),
  ('uc020-project', 'uc020-worker-a', datetime('now')),
  ('uc020-project', 'uc020-worker-b', datetime('now'));

-- Insert the task (this is a valid seed - task is the "instruction" in task-based flow)
-- Task description contains the instruction for Worker-A
INSERT INTO tasks (id, project_id, title, description, status, priority, assignee_id, created_by_agent_id, created_at, updated_at)
VALUES
  ('uc020-task-shiritori', 'uc020-project', 'しりとりタスク',
   'uc020-worker-bと6往復しりとりをしてください。最初の単語は「りんご」で始めて、終わったら完了報告してください。',
   'todo', 'medium', 'uc020-worker-a', 'uc020-human', datetime('now'), datetime('now'));

-- Note: Agent sessions are NOT seeded
-- Coordinator will create session when task status changes to in_progress
