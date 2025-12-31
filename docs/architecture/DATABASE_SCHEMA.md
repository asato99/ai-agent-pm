# データベーススキーマ設計

SQLiteデータベースのテーブル設計とマイグレーション戦略。

---

## ER図

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           Database Schema                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────┐                     ┌─────────────┐                    │
│  │  projects   │──────1:N───────────│   agents    │                    │
│  └──────┬──────┘                     └──────┬──────┘                    │
│         │                                    │                           │
│         │ 1:N                               │ 1:N                        │
│         ▼                                    ▼                           │
│  ┌─────────────┐                     ┌─────────────┐                    │
│  │    tasks    │                     │  sessions   │                    │
│  └──────┬──────┘                     └─────────────┘                    │
│         │                                                                │
│    ┌────┼────┬────────────┐                                             │
│    │    │    │            │                                             │
│    ▼    ▼    ▼            ▼                                             │
│ ┌──────┐ ┌──────┐ ┌──────────┐ ┌──────────────────┐                    │
│ │subtasks│ │contexts│ │handoffs │ │task_dependencies │                    │
│ └──────┘ └──────┘ └──────────┘ └──────────────────┘                    │
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                    state_change_events                           │   │
│  │                  (イベントソーシングテーブル)                      │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## テーブル定義

### projects

```sql
CREATE TABLE projects (
    id              TEXT PRIMARY KEY,           -- prj_xxx
    name            TEXT NOT NULL,
    description     TEXT NOT NULL DEFAULT '',
    status          TEXT NOT NULL DEFAULT 'active',  -- active, archived
    created_at      TEXT NOT NULL,              -- ISO8601
    updated_at      TEXT NOT NULL,
    archived_at     TEXT,

    CHECK (status IN ('active', 'archived'))
);

CREATE INDEX idx_projects_status ON projects(status);
CREATE INDEX idx_projects_updated_at ON projects(updated_at);
```

### agents

```sql
CREATE TABLE agents (
    id              TEXT PRIMARY KEY,           -- agt_xxx
    project_id      TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    name            TEXT NOT NULL,
    role            TEXT NOT NULL,
    type            TEXT NOT NULL,              -- human, ai
    role_type       TEXT NOT NULL DEFAULT 'worker',  -- owner, manager, worker, viewer
    capabilities    TEXT NOT NULL DEFAULT '[]', -- JSON array
    system_prompt   TEXT,
    status          TEXT NOT NULL DEFAULT 'active',  -- active, inactive, archived
    created_at      TEXT NOT NULL,
    updated_at      TEXT NOT NULL,

    CHECK (type IN ('human', 'ai')),
    CHECK (role_type IN ('owner', 'manager', 'worker', 'viewer')),
    CHECK (status IN ('active', 'inactive', 'archived')),
    UNIQUE (project_id, name)
);

CREATE INDEX idx_agents_project_id ON agents(project_id);
CREATE INDEX idx_agents_status ON agents(status);
CREATE INDEX idx_agents_type ON agents(type);
```

### sessions

```sql
CREATE TABLE sessions (
    id              TEXT PRIMARY KEY,           -- ses_xxx
    agent_id        TEXT NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
    project_id      TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    tool_type       TEXT NOT NULL,              -- claude_code, gemini, human, other
    status          TEXT NOT NULL DEFAULT 'active',  -- active, ended
    started_at      TEXT NOT NULL,
    ended_at        TEXT,
    summary         TEXT,

    CHECK (tool_type IN ('claude_code', 'gemini', 'human', 'other')),
    CHECK (status IN ('active', 'ended'))
);

CREATE INDEX idx_sessions_agent_id ON sessions(agent_id);
CREATE INDEX idx_sessions_project_id ON sessions(project_id);
CREATE INDEX idx_sessions_status ON sessions(status);
CREATE INDEX idx_sessions_started_at ON sessions(started_at);
```

### tasks

```sql
CREATE TABLE tasks (
    id                  TEXT PRIMARY KEY,       -- tsk_xxx
    project_id          TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    title               TEXT NOT NULL,
    description         TEXT NOT NULL DEFAULT '',
    status              TEXT NOT NULL DEFAULT 'backlog',
    priority            TEXT NOT NULL DEFAULT 'medium',
    assignee_id         TEXT REFERENCES agents(id) ON DELETE SET NULL,
    parent_task_id      TEXT REFERENCES tasks(id) ON DELETE SET NULL,
    estimated_minutes   INTEGER,
    actual_minutes      INTEGER,
    created_at          TEXT NOT NULL,
    updated_at          TEXT NOT NULL,
    completed_at        TEXT,

    CHECK (status IN ('backlog', 'todo', 'in_progress', 'review', 'blocked', 'done', 'cancelled')),
    CHECK (priority IN ('critical', 'high', 'medium', 'low'))
);

CREATE INDEX idx_tasks_project_id ON tasks(project_id);
CREATE INDEX idx_tasks_status ON tasks(status);
CREATE INDEX idx_tasks_assignee_id ON tasks(assignee_id);
CREATE INDEX idx_tasks_parent_task_id ON tasks(parent_task_id);
CREATE INDEX idx_tasks_priority ON tasks(priority);
CREATE INDEX idx_tasks_updated_at ON tasks(updated_at);
```

