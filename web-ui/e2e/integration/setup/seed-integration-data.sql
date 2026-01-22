-- Integration Test Data Seed Script
-- Reference: docs/usecase/UC010_TaskInterruptByStatusChange.md
--
-- This script sets up test data for integration tests including:
-- - Agents with proper hierarchy (owner -> manager -> worker)
-- - A test project for integration testing
-- - A countdown task designed for testing task interruption
--
-- IMPORTANT: Only run against test database!

-- Clear existing integration test data
DELETE FROM tasks WHERE id LIKE 'integ-task-%';
DELETE FROM agent_credentials WHERE agent_id IN ('integ-owner', 'integ-manager', 'integ-worker');
DELETE FROM agents WHERE id IN ('integ-owner', 'integ-manager', 'integ-worker');
DELETE FROM project_agents WHERE project_id = 'integ-project';
DELETE FROM projects WHERE id = 'integ-project';

-- Insert test agents for integration tests
INSERT INTO agents (id, name, role, type, status, hierarchy_type, parent_agent_id, role_type, max_parallel_tasks, capabilities, system_prompt, kick_method, created_at, updated_at)
VALUES
  ('integ-owner', 'Integration Owner', 'Test Owner', 'human', 'active', 'owner', NULL, 'general', 1, NULL, NULL, 'cli', datetime('now'), datetime('now')),
  ('integ-manager', 'Integration Manager', 'Test Manager', 'ai', 'active', 'manager', 'integ-owner', 'general', 5, '["management"]', 'You are a test manager for integration tests.', 'mcp', datetime('now'), datetime('now')),
  ('integ-worker', 'Integration Worker', 'Test Worker', 'ai', 'active', 'worker', 'integ-manager', 'general', 3, '["coding","testing"]', 'You are a test worker for integration tests.', 'mcp', datetime('now'), datetime('now'));

-- Insert agent credentials
-- Hash: SHA256("test-passkeysalt") = 2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519
INSERT INTO agent_credentials (id, agent_id, passkey_hash, salt, raw_passkey, created_at)
VALUES
  ('cred-integ-owner', 'integ-owner', '2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519', 'salt', 'test-passkey', datetime('now')),
  ('cred-integ-manager', 'integ-manager', '2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519', 'salt', 'test-passkey', datetime('now')),
  ('cred-integ-worker', 'integ-worker', '2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519', 'salt', 'test-passkey', datetime('now'));

-- Insert test project
-- working_directory is set to /tmp/uc001_webui_work for integration tests
INSERT INTO projects (id, name, description, status, working_directory, created_at, updated_at)
VALUES
  ('integ-project', 'Integration Test Project', 'Project for integration testing', 'active', '/tmp/uc001_webui_work', datetime('now'), datetime('now'));

-- Assign agents to project
INSERT INTO project_agents (project_id, agent_id, assigned_at)
VALUES
  ('integ-project', 'integ-owner', datetime('now')),
  ('integ-project', 'integ-manager', datetime('now')),
  ('integ-project', 'integ-worker', datetime('now'));

-- Insert simple task for integration testing
-- This task is designed to complete quickly for fast test execution
-- Note: Status is 'todo' initially, changed to 'in_progress' via UI
INSERT INTO tasks (id, project_id, title, description, status, priority, assignee_id, created_by_agent_id, dependencies, created_at, updated_at)
VALUES
  ('integ-task-countdown', 'integ-project', 'カウントダウンタスク',
   'シンプルなテストタスクです。

## 実行手順
1. このメッセージを確認したら、すぐにreport_completedを呼び出してください
2. result: "success"で完了を報告してください

## 注意
- サブタスクの作成は不要です
- すぐにreport_completed(result="success")を呼び出してください',
   'todo', 'medium', 'integ-worker', 'integ-manager', '[]', datetime('now'), datetime('now'));
