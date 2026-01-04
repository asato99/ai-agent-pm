# 内部監査 (Internal Audit) 仕様

## 概要

Internal Auditは、プロジェクト横断でプロセス遵守を自動監視する仕組み。
**プロジェクトと同様に複数登録可能**なトップレベルエンティティ。

---

## 核となる概念: Audit Rules

Internal Auditの**メインの実態は「Audit Rules」**（トリガー付きワークフロー一覧）。

```
[Internal Audit インスタンス]
 │
 └─ Audit Rules（メインエンティティ）
     ├─ Rule 1: タスク完了時 → 手順遵守チェック
     ├─ Rule 2: ステータス変更時 → 承認フロー確認
     └─ Rule 3: 期限超過時 → 遅延理由記録要求
```

### Audit Rule の構成

| 要素 | 説明 |
|------|------|
| **トリガー条件** | いつワークフローを発火するか |
| **監査タスク定義** | インラインでタスク群を定義（エージェント割り当て含む） |

### エージェント割り当て

エージェントは**Audit Rule内で直接タスクに割り当て**:

```
[Audit Rule: タスク完了時の手順チェック]
 ├─ トリガー: タスク完了
 └─ 監査タスク（インライン定義）
     ├─ Task 1: 要件確認      → qa-auditor
     ├─ Task 2: 実装レビュー  → review-bot
     └─ Task 3: 最終承認      → owner
```

> **注**: WorkflowTemplateはプロジェクトスコープのため、プロジェクト横断で動作する
> Internal Audit はテンプレートを参照せず、タスク定義をインラインで保持する。

※ Internal Audit単位でのエージェント割り当てはない（Rule内のタスク単位で指定）

---

## 基本構造

### 複数インスタンス登録

プロジェクトと同様に、**複数の Internal Audit を登録可能**:

```
[Internal Audit 一覧]
 ├─ QA Audit（品質監査）
 │   └─ Rules: テスト実行確認、コードレビュー確認
 ├─ Security Audit（セキュリティ監査）
 │   └─ Rules: 脆弱性チェック、アクセス権確認
 └─ Compliance Audit（コンプライアンス監査）
     └─ Rules: 承認フロー確認、ドキュメント整備確認
```

### 監視範囲

各 Internal Audit は全プロジェクトを横断監視:

```
[QA Audit]                    [全プロジェクト]
 └─ Rules             ──監視──→ プロジェクトA, B, C

[Security Audit]              [全プロジェクト]
 └─ Rules             ──監視──→ プロジェクトA, B, C
```

---

## 自動トリガー機能

### トリガー条件

Internal Audit が**アクティブ**の場合、Audit Rules に定義されたトリガー条件でワークフローが自動キック:

| トリガー | 説明 | ワークフロー例 |
|----------|------|----------------|
| タスク完了 | 任意のタスクが `done` に変更 | 手順遵守チェック |
| ステータス変更 | 特定のステータス遷移 | 承認フロー確認 |
| ハンドオフ完了 | エージェント間の引き継ぎ | 引き継ぎ品質レビュー |
| 期限超過 | タスクが期限を過ぎた | 遅延理由の記録要求 |

### ワークフロー実行フロー

```
1. タスク "API実装" が done に変更される
2. Internal Audit がアクティブか確認
3. マッチする Audit Rule を検索
4. Rule の監査タスクからワークフローを生成:
   - AuditTask定義から実タスク群を生成
   - 設定済みのエージェントが各タスクにアサイン
5. 各エージェントがタスクを実行
6. 結果を監査履歴に記録
```

---

## Internal Audit の状態

| 状態 | 説明 |
|------|------|
| **Active** | 監査機能が有効。トリガー発火時にワークフロー実行 |
| **Inactive** | 監査機能が無効。トリガーは無視される |
| **Suspended** | 一時停止。手動で再開可能 |

---

## 監査エージェントの権限

### 閲覧権限
- 全プロジェクトの閲覧
- 全タスク・履歴へのアクセス
- エージェントの行動ログ閲覧

### ロック権限
- タスクの強制ロック（作業停止）
- エージェントの強制ロック（活動停止）

### ロック解除
- **監査エージェントのみ**解除可能

---

## ロック機能

### ロックの種類

| 種類 | 対象 | 効果 |
|------|------|------|
| タスクロック | 特定タスク | 状態変更を禁止 |
| エージェントロック | 特定エージェント | 全操作を禁止 |

---

## 位置づけ

- プロジェクトと**同様のトップレベルエンティティ**
- 複数インスタンス登録可能

```
[トップレベル]
 ├─ プロジェクト群
 │   ├─ プロジェクトA
 │   └─ プロジェクトB
 ├─ エージェント群
 │   ├─ owner
 │   └─ backend-dev
 └─ Internal Audit 群 ★
     ├─ QA Audit
     ├─ Security Audit
     └─ Compliance Audit
```

---

## エンティティ定義

### InternalAudit

| 属性 | 型 | 必須 | 説明 |
|------|-----|------|------|
| id | InternalAuditID | ○ | 一意識別子 |
| name | String | ○ | 監査名 |
| description | String | | 説明 |
| status | AuditStatus | ○ | active / inactive / suspended |
| createdAt | Date | ○ | 作成日時 |
| updatedAt | Date | ○ | 更新日時 |

### AuditRule

| 属性 | 型 | 必須 | 説明 |
|------|-----|------|------|
| id | AuditRuleID | ○ | 一意識別子 |
| auditId | InternalAuditID | ○ | 所属するInternal Audit |
| name | String | ○ | ルール名 |
| triggerType | TriggerType | ○ | トリガー種別 |
| triggerConfig | JSON | | トリガーの追加設定 |
| auditTasks | [AuditTask] | ○ | 監査ワークフローのタスク定義（インライン） |
| isEnabled | Bool | ○ | ルールが有効か |
| createdAt | Date | ○ | 作成日時 |
| updatedAt | Date | ○ | 更新日時 |

> **設計方針**: WorkflowTemplateはプロジェクトスコープのため、プロジェクト横断で動作する
> Internal Audit のルールは、タスク定義をインラインで保持する（テンプレート参照ではない）。

### AuditTask

| 属性 | 型 | 必須 | 説明 |
|------|-----|------|------|
| order | Int | ○ | タスクの順序 |
| title | String | ○ | タスクタイトル |
| description | String | | タスク説明 |
| assigneeId | AgentID | ○ | 割り当てるエージェント |
| priority | TaskPriority | ○ | 優先度 |
| dependsOnOrders | [Int] | | 依存する他タスクのorder |

### TriggerType

| 値 | 説明 |
|-----|------|
| task_completed | タスク完了時 |
| status_changed | ステータス変更時 |
| handoff_completed | ハンドオフ完了時 |
| deadline_exceeded | 期限超過時 |

---

## 将来拡張

- カスタムトリガー条件（Webhook連携など）
- 監査レポート自動生成
- コンプライアンススコアリング
- ルールテンプレート機能
- トリガーフィルタ（特定プロジェクトのみ等）