### task_dependencies

```sql
CREATE TABLE task_dependencies (
    task_id         TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    depends_on_id   TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    created_at      TEXT NOT NULL,

    PRIMARY KEY (task_id, depends_on_id),
    CHECK (task_id != depends_on_id)
);

CREATE INDEX idx_task_dependencies_depends_on_id ON task_dependencies(depends_on_id);
```

### subtasks

```sql
CREATE TABLE subtasks (
    id              TEXT PRIMARY KEY,           -- sub_xxx
    task_id         TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    title           TEXT NOT NULL,
    is_completed    INTEGER NOT NULL DEFAULT 0, -- 0=false, 1=true
    sort_order      INTEGER NOT NULL DEFAULT 0,
    created_at      TEXT NOT NULL,
    completed_at    TEXT
);

CREATE INDEX idx_subtasks_task_id ON subtasks(task_id);
CREATE INDEX idx_subtasks_sort_order ON subtasks(task_id, sort_order);
```

### contexts

```sql
CREATE TABLE contexts (
    id              TEXT PRIMARY KEY,           -- ctx_xxx
    task_id         TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    agent_id        TEXT NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
    session_id      TEXT REFERENCES sessions(id) ON DELETE SET NULL,
    content         TEXT NOT NULL,
    type            TEXT NOT NULL,              -- note, decision, assumption, blocker, reference, artifact
    created_at      TEXT NOT NULL,

    CHECK (type IN ('note', 'decision', 'assumption', 'blocker', 'reference', 'artifact'))
);

CREATE INDEX idx_contexts_task_id ON contexts(task_id);
CREATE INDEX idx_contexts_agent_id ON contexts(agent_id);
CREATE INDEX idx_contexts_type ON contexts(type);
CREATE INDEX idx_contexts_created_at ON contexts(created_at);
```

### handoffs

```sql
CREATE TABLE handoffs (
    id              TEXT PRIMARY KEY,           -- hnd_xxx
    task_id         TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    from_agent_id   TEXT NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
    to_agent_id     TEXT REFERENCES agents(id) ON DELETE SET NULL,
    session_id      TEXT REFERENCES sessions(id) ON DELETE SET NULL,
    summary         TEXT NOT NULL,
    next_steps      TEXT NOT NULL DEFAULT '[]', -- JSON array
    warnings        TEXT NOT NULL DEFAULT '[]', -- JSON array
    status          TEXT NOT NULL DEFAULT 'pending',  -- pending, acknowledged, completed
    created_at      TEXT NOT NULL,
    acknowledged_at TEXT,

    CHECK (status IN ('pending', 'acknowledged', 'completed'))
);

CREATE INDEX idx_handoffs_task_id ON handoffs(task_id);
CREATE INDEX idx_handoffs_from_agent_id ON handoffs(from_agent_id);
CREATE INDEX idx_handoffs_to_agent_id ON handoffs(to_agent_id);
CREATE INDEX idx_handoffs_status ON handoffs(status);
CREATE INDEX idx_handoffs_created_at ON handoffs(created_at);
```

### state_change_events

```sql
CREATE TABLE state_change_events (
    id              TEXT PRIMARY KEY,           -- evt_xxx
    project_id      TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    entity_type     TEXT NOT NULL,              -- project, task, subtask, agent, session, context, handoff
    entity_id       TEXT NOT NULL,
    event_type      TEXT NOT NULL,              -- created, updated, deleted, status_changed, etc.
    agent_id        TEXT REFERENCES agents(id) ON DELETE SET NULL,
    session_id      TEXT REFERENCES sessions(id) ON DELETE SET NULL,
    previous_state  TEXT,                       -- JSON
    new_state       TEXT,                       -- JSON
    reason          TEXT,
    metadata        TEXT,                       -- JSON
    timestamp       TEXT NOT NULL,

    CHECK (entity_type IN ('project', 'task', 'subtask', 'agent', 'session', 'context', 'handoff'))
);

CREATE INDEX idx_events_project_id ON state_change_events(project_id);
CREATE INDEX idx_events_entity ON state_change_events(entity_type, entity_id);
CREATE INDEX idx_events_event_type ON state_change_events(event_type);
CREATE INDEX idx_events_agent_id ON state_change_events(agent_id);
CREATE INDEX idx_events_timestamp ON state_change_events(timestamp);

-- 複合インデックス（監査ログ用）
CREATE INDEX idx_events_audit ON state_change_events(project_id, timestamp DESC);
CREATE INDEX idx_events_entity_history ON state_change_events(entity_type, entity_id, timestamp DESC);
```

