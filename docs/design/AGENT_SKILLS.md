# エージェントスキル機能 設計書

## 1. 概要

エージェントにスキル（カスタムコマンド）を割り当て、起動時に自動配置する機能。

Claude Code / Gemini CLI 両対応。同一ディレクトリ構成（`skills/`）でスキルを管理。

## 2. 背景と目的

### 2.1 現状

- エージェントは system_prompt のみでカスタマイズ
- Claude Code のスキル機能（`.claude/skills/`）を活用できていない
- Gemini CLI も同様にスキル機能を活用できていない

### 2.2 目的

- エージェントごとに異なるスキルセットを割り当て可能にする
- スキルをアプリ側でマスタ管理し、再利用性を高める
- コードレビュー、テスト作成など、役割に応じたスキルを付与

---

## 3. データモデル

### 3.1 スキル定義（SkillDefinition）

アプリ側でマスタ管理するスキルの定義。

```swift
struct SkillDefinition: Identifiable {
    let id: SkillID
    let name: String              // 表示名（例：「コードレビュー」）
    let directoryName: String     // ディレクトリ名（例：「code-review」）
    let content: String           // SKILL.md の全内容（frontmatter含む）
    let createdAt: Date
    let updatedAt: Date
}

// 例
SkillDefinition(
    id: "skill_001",
    name: "コードレビュー",
    directoryName: "code-review",
    content: """
    ---
    name: code-review
    description: コードの品質、セキュリティ、パフォーマンスをレビューする
    ---

    ## コードレビュー手順

    1. セキュリティ脆弱性のチェック
    2. パフォーマンス問題の検出
    3. コーディング規約の確認
    4. 改善提案の提示
    """
)
```

### 3.2 エージェントスキル割り当て（AgentSkillAssignment）

エージェントとスキルの多対多関係。

```swift
struct AgentSkillAssignment {
    let agentId: AgentID
    let skillId: SkillID
    let assignedAt: Date
}
```

### 3.3 ER図

```
┌─────────────────┐       ┌──────────────────────┐       ┌─────────────────┐
│     Agent       │       │ AgentSkillAssignment │       │ SkillDefinition │
├─────────────────┤       ├──────────────────────┤       ├─────────────────┤
│ id (PK)         │──1:N──│ agentId (FK)         │       │ id (PK)         │
│ name            │       │ skillId (FK)         │──N:1──│ name            │
│ provider        │       │ assignedAt           │       │ directoryName   │
│ system_prompt   │       └──────────────────────┘       │ content         │
└─────────────────┘                                      │ createdAt       │
                                                         │ updatedAt       │
                                                         └─────────────────┘
```

---

## 4. UI設計

### 4.1 スキル管理画面

**場所:** 設定 > スキル管理（新規メニュー）

| 要素 | 説明 |
|------|------|
| スキル一覧 | 登録済みスキルをリスト表示 |
| 追加ボタン | 新規スキル作成モーダルを開く |
| 編集 | スキル内容を編集 |
| 削除 | スキルを削除（使用中の場合は警告） |

### 4.2 スキル作成・編集モーダル

```
┌─────────────────────────────────────────────────┐
│ スキル作成                              [×]     │
├─────────────────────────────────────────────────┤
│                                                 │
│ スキル名:                                       │
│ ┌─────────────────────────────────────────────┐ │
│ │ コードレビュー                              │ │
│ └─────────────────────────────────────────────┘ │
│                                                 │
│ ディレクトリ名:                                 │
│ ┌─────────────────────────────────────────────┐ │
│ │ code-review                                 │ │
│ └─────────────────────────────────────────────┘ │
│ ※ 英数字・ハイフンのみ                         │
│                                                 │
│ 内容 (SKILL.md):                               │
│ ┌─────────────────────────────────────────────┐ │
│ │ ---                                         │ │
│ │ name: code-review                           │ │
│ │ description: コードをレビューする           │ │
│ │ ---                                         │ │
│ │                                             │ │
│ │ ## レビュー手順                             │ │
│ │ 1. セキュリティチェック                     │ │
│ │ ...                                         │ │
│ └─────────────────────────────────────────────┘ │
│                                                 │
│              [キャンセル]  [保存]               │
└─────────────────────────────────────────────────┘
```

