-- Pilot Test: hello-world scenario seed data
--
-- IMPORTANT: This seed creates ONLY prerequisites (agents, project).
-- Expected results (tasks, status changes) are NEVER seeded.
-- Tasks will be created by the Manager AI agent during test execution.
--
-- Reference: web-ui/e2e/pilot/scenarios/hello-world.md

-- Clear existing pilot test data
DELETE FROM tasks WHERE project_id = 'pilot-hello';
DELETE FROM agent_sessions WHERE agent_id IN ('pilot-owner', 'pilot-manager', 'pilot-worker-dev', 'pilot-worker-review');
DELETE FROM agent_credentials WHERE agent_id IN ('pilot-owner', 'pilot-manager', 'pilot-worker-dev', 'pilot-worker-review');
DELETE FROM agents WHERE id IN ('pilot-owner', 'pilot-manager', 'pilot-worker-dev', 'pilot-worker-review');
DELETE FROM project_agents WHERE project_id = 'pilot-hello';
DELETE FROM projects WHERE id = 'pilot-hello';

-- Insert pilot agents
-- Schema: id, name, role, type, status, hierarchy_type, parent_agent_id, role_type, max_parallel_tasks, capabilities, system_prompt, kick_method, created_at, updated_at

-- Owner (human role - operated by test script via Playwright)
INSERT INTO agents (id, name, role, type, status, hierarchy_type, parent_agent_id, role_type, max_parallel_tasks, capabilities, system_prompt, kick_method, created_at, updated_at)
VALUES (
    'pilot-owner', 'パイロットオーナー', 'Project Owner', 'human', 'active', 'owner', NULL, 'general', 1, NULL, NULL, 'cli',
    datetime('now'), datetime('now')
);

-- Manager (AI - task management only, no implementation work)
INSERT INTO agents (id, name, role, type, status, hierarchy_type, parent_agent_id, role_type, max_parallel_tasks, capabilities, system_prompt, kick_method, created_at, updated_at)
VALUES (
    'pilot-manager', '開発マネージャー', 'Development Manager', 'ai', 'active', 'manager', 'pilot-owner', 'general', 5, '["management"]',
    'あなたは開発マネージャーです。Ownerからの要件を受け取り、Workerに作業を割り当てます。

## 重要な行動指針
1. 要件を受け取ったら、必ず2つのタスクを作成してください
2. タスクは必ずWorkerに割り当ててください（自分自身には割り当てない）
3. 実装タスク → pilot-worker-dev に割り当て
4. 確認タスク → pilot-worker-review に割り当て
5. create_taskツールでタスクを作成し、assignee_idパラメータでWorkerを指定

## 重要: タスクのステータスを「in_progress」に変更する
タスクを作成したら、必ずupdate_task_statusツールを使って各タスクのステータスを「in_progress」に変更してください。
これにより、Workerが作業を開始できます。
- update_task_status(task_id, "in_progress")

## タスク作成と開始の手順
1. create_taskでタスク1を作成（assignee_id: pilot-worker-dev）
2. create_taskでタスク2を作成（assignee_id: pilot-worker-review）
3. update_task_statusでタスク1を「in_progress」に変更
4. update_task_statusでタスク2を「in_progress」に変更（タスク1の完了を待つ場合はタスク1完了後）

## タスク作成の例
- タスク1: 「hello.pyの作成」→ assignee_id: pilot-worker-dev → in_progressに変更
- タスク2: 「hello.pyの動作確認」→ assignee_id: pilot-worker-review → タスク1完了後にin_progressに変更

## 禁止事項
- 自分（pilot-manager）にタスクを割り当てない
- 自分で実装や確認作業をしない（管理のみ）
- タスクをbacklog状態のまま放置しない',
    'mcp', datetime('now'), datetime('now')
);

-- Worker-Dev (AI - implementation)
INSERT INTO agents (id, name, role, type, status, hierarchy_type, parent_agent_id, role_type, max_parallel_tasks, capabilities, system_prompt, kick_method, created_at, updated_at)
VALUES (
    'pilot-worker-dev', '開発エンジニア', 'Developer', 'ai', 'active', 'worker', 'pilot-manager', 'general', 3, '["coding"]',
    'あなたは開発エンジニアです。

## 責務
- 割り当てられた実装タスクを遂行する
- コードを作成し、プロジェクトの作業ディレクトリに保存する
- 作業完了後、進捗を報告する

## 行動指針
- シンプルで読みやすいコードを書く
- ファイルは作業ディレクトリに保存する
- 完了したら必ずタスクのステータスを更新する',
    'mcp', datetime('now'), datetime('now')
);

-- Worker-Review (AI - verification)
INSERT INTO agents (id, name, role, type, status, hierarchy_type, parent_agent_id, role_type, max_parallel_tasks, capabilities, system_prompt, kick_method, created_at, updated_at)
VALUES (
    'pilot-worker-review', 'レビューエンジニア', 'Reviewer', 'ai', 'active', 'worker', 'pilot-manager', 'general', 3, '["testing"]',
    'あなたはレビューエンジニアです。

## 責務
- 他のWorkerが作成した成果物を確認する
- 実際にコードを実行して動作を検証する
- 確認結果を報告する

## 行動指針
- 実装されたコードを実際に実行して確認する
- 期待通りの動作をするか検証する
- 問題があれば具体的に報告する',
    'mcp', datetime('now'), datetime('now')
);

-- Insert agent credentials
-- Hash: SHA256("test-passkeysalt") = 2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519
-- Using same passkey as integration tests for consistency
INSERT INTO agent_credentials (id, agent_id, passkey_hash, salt, raw_passkey, created_at)
VALUES
    ('cred-pilot-owner', 'pilot-owner', '2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519', 'salt', 'test-passkey', datetime('now')),
    ('cred-pilot-manager', 'pilot-manager', '2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519', 'salt', 'test-passkey', datetime('now')),
    ('cred-pilot-worker-dev', 'pilot-worker-dev', '2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519', 'salt', 'test-passkey', datetime('now')),
    ('cred-pilot-worker-review', 'pilot-worker-review', '2dc6fa1745a211ab436bff40df2f9c701572e44ab98d55b8121fe0cb1b2ae519', 'salt', 'test-passkey', datetime('now'));

-- Insert pilot project
INSERT INTO projects (id, name, description, status, working_directory, created_at, updated_at)
VALUES (
    'pilot-hello', 'Hello World パイロット', 'パイロットテスト: Hello Worldスクリプトの作成', 'active',
    '/tmp/pilot_hello_workspace', datetime('now'), datetime('now')
);

-- Assign agents to project
INSERT INTO project_agents (project_id, agent_id, assigned_at)
VALUES
    ('pilot-hello', 'pilot-owner', datetime('now')),
    ('pilot-hello', 'pilot-manager', datetime('now')),
    ('pilot-hello', 'pilot-worker-dev', datetime('now')),
    ('pilot-hello', 'pilot-worker-review', datetime('now'));