---

## マイグレーション戦略

### バージョン管理

```sql
CREATE TABLE schema_migrations (
    version     INTEGER PRIMARY KEY,
    applied_at  TEXT NOT NULL
);
```

### マイグレーションファイル構成

```
Sources/Infrastructure/Database/Migrations/
├── Migration.swift           # Protocol定義
├── MigrationRunner.swift     # マイグレーション実行
├── V001_InitialSchema.swift  # 初期スキーマ
├── V002_AddMetadata.swift    # 将来の変更
└── ...
```

### マイグレーション実装例

```swift
protocol Migration {
    static var version: Int { get }
    static func up(_ db: Database) throws
    static func down(_ db: Database) throws
}

struct V001_InitialSchema: Migration {
    static let version = 1

    static func up(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE projects (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                ...
            );
        """)
        // 他のテーブル作成
    }

    static func down(_ db: Database) throws {
        try db.execute(sql: "DROP TABLE IF EXISTS state_change_events;")
        try db.execute(sql: "DROP TABLE IF EXISTS handoffs;")
        // 逆順で削除
    }
}
```

---

## GRDB.swift Record定義

### ProjectRecord

```swift
struct ProjectRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "projects"

    var id: String
    var name: String
    var description: String
    var status: String
    var createdAt: String
    var updatedAt: String
    var archivedAt: String?

    // Domain変換
    func toDomain() -> Project {
        Project(
            id: ProjectID(value: id),
            name: name,
            description: description,
            status: ProjectStatus(rawValue: status) ?? .active,
            createdAt: ISO8601DateFormatter().date(from: createdAt) ?? Date(),
            updatedAt: ISO8601DateFormatter().date(from: updatedAt) ?? Date(),
            archivedAt: archivedAt.flatMap { ISO8601DateFormatter().date(from: $0) }
        )
    }

    static func fromDomain(_ project: Project) -> ProjectRecord {
        ProjectRecord(
            id: project.id.value,
            name: project.name,
            description: project.description,
            status: project.status.rawValue,
            createdAt: ISO8601DateFormatter().string(from: project.createdAt),
            updatedAt: ISO8601DateFormatter().string(from: project.updatedAt),
            archivedAt: project.archivedAt.map { ISO8601DateFormatter().string(from: $0) }
        )
    }
}
```

---

## パフォーマンス考慮

### インデックス戦略

| 用途 | インデックス | クエリ例 |
|------|-------------|----------|
| プロジェクト一覧 | `idx_projects_status` | アクティブプロジェクト取得 |
| タスクボード | `idx_tasks_project_id`, `idx_tasks_status` | ステータス別タスク取得 |
| エージェント作業 | `idx_tasks_assignee_id` | 担当タスク取得 |
| 監査ログ | `idx_events_audit` | 時系列イベント取得 |
| 履歴表示 | `idx_events_entity_history` | Entity別履歴取得 |

### クエリ最適化

```sql
-- 効率的なタスクボードクエリ
SELECT t.*, a.name as assignee_name
FROM tasks t
LEFT JOIN agents a ON t.assignee_id = a.id
WHERE t.project_id = ?
ORDER BY t.priority, t.updated_at DESC;

-- 効率的なイベント取得（ページネーション）
SELECT *
FROM state_change_events
WHERE project_id = ?
ORDER BY timestamp DESC
LIMIT ? OFFSET ?;
```

---

## データ整合性

### 外部キー制約

- `ON DELETE CASCADE`: 親削除時に子も削除（tasks → subtasks）
- `ON DELETE SET NULL`: 親削除時にNULL（tasks → assignee_id）

### 排他制御

```swift
// GRDB.swiftでの排他制御
try dbQueue.write { db in
    // トランザクション内で実行
    try task.update(db)
    try event.insert(db)
}
```

---

## 変更履歴

| 日付 | バージョン | 変更内容 |
|------|-----------|----------|
| 2024-12-30 | 1.0.0 | 初版作成 |