### 4.3 エージェントスキル割り当てモーダル

**開き方:** エージェント詳細画面 > 「スキル設定」ボタン

```
┌─────────────────────────────────────────────────┐
│ スキル割り当て: Worker-01                [×]   │
├─────────────────────────────────────────────────┤
│                                                 │
│ このエージェントに割り当てるスキルを選択:       │
│                                                 │
│ ┌─────────────────────────────────────────────┐ │
│ │ ☑ コードレビュー                           │ │
│ │   コードの品質をレビューする                │ │
│ ├─────────────────────────────────────────────┤ │
│ │ ☑ テスト作成                               │ │
│ │   ユニットテストを作成する                  │ │
│ ├─────────────────────────────────────────────┤ │
│ │ ☐ ドキュメント作成                         │ │
│ │   技術ドキュメントを作成する                │ │
│ ├─────────────────────────────────────────────┤ │
│ │ ☐ リファクタリング                         │ │
│ │   コードをリファクタリングする              │ │
│ └─────────────────────────────────────────────┘ │
│                                                 │
│              [キャンセル]  [保存]               │
└─────────────────────────────────────────────────┘
```

---

## 5. ディレクトリ構造

### 5.1 エージェントコンテキストディレクトリ

```
{manager_working_dir}/
└── .aiagent/
    └── agents/{agent_id}/
        ├── .claude/                       ← Claude CLI 用
        │   ├── CLAUDE.md
        │   ├── settings.json
        │   └── skills/
        │       ├── code-review/
        │       │   └── SKILL.md
        │       └── test-creation/
        │           └── SKILL.md
        │
        └── .gemini/                       ← Gemini CLI 用（同一構造）
            ├── GEMINI.md
            ├── settings.json
            └── skills/
                ├── code-review/
                │   └── SKILL.md
                └── test-creation/
                    └── SKILL.md
```

### 5.2 生成されるSKILL.md

スキル定義の `content` フィールドがそのまま配置される。

---

## 6. MCP API

### 6.1 スキル定義 CRUD

```swift
// スキル一覧取得
func list_skill_definitions() -> [SkillDefinition]

// スキル作成
func create_skill_definition(
    name: String,
    directoryName: String,
    content: String
) -> SkillDefinition

// スキル更新
func update_skill_definition(
    skillId: SkillID,
    name: String?,
    directoryName: String?,
    content: String?
) -> SkillDefinition

// スキル削除
func delete_skill_definition(skillId: SkillID) -> Bool
```

### 6.2 エージェントスキル割り当て

```swift
// エージェントのスキル一覧取得
func get_agent_skills(agentId: AgentID) -> [SkillDefinition]

// エージェントにスキルを割り当て（全置換）
func assign_skills_to_agent(
    agentId: AgentID,
    skillIds: [SkillID]
) -> Bool
```

### 6.3 Coordinator用API

```swift
// エージェント起動時に呼び出し（既存APIの拡張）
func get_subordinate_profile(agentId: AgentID) -> SubordinateProfile

struct SubordinateProfile {
    let agentId: AgentID
    let name: String
    let systemPrompt: String
    let skills: [SkillDefinition]  // ← 追加
}
```

---

## 7. Coordinator 処理フロー

### 7.1 `_prepare_agent_context` の拡張

