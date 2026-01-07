# UC004: 複数プロジェクト×同一エージェント

## 概要

同一エージェントが複数のプロジェクトに割り当てられ、各プロジェクトで独立してタスクを実行するシナリオ。

---

## ユースケース目的

### 検証したいこと

1. **プロジェクト分離**: 同一エージェントでも、異なるプロジェクトのタスクは別々のAgent Instanceで実行される
2. **Working Directory**: 各Agent Instanceは正しいプロジェクトのworking_directoryで動作する
3. **並列実行**: 同一エージェントの複数Agent Instanceが同時に実行可能
4. **ファイル分離**: 各プロジェクトで生成されたファイルが干渉しない

### ビジネス価値

- 1人の専門家（エージェント）を複数プロジェクトで共有できる
- プロジェクトごとに異なる作業環境（リポジトリ）で作業可能
- スケーラブルなタスク実行

---

## 前提条件

### アプリ側の実装要件

| 機能 | 状態 | 説明 |
|------|------|------|
| プロジェクトへのエージェント割り当て | **要実装** | どのエージェントがどのプロジェクトで作業可能か |
| Project.workingDirectory | 存在 | 各プロジェクトの作業ディレクトリ |
| タスクのプロジェクト所属 | 存在 | タスクは必ずプロジェクトに紐づく |

### MCP API要件

| API | 状態 | 説明 |
|-----|------|------|
| `list_active_projects_with_agents` | **要実装** | プロジェクト+割り当てエージェント一覧 |
| `should_start(agent_id, project_id)` | **要実装** | (agent, project)単位の起動判断 |
| `authenticate(agent_id, passkey, project_id)` | **要実装** | project_id付き認証 |

---

## シナリオ

### シナリオ構成

```
エージェント:
  - agt_developer: 開発者エージェント（system_prompt: コード実装担当）

プロジェクト:
  - prj_frontend: フロントエンドアプリ（working_dir: /projects/frontend）
  - prj_backend: バックエンドAPI（working_dir: /projects/backend）

タスク:
  - tsk_fe_001: READMEを作成（prj_frontend, agt_developer）
  - tsk_be_001: READMEを作成（prj_backend, agt_developer）
```

### 期待される動作

```
1. Coordinator起動

2. list_active_projects_with_agents() →
   {
     projects: [
       { project_id: "prj_frontend", working_directory: "/projects/frontend", agents: ["agt_developer"] },
       { project_id: "prj_backend", working_directory: "/projects/backend", agents: ["agt_developer"] }
     ]
   }

3. should_start("agt_developer", "prj_frontend") → { should_start: true, ai_type: "claude" }
4. should_start("agt_developer", "prj_backend") → { should_start: true, ai_type: "claude" }

5. Agent Instance A 起動（agt_developer/prj_frontend, cwd=/projects/frontend）
6. Agent Instance B 起動（agt_developer/prj_backend, cwd=/projects/backend）

7. 各インスタンスが並列でタスク実行
   - Instance A: /projects/frontend/README.md を作成
   - Instance B: /projects/backend/README.md を作成

8. 両インスタンスが完了報告して終了
```

### 成功条件

```
/projects/frontend/README.md が存在
/projects/backend/README.md が存在
両ファイルの内容が異なる（プロジェクト固有の情報を含む）
```

---

## 実装設計

### 1. プロジェクトへのエージェント割り当て

**採用方式: 明示的な割り当てテーブル**

```sql
CREATE TABLE project_agents (
    project_id TEXT NOT NULL REFERENCES projects(id),
    agent_id TEXT NOT NULL REFERENCES agents(id),
    assigned_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (project_id, agent_id)
);
```

**設計原則**:
- エージェントはプロジェクトに**明示的に割り当てる**
- タスクの担当者は、**割り当て済みエージェントの範囲内**に限定

詳細は `docs/requirements/PROJECTS.md` を参照。

### 2. list_active_projects_with_agents の実装

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

### 3. セッション管理

```
セッションキー: (agent_id, project_id)

同時に存在可能:
- session(agt_developer, prj_frontend)
- session(agt_developer, prj_backend)

同時に存在不可（二重起動防止）:
- session(agt_developer, prj_frontend) × 2
```

---

## テスト設計

### テストデータ

```swift
// プロジェクト
Project(id: "prj_uc004_fe", name: "UC004 Frontend", workingDirectory: "/tmp/uc004/frontend")
Project(id: "prj_uc004_be", name: "UC004 Backend", workingDirectory: "/tmp/uc004/backend")

// エージェント（1つ）
Agent(id: "agt_uc004_dev", name: "UC004開発者", aiType: .claude, systemPrompt: "...")

// タスク（各プロジェクトに1つ）
Task(id: "tsk_uc004_fe", projectId: "prj_uc004_fe", assigneeId: "agt_uc004_dev", title: "README作成", status: .in_progress)
Task(id: "tsk_uc004_be", projectId: "prj_uc004_be", assigneeId: "agt_uc004_dev", title: "README作成", status: .in_progress)

// 認証情報
AgentCredential(agentId: "agt_uc004_dev", passkey: "test_passkey_uc004")
```

### 検証項目

| # | 検証内容 | 期待結果 |
|---|----------|----------|
| 1 | Agent Instance が2つ起動される | 別プロセスとして並列実行 |
| 2 | 各インスタンスのcwdが正しい | fe=/tmp/uc004/frontend, be=/tmp/uc004/backend |
| 3 | 各プロジェクトにファイルが作成される | README.md が両方に存在 |
| 4 | ファイル内容がプロジェクト固有 | 異なる内容 |
| 5 | 二重起動が防止される | 同一(agent,project)の2回目起動は失敗 |

---

## 依存関係

### 先行して必要な実装

1. **Phase 4-0**: プロジェクトへのエージェント割り当て機能
2. **Phase 4-1**: `list_active_projects_with_agents` API
3. **Phase 4-1**: `should_start(agent_id, project_id)` API
4. **Phase 4-2**: `authenticate(agent_id, passkey, project_id)` API

### 関連ユースケース

| UC | 関係 |
|----|------|
| UC001 | 単一エージェント×単一プロジェクト（基本形） |
| UC002 | 複数エージェント×単一プロジェクト（system_prompt差異） |
| UC003 | ai_type切り替え（将来） |
| **UC004** | **複数プロジェクト×同一エージェント（本UC）** |

---

## 未決事項

1. ~~**割り当て方式**: A/B/Cのどれを採用するか~~ → **決定: 明示的割り当てテーブル方式**
2. **UI設計**: プロジェクトへのエージェント割り当て画面の詳細
3. **並列数制限**: 同一エージェントの同時実行数に上限を設けるか

---

## 変更履歴

| 日付 | 内容 |
|------|------|
| 2026-01-07 | 初版作成 |
