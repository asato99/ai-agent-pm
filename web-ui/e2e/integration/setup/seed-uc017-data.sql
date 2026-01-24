-- UC017 Task Approval Integration Test Data
-- Reference: docs/usecase/UC017_TaskApproval.md
--
-- This script sets up test data for task approval flow:
-- - Manager agent (can approve tasks)
-- - Worker agent (task requester)
-- - Task in pendingApproval status with requester set
--
-- IMPORTANT: Only run against test database!

-- Clear existing UC017 test data
DELETE FROM tasks WHERE id LIKE 'uc017-%';
DELETE FROM agent_credentials WHERE agent_id IN ('uc017-manager', 'uc017-worker');
DELETE FROM agents WHERE id IN ('uc017-manager', 'uc017-worker');
DELETE FROM project_agents WHERE project_id = 'uc017-project';
DELETE FROM projects WHERE id = 'uc017-project';

-- Insert test agents
-- Manager: has approval authority
-- Worker: created the task and is the requester
INSERT INTO agents (id, name, role, type, status, hierarchy_type, parent_agent_id, role_type, max_parallel_tasks, capabilities, system_prompt, kick_method, created_at, updated_at)
VALUES
  ('uc017-manager', 'Approval Manager', 'Test Manager', 'ai', 'active', 'manager', NULL, 'general', 5, '["management"]', 'You are a manager for approval tests.', 'mcp', datetime('now'), datetime('now')),
  ('uc017-worker', 'Task Worker', 'Test Worker', 'ai', 'active', 'worker', 'uc017-manager', 'general', 3, '["coding"]', 'You are a worker for approval tests.', 'mcp', datetime('now'), datetime('now'));

-- Insert agent credentials
-- Hash: SHA256("test-passkeysalt") = 2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519
INSERT INTO agent_credentials (id, agent_id, passkey_hash, salt, raw_passkey, created_at)
VALUES
  ('cred-uc017-manager', 'uc017-manager', '2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519', 'salt', 'test-passkey', datetime('now')),
  ('cred-uc017-worker', 'uc017-worker', '2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519', 'salt', 'test-passkey', datetime('now'));

-- Insert test project
INSERT INTO projects (id, name, description, status, working_directory, created_at, updated_at)
VALUES
  ('uc017-project', 'Task Approval Test Project', 'Project for UC017 task approval testing', 'active', '/tmp/uc017_webui_work', datetime('now'), datetime('now'));

-- Assign agents to project
INSERT INTO project_agents (project_id, agent_id, assigned_at)
VALUES
  ('uc017-project', 'uc017-manager', datetime('now')),
  ('uc017-project', 'uc017-worker', datetime('now'));

-- Insert task in pendingApproval status
-- This task was created by worker and needs manager approval
-- Note: approval_status uses snake_case 'pending_approval' (Domain/Entities/Task.swift)
INSERT INTO tasks (id, project_id, title, description, status, priority, assignee_id, created_by_agent_id, requester_id, approval_status, dependencies, created_at, updated_at)
VALUES
  ('uc017-task-pending', 'uc017-project', '承認待ちタスク',
   'このタスクはWorkerが作成し、Managerの承認を待っています。

## 作業内容
- 新機能の実装
- 単体テストの作成

## 承認依頼理由
機能実装の着手許可をお願いします。',
   'backlog', 'medium', 'uc017-worker', 'uc017-worker', 'uc017-worker', 'pending_approval', '[]', datetime('now'), datetime('now'));