```python
async def _prepare_agent_context(
    self,
    agent_id: str,
    working_dir: str,
    provider: str
) -> str:
    context_dir = Path(working_dir) / ".aiagent" / "agents" / agent_id

    # プロバイダー別の設定ディレクトリ
    if provider == "claude":
        config_dir = context_dir / ".claude"
    elif provider == "gemini":
        config_dir = context_dir / ".gemini"
    else:
        return str(context_dir)

    config_dir.mkdir(parents=True, exist_ok=True)

    # 1. プロファイル取得（スキル含む）
    profile = await self.mcp_client.get_subordinate_profile(agent_id)

    # 2. システムプロンプトファイル生成
    if provider == "claude":
        self._write_claude_md(config_dir, profile.system_prompt, working_dir)
        self._write_claude_settings(config_dir, working_dir)
    elif provider == "gemini":
        self._write_gemini_md(config_dir, profile.system_prompt, working_dir)
        self._write_gemini_settings(config_dir)

    # 3. スキル配置（両プロバイダー共通）
    self._write_skills(config_dir, profile.skills)

    return str(context_dir)

def _write_skills(self, config_dir: Path, skills: list[SkillDefinition]):
    """スキルファイルを配置する（Claude/Gemini共通）"""
    skills_dir = config_dir / "skills"

    # 既存スキルをクリア（毎回再生成）
    if skills_dir.exists():
        shutil.rmtree(skills_dir)

    for skill in skills:
        skill_dir = skills_dir / skill.directory_name
        skill_dir.mkdir(parents=True, exist_ok=True)

        skill_file = skill_dir / "SKILL.md"
        skill_file.write_text(skill.content)
```

---

## 8. 制約事項

### 8.1 プロバイダー対応

| プロバイダー | スキル対応 | ディレクトリ | 備考 |
|-------------|-----------|-------------|------|
| Claude | ✅ 対応 | `.claude/skills/` | ネイティブサポート |
| Gemini | ✅ 対応 | `.gemini/skills/` | 同一構造で配置 |

### 8.2 directoryName 制約

- 英小文字、数字、ハイフンのみ許可
- 最大64文字
- 重複不可（一意制約）
- 正規表現: `^[a-z0-9][a-z0-9-]*[a-z0-9]$`

### 8.3 content 制約

- frontmatter（YAML）+ markdown 形式
- `name` フィールドは `directoryName` と一致推奨
- 最大サイズ: 64KB

---

## 9. 実装計画

### Phase 1: データモデル・永続化

- [ ] `SkillDefinition` エンティティ追加
- [ ] `AgentSkillAssignment` エンティティ追加
- [ ] SQLite マイグレーション

### Phase 2: MCP API

- [ ] スキル定義 CRUD API 実装
- [ ] エージェントスキル割り当て API 実装
- [ ] `get_subordinate_profile` レスポンス拡張

### Phase 3: UI（スキル管理）

- [ ] スキル管理画面作成
- [ ] スキル作成・編集モーダル作成

### Phase 4: UI（スキル割り当て）

- [ ] エージェント詳細画面に「スキル設定」ボタン追加
- [ ] スキル割り当てモーダル作成

### Phase 5: Coordinator

- [ ] `_write_skills` メソッド追加（Claude/Gemini共通）
- [ ] `_prepare_agent_context` 拡張（両プロバイダー対応）

### Phase 6: 統合テスト

- [ ] スキル配置の検証
- [ ] エージェント起動時のスキル読み込み確認

---

## 10. 決定事項

| 項目 | 決定 |
|-----|------|
| プリセットスキルの提供 | なし（ユーザーが自由に作成） |
| スキル管理画面の配置 | 設定メニュー配下 |

## 11. 未解決事項

| 項目 | 状態 | 対応方針 |
|-----|------|---------|
| スキルのインポート/エクスポート | スコープ外 | 将来機能として検討 |

---

## 変更履歴

| 日付 | 内容 |
|------|------|
| 2026-01-28 | 初版作成 |
| 2026-01-29 | Gemini対応追加: 同一ディレクトリ構成（`.gemini/skills/`）で両プロバイダー対応 |
