-- UC018 Chat Task Request Integration Test Data
-- Reference: docs/usecase/UC018_ChatTaskRequest.md
--
-- This script sets up test data for chat-based task request flow:
-- - 田中 (human PO): requester - sends chat message to Worker-01
-- - Worker-01 (AI): worker - receives request, creates task via MCP
-- - 佐藤 (human Tech Lead): approver - Worker-01's parent, receives notification
--
-- IMPORTANT: Only run against test database!

-- Clear existing UC018 test data
DELETE FROM agent_sessions WHERE agent_id IN ('uc018-tanaka', 'uc018-worker-01', 'uc018-sato');
DELETE FROM tasks WHERE id LIKE 'uc018-%';
DELETE FROM agent_credentials WHERE agent_id IN ('uc018-tanaka', 'uc018-worker-01', 'uc018-sato');
DELETE FROM agents WHERE id IN ('uc018-tanaka', 'uc018-worker-01', 'uc018-sato');
DELETE FROM project_agents WHERE project_id = 'uc018-project';
DELETE FROM projects WHERE id = 'uc018-project';

-- Insert test agents
-- 佐藤: Tech Lead (human), approver, Worker-01's parent
-- Worker-01: AI worker, subordinate of 佐藤
-- 田中: PO (human), requester, not in hierarchy with Worker-01
INSERT INTO agents (id, name, role, type, status, hierarchy_type, parent_agent_id, role_type, max_parallel_tasks, capabilities, system_prompt, kick_method, created_at, updated_at)
VALUES
  ('uc018-sato', '佐藤', 'Tech Lead', 'human', 'active', 'manager', NULL, 'general', 5, '["management", "review"]', 'You are a tech lead.', 'mcp', datetime('now'), datetime('now')),
  ('uc018-worker-01', 'Worker-01', 'Developer', 'ai', 'active', 'worker', 'uc018-sato', 'general', 3, '["coding", "implementation"]', 'You are an AI developer.', 'mcp', datetime('now'), datetime('now')),
  ('uc018-tanaka', '田中', 'Product Owner', 'human', 'active', 'worker', NULL, 'general', 1, '["planning"]', 'You are a product owner.', 'mcp', datetime('now'), datetime('now'));

-- Insert agent credentials
-- Hash: SHA256("test-passkeysalt") = 2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519
INSERT INTO agent_credentials (id, agent_id, passkey_hash, salt, raw_passkey, created_at)
VALUES
  ('cred-uc018-sato', 'uc018-sato', '2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519', 'salt', 'test-passkey', datetime('now')),
  ('cred-uc018-worker-01', 'uc018-worker-01', '2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519', 'salt', 'test-passkey', datetime('now')),
  ('cred-uc018-tanaka', 'uc018-tanaka', '2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519', 'salt', 'test-passkey', datetime('now'));

-- Insert test project
INSERT INTO projects (id, name, description, status, working_directory, created_at, updated_at)
VALUES
  ('uc018-project', 'Chat Task Request Test Project', 'Project for UC018 chat-based task request testing', 'active', '/tmp/uc018_webui_work', datetime('now'), datetime('now'));

-- Assign all agents to project
INSERT INTO project_agents (project_id, agent_id, assigned_at)
VALUES
  ('uc018-project', 'uc018-sato', datetime('now')),
  ('uc018-project', 'uc018-worker-01', datetime('now')),
  ('uc018-project', 'uc018-tanaka', datetime('now'));

-- Create Worker-01's chat session (simulates Coordinator having started the agent)
-- This allows the chat panel to be in "ready" state without actual Coordinator
INSERT INTO agent_sessions (id, token, agent_id, expires_at, created_at, project_id, purpose, last_activity_at, state)
VALUES
  ('uc018-worker01-chat-session', 'uc018-worker01-chat-token', 'uc018-worker-01',
   datetime('now', '+1 day'), datetime('now'), 'uc018-project', 'chat', datetime('now'), 'active');

-- Create task with pending_approval status (Step 3)
-- This simulates Worker-01 having created a task via request_task tool
INSERT INTO tasks (id, project_id, title, status, assignee_id, description, priority, requester_id, approval_status, created_at, updated_at)
VALUES
  ('uc018-search-task', 'uc018-project', 'ユーザー一覧に検索機能追加', 'backlog', 'uc018-worker-01',
   '名前・メールアドレスでの絞り込み機能を実装', 'medium', 'uc018-worker-01', 'pending_approval',
   datetime('now'), datetime('now'));
