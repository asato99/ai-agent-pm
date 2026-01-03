# ワークフローテンプレート要件

## 概要

一連のタスクをテンプレートとして定義し、繰り返し適用できる機能。
プロジェクト横断で再利用可能なワークフローを管理する。

---

## 用語定義

| 用語 | 説明 |
|------|------|
| WorkflowTemplate | タスクの雛形をまとめたテンプレート |
| TemplateTask | テンプレート内の個別タスク定義 |
| インスタンス化 | テンプレートから実際のタスク群を生成すること |
| 変数 | インスタンス化時に置換されるプレースホルダー |

---

## エンティティ

### WorkflowTemplate

| 属性 | 型 | 必須 | 説明 |
|------|-----|------|------|
| id | WorkflowTemplateID | ○ | 一意識別子 |
| name | String | ○ | テンプレート名 |
| description | String | | テンプレートの説明 |
| variables | [String] | | 変数名のリスト（例: ["feature_name", "module"]） |
| status | TemplateStatus | ○ | active / archived |
| createdAt | Date | ○ | 作成日時 |
| updatedAt | Date | ○ | 更新日時 |

### TemplateTask

| 属性 | 型 | 必須 | 説明 |
|------|-----|------|------|
| id | TemplateTaskID | ○ | 一意識別子 |
| templateId | WorkflowTemplateID | ○ | 所属テンプレート |
| title | String | ○ | タスクタイトル（変数使用可） |
| description | String | | タスク説明（変数使用可） |
| order | Int | ○ | テンプレート内での順序 |
| dependsOnOrders | [Int] | | 依存する他タスクのorder |
| defaultAssigneeRole | AgentRoleType? | | デフォルトのアサイン先ロール |
| defaultPriority | TaskPriority | ○ | デフォルト優先度 |
| estimatedMinutes | Int? | | 見積もり時間 |

---

## ステータス

### TemplateStatus

```
active ←→ archived
```

- **active**: 使用可能なテンプレート
- **archived**: アーカイブ済み（一覧に表示しない）

---

## 変数システム

### 変数の記法

```
{{variable_name}}
```

### 使用例

テンプレート定義:
```
title: "{{feature_name}} - 要件確認"
description: "{{module}}モジュールの{{feature_name}}機能について要件を確認する"
```

インスタンス化時の入力:
```
feature_name: "ログイン機能"
module: "認証"
```

生成されるタスク:
```
title: "ログイン機能 - 要件確認"
description: "認証モジュールのログイン機能について要件を確認する"
```

---

## ユースケース

### UC-WT-01: テンプレート作成

**アクター**: ユーザー

**フロー**:
1. ユーザーがテンプレート一覧画面で「新規作成」を選択
2. テンプレート名、説明、変数を入力
3. タスクを追加（タイトル、説明、依存関係、優先度）
4. 保存

**事後条件**: テンプレートが保存され、一覧に表示される

### UC-WT-02: テンプレートからタスク生成（インスタンス化）

**アクター**: ユーザー

**フロー**:
1. ユーザーがテンプレート一覧から適用するテンプレートを選択
2. 適用先プロジェクトを選択
3. 変数の値を入力
4. エージェントのアサイン（オプション）
5. 「タスク生成」を実行
6. システムがタスク群を生成（依存関係も設定）

**事後条件**:
- プロジェクトにタスク群が追加される
- タスク間の依存関係が設定される
- 全タスクが `backlog` ステータスで作成される

### UC-WT-03: テンプレート編集

**アクター**: ユーザー

**フロー**:
1. テンプレート一覧から編集対象を選択
2. 内容を編集
3. 保存

**注意**: 既にインスタンス化されたタスクには影響しない

### UC-WT-04: テンプレートアーカイブ

**アクター**: ユーザー

**フロー**:
1. テンプレート一覧から対象を選択
2. 「アーカイブ」を選択
3. 確認後、ステータスが `archived` に変更

---

## UI要件

### テンプレート一覧画面

- テンプレート名、説明、タスク数を表示
- 新規作成ボタン
- 各テンプレートに対して:
  - 編集
  - インスタンス化（適用）
  - アーカイブ
- アーカイブ済みの表示/非表示切り替え

### テンプレート作成/編集画面

- テンプレート名（必須）
- 説明
- 変数リスト（追加/削除可能）
- タスクリスト:
  - ドラッグ&ドロップで順序変更
  - 各タスク: タイトル、説明、依存関係、優先度、見積もり
  - タスク追加/削除

### インスタンス化画面（シート）

- 適用先プロジェクト選択
- 変数入力フォーム（テンプレートの変数ごと）
- プレビュー（生成されるタスク一覧）
- エージェントアサイン（オプション）
- 生成ボタン

---

## アクセシビリティ識別子

| 要素 | 識別子 |
|------|--------|
| テンプレート一覧 | TemplateList |
| テンプレート行 | TemplateRow_{id} |
| 新規作成ボタン | NewTemplateButton |
| テンプレートフォーム | TemplateForm |
| テンプレート名入力 | TemplateNameField |
| 変数リスト | TemplateVariablesList |
| タスクリスト | TemplateTasksList |
| タスク追加ボタン | AddTemplateTaskButton |
| インスタンス化シート | InstantiateSheet |
| プロジェクト選択 | InstantiateProjectPicker |
| 変数入力フィールド | VariableField_{name} |
| 生成ボタン | InstantiateButton |

---

## データベーススキーマ

### workflow_templates テーブル

```sql
CREATE TABLE workflow_templates (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT DEFAULT '',
    variables TEXT,  -- JSON array: ["var1", "var2"]
    status TEXT NOT NULL DEFAULT 'active',
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL
);
```

### template_tasks テーブル

```sql
CREATE TABLE template_tasks (
    id TEXT PRIMARY KEY,
    template_id TEXT NOT NULL REFERENCES workflow_templates(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT DEFAULT '',
    "order" INTEGER NOT NULL,
    depends_on_orders TEXT,  -- JSON array: [1, 2]
    default_assignee_role TEXT,
    default_priority TEXT NOT NULL DEFAULT 'medium',
    estimated_minutes INTEGER
);

CREATE INDEX idx_template_tasks_template_id ON template_tasks(template_id);
```

---

## 制約・バリデーション

1. **テンプレート名**: 必須、1〜100文字
2. **変数名**: 英数字とアンダースコアのみ（`[a-zA-Z_][a-zA-Z0-9_]*`）
3. **タスクタイトル**: 必須、1〜200文字
4. **依存関係**: 自己参照禁止、循環禁止
5. **order**: テンプレート内で一意

---

## 将来の拡張（スコープ外）

- テンプレートのインポート/エクスポート（YAML/JSON）
- テンプレートの共有（チーム間）
- 条件分岐（変数値によるタスク生成の分岐）
- 繰り返しタスク（Recurring）との統合
