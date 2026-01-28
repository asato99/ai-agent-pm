-- Seed data for Session Status Integration Test
-- Reference: Chat session status transitions (disconnected → connecting → connected)

-- Clean existing test data
DELETE FROM agent_sessions WHERE agent_id LIKE 'session-%';
DELETE FROM tasks WHERE project_id = 'session-project';
DELETE FROM project_agents WHERE project_id = 'session-project';
DELETE FROM agent_credentials WHERE agent_id LIKE 'session-%';
DELETE FROM agents WHERE id LIKE 'session-%';
DELETE FROM projects WHERE id = 'session-project';

-- Project
INSERT INTO projects (id, name, description, status, working_directory, created_at, updated_at)
VALUES ('session-project', 'Session Test Project', 'Project for session status testing', 'active', '/tmp/session-test', datetime('now'), datetime('now'));

-- Agents
-- Human (project owner) - for login
INSERT INTO agents (id, name, role, type, hierarchy_type, status, role_type, max_parallel_tasks, kick_method, created_at, updated_at)
VALUES ('session-human', 'Session Test Human', 'Project Owner', 'human', 'manager', 'active', 'general', 1, 'cli', datetime('now'), datetime('now'));

-- Worker agent - target for chat sessions
INSERT INTO agents (id, name, role, type, hierarchy_type, status, role_type, max_parallel_tasks, provider, model_id, kick_method, capabilities, system_prompt, created_at, updated_at)
VALUES ('session-worker', 'Session Test Worker', 'Chat Responder', 'ai', 'worker', 'active', 'general', 1, 'claude', 'claude-sonnet-4-20250514', 'cli', '["chat"]',
'あなたはチャット対応ワーカーです。
ユーザーからのメッセージに対して、簡潔に応答してください。
get_pending_messages でメッセージを取得し、respond_chat で応答を送信してください。
get_next_action が exit を返した場合は、logout を呼び出してセッションを終了してください。',
datetime('now'), datetime('now'));

-- Agent credentials (passkey_hash is SHA256 of "test-passkey")
INSERT INTO agent_credentials (id, agent_id, passkey_hash, salt, raw_passkey, created_at)
VALUES ('cred-session-human', 'session-human', '2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519', 'salt', 'test-passkey', datetime('now'));

INSERT INTO agent_credentials (id, agent_id, passkey_hash, salt, raw_passkey, created_at)
VALUES ('cred-session-worker', 'session-worker', '2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519', 'salt', 'test-passkey', datetime('now'));

-- Project assignments
INSERT INTO project_agents (project_id, agent_id, assigned_at)
VALUES ('session-project', 'session-human', datetime('now'));

INSERT INTO project_agents (project_id, agent_id, assigned_at)
VALUES ('session-project', 'session-worker', datetime('now'));

-- Verify data
SELECT 'Projects:' as info;
SELECT id, name, status FROM projects WHERE id = 'session-project';

SELECT 'Agents:' as info;
SELECT id, name, type, hierarchy_type, status FROM agents WHERE id LIKE 'session-%';

SELECT 'Assignments:' as info;
SELECT project_id, agent_id FROM project_agents WHERE project_id = 'session-project';

SELECT 'Credentials:' as info;
SELECT agent_id, raw_passkey FROM agent_credentials WHERE agent_id LIKE 'session-%';
