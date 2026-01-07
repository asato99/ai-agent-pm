# プロジェクト (Project) 仕様

## 構造

```
[トップレベル]
 ├─ プロジェクト群
 ├─ エージェント群
 └─ 監査チーム群

プロジェクト ←── 割り当て ──→ エージェント
監査チーム  ←── 割り当て ──→ エージェント（監査権限付き）
```

- プロジェクト、エージェント、監査チームは同列のトップレベル概念
- エージェントをプロジェクトまたは監査チームに割り当てる

---

## 属性

| 属性 | 必須 | 説明 |
|------|------|------|
| 名前 | ✓ | プロジェクトの識別名 |
| 説明 | | プロジェクトの概要 |
| workingDirectory | ✓ | 作業ディレクトリのパス |
| 割り当てエージェント | | 参加するエージェント群（明示的に割り当て） |

---

## エージェント割り当て

### 設計原則

1. **明示的割り当て**: エージェントはプロジェクトに明示的に割り当てる
2. **タスク担当者の制約**: タスクの担当者は、そのプロジェクトに割り当て済みのエージェントに限定される

### データ構造

```sql
-- プロジェクト×エージェント割り当てテーブル
CREATE TABLE project_agents (
    project_id TEXT NOT NULL REFERENCES projects(id),
    agent_id TEXT NOT NULL REFERENCES agents(id),
    assigned_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (project_id, agent_id)
);
```

### 制約

```
タスク.assignee_id ∈ プロジェクト.割り当てエージェント

例:
  Project A に [Agent X, Agent Y] が割り当て済み
  → Task(project=A) の担当者は Agent X または Agent Y のみ選択可能
  → Agent Z は選択不可（割り当てられていないため）
```

### UI要件

1. **プロジェクト設定画面**: エージェント割り当ての追加/削除
2. **タスク作成/編集画面**: 担当者選択は割り当て済みエージェントのみ表示
3. **バリデーション**: 未割り当てエージェントへのタスクアサインをブロック

---

## Working Directory

### 用途

- Agent Instanceの起動時にcwd（カレントディレクトリ）として使用
- プロジェクトごとに独立した作業環境を提供

### 制約

- 有効なディレクトリパスであること
- Coordinatorがアクセス可能なパスであること

### 例

```
Project: Frontend App
workingDirectory: /Users/dev/projects/frontend-app

Project: Backend API
workingDirectory: /Users/dev/projects/backend-api
```

---

## 関連

- **タスク**: プロジェクトに属する
- **履歴**: プロジェクト単位で記録される
- **Agent Instance**: プロジェクトのworkingDirectoryで実行される

---

## ステータス

| 状態 | 説明 |
|------|------|
| active | 進行中 |
| archived | アーカイブ済み |

---

## MCP API

### list_active_projects_with_agents

アクティブなプロジェクトと割り当てエージェントの一覧を返す。

```json
{
  "projects": [
    {
      "project_id": "prj_frontend",
      "project_name": "Frontend App",
      "working_directory": "/projects/frontend",
      "agents": ["agt_developer", "agt_reviewer"]
    }
  ]
}
```

**実装**:
```sql
SELECT
    p.id as project_id,
    p.name as project_name,
    p.working_directory,
    GROUP_CONCAT(pa.agent_id) as agents
FROM projects p
LEFT JOIN project_agents pa ON p.id = pa.project_id
WHERE p.status = 'active'
GROUP BY p.id
```
