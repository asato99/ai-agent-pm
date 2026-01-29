# エージェントスキル機能 実装計画書

**設計書:** [docs/design/AGENT_SKILLS.md](../design/AGENT_SKILLS.md)

**開始日:** 2026-01-29
**ステータス:** 進行中

---

## 進捗サマリー

| Phase | 名称 | ステータス | 完了日 |
|-------|------|-----------|--------|
| 1 | データモデル・永続化 | ✅ 完了 | 2026-01-29 |
| 2 | UseCase | ✅ 完了 | 2026-01-29 |
| 3 | UI（スキル管理） | ✅ 完了 | 2026-01-29 |
| 4 | UI（スキル割り当て） | ✅ 完了 | 2026-01-29 |
| 5 | Coordinator | ✅ 完了 | 2026-01-29 |
| 6 | 統合テスト | ✅ 完了 | 2026-01-29 |

**凡例:** ⬜ 未着手 / 🔄 進行中 / ✅ 完了 / ⏸️ 保留

---

## Phase 1: データモデル・永続化

**目的:** スキル定義とエージェントスキル割り当てのデータモデルを追加

### 1.1 テスト作成（RED）

**ファイル:** `Tests/DomainTests/Entities/SkillDefinitionTests.swift`

- [ ] `test_skillDefinition_initialization`: 正常な初期化
- [ ] `test_skillDefinition_equatable`: 同一性比較
- [ ] `test_skillId_hashable`: SkillID のハッシュ化

**ファイル:** `Tests/InfrastructureTests/Repositories/SkillDefinitionRepositoryTests.swift`

- [ ] `test_save_and_findById`: 保存と取得
- [ ] `test_findAll_returnsAllSkills`: 全件取得
- [ ] `test_delete_removesSkill`: 削除
- [ ] `test_directoryName_uniqueConstraint`: 重複時のエラー

**テストコード例:**
```swift
func test_save_and_findById() throws {
    let skill = SkillDefinition(
        id: SkillID(value: "skill_001"),
        name: "コードレビュー",
        description: "コードの品質をレビューする",
        directoryName: "code-review",
        content: "---\nname: code-review\n---\n## 手順",
        createdAt: Date(),
        updatedAt: Date()
    )

    try repository.save(skill)
    let found = try repository.findById(skill.id)

    XCTAssertEqual(found?.name, "コードレビュー")
    XCTAssertEqual(found?.description, "コードの品質をレビューする")
    XCTAssertEqual(found?.directoryName, "code-review")
}
```

**ファイル:** `Tests/InfrastructureTests/Repositories/AgentSkillAssignmentRepositoryTests.swift`

- [ ] `test_assignSkills_savesAssignments`: スキル割り当て保存
- [ ] `test_findByAgentId_returnsAssignedSkills`: エージェントのスキル取得
- [ ] `test_assignSkills_replacesExisting`: 全置換動作

**テストコード例:**
```swift
func test_assignSkills_replacesExisting() throws {
    let agentId = AgentID(value: "agent_001")
    let skill1 = SkillID(value: "skill_001")
    let skill2 = SkillID(value: "skill_002")
    let skill3 = SkillID(value: "skill_003")

    // 初回割り当て
    try repository.assignSkills(agentId: agentId, skillIds: [skill1, skill2])

    // 2回目（全置換）
    try repository.assignSkills(agentId: agentId, skillIds: [skill3])

    let assigned = try repository.findByAgentId(agentId)
    XCTAssertEqual(assigned.count, 1)
    XCTAssertEqual(assigned.first?.id, skill3)
}
```

### 1.2 実装（GREEN）

**ファイル:** `Sources/Domain/Entities/SkillDefinition.swift`

```swift
struct SkillDefinition: Identifiable, Equatable {
    let id: SkillID
    let name: String              // 表示名
    let description: String       // 概要説明（人間向け）
    let directoryName: String     // ディレクトリ名
    let content: String           // SKILL.md の全内容
    let createdAt: Date
    let updatedAt: Date
}

struct SkillID: Hashable, Codable {
    let value: String
}
```

**ファイル:** `Sources/Domain/Entities/AgentSkillAssignment.swift`

```swift
struct AgentSkillAssignment: Equatable {
    let agentId: AgentID
    let skillId: SkillID
    let assignedAt: Date
}
```

**ファイル:** `Sources/Domain/Repositories/SkillDefinitionRepository.swift`

```swift
protocol SkillDefinitionRepository {
    func findAll() throws -> [SkillDefinition]
    func findById(_ id: SkillID) throws -> SkillDefinition?
    func save(_ skill: SkillDefinition) throws
    func delete(_ id: SkillID) throws
}
```

**ファイル:** `Sources/Domain/Repositories/AgentSkillAssignmentRepository.swift`

```swift
protocol AgentSkillAssignmentRepository {
    func findByAgentId(_ agentId: AgentID) throws -> [SkillDefinition]
    func assignSkills(agentId: AgentID, skillIds: [SkillID]) throws
}
```

### 1.3 SQLite マイグレーション

**スキーマ:**
```sql
-- skill_definitions テーブル
CREATE TABLE skill_definitions (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    directory_name TEXT NOT NULL UNIQUE,
    content TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

-- agent_skill_assignments テーブル
CREATE TABLE agent_skill_assignments (
    agent_id TEXT NOT NULL,
    skill_id TEXT NOT NULL,
    assigned_at TEXT NOT NULL,
    PRIMARY KEY (agent_id, skill_id),
    FOREIGN KEY (agent_id) REFERENCES agents(id) ON DELETE CASCADE,
    FOREIGN KEY (skill_id) REFERENCES skill_definitions(id) ON DELETE CASCADE
);

CREATE INDEX idx_agent_skill_assignments_agent_id ON agent_skill_assignments(agent_id);
```

### 1.4 Repository 実装

- [ ] `SQLiteSkillDefinitionRepository.swift` 作成
- [ ] `SQLiteAgentSkillAssignmentRepository.swift` 作成

### 1.5 リファクタリング

- [ ] 型アノテーション確認
- [ ] ドキュメントコメント追加

### 1.6 進捗ログ

| 日時 | 作業内容 | 担当 |
|------|---------|------|
| - | - | - |

---

## Phase 2: MCP API

**目的:** スキル管理・割り当ての MCP ツールを実装

### 2.1 テスト作成（RED）

**ファイル:** `Tests/MCPServerTests/SkillToolsTests.swift`

#### スキル定義 CRUD

- [ ] `test_list_skill_definitions_returnsAllSkills`: 全スキル取得
- [ ] `test_create_skill_definition_success`: スキル作成成功
- [ ] `test_create_skill_definition_invalidDirectoryName`: バリデーションエラー
- [ ] `test_update_skill_definition_success`: スキル更新成功
- [ ] `test_delete_skill_definition_success`: スキル削除成功

**テストコード例:**
```swift
func test_create_skill_definition_invalidDirectoryName() async throws {
    let result = try await mcpServer.handleToolCall(
        tool: "create_skill_definition",
        arguments: [
            "name": "Test Skill",
            "directoryName": "Invalid Name!",  // 無効な文字
            "content": "# Test"
        ],
        caller: .coordinator
    )

    XCTAssertThrowsError(result) { error in
        XCTAssertTrue(error is MCPError)
    }
}
```

#### エージェントスキル割り当て

- [ ] `test_get_agent_skills_returnsAssignedSkills`: 割り当て済みスキル取得
- [ ] `test_assign_skills_to_agent_success`: スキル割り当て成功
- [ ] `test_assign_skills_to_agent_replacesExisting`: 全置換動作

#### get_subordinate_profile 拡張

- [ ] `test_get_subordinate_profile_includesSkills`: skills フィールドが含まれること

**テストコード例:**
```swift
func test_get_subordinate_profile_includesSkills() async throws {
    // セットアップ: エージェントにスキルを割り当て
    try skillAssignmentRepository.assignSkills(
        agentId: AgentID(value: "worker-01"),
        skillIds: [SkillID(value: "skill_001")]
    )

    let result = try await mcpServer.handleToolCall(
        tool: "get_subordinate_profile",
        arguments: ["agent_id": "worker-01"],
        caller: .coordinator
    )

    let skills = result["skills"] as? [[String: Any]]
    XCTAssertEqual(skills?.count, 1)
    XCTAssertEqual(skills?.first?["directory_name"] as? String, "code-review")
}
```

### 2.2 実装（GREEN）

**ファイル:** `Sources/MCPServer/MCPServer.swift`

#### スキル定義 CRUD

- [ ] `list_skill_definitions` ツール追加
- [ ] `create_skill_definition` ツール追加
- [ ] `update_skill_definition` ツール追加
- [ ] `delete_skill_definition` ツール追加

#### エージェントスキル割り当て

- [ ] `get_agent_skills` ツール追加
- [ ] `assign_skills_to_agent` ツール追加

#### get_subordinate_profile 拡張

```swift
// 既存レスポンスに skills フィールドを追加
let assignedSkills = try skillAssignmentRepository.findByAgentId(targetId)

return [
    "id": agent.id.value,
    "name": agent.name,
    "system_prompt": agent.systemPrompt ?? "",
    "skills": assignedSkills.map { skill in
        [
            "id": skill.id.value,
            "name": skill.name,
            "description": skill.description,
            "directory_name": skill.directoryName,
            "content": skill.content
        ]
    }
]
```

### 2.3 MCPClient 拡張

**ファイル:** `runner/tests/test_mcp_client.py`

- [ ] `test_get_subordinate_profile_with_skills`: skills フィールドのパース

**テストコード例:**
```python
async def test_get_subordinate_profile_with_skills(mock_transport):
    """get_subordinate_profile が skills を正しくパースすること"""
    mock_transport.set_response({
        "success": True,
        "id": "worker-01",
        "name": "Worker 01",
        "system_prompt": "You are helpful.",
        "skills": [
            {
                "id": "skill_001",
                "name": "コードレビュー",
                "description": "コードの品質をレビューする",
                "directory_name": "code-review",
                "content": "# Code Review\n..."
            }
        ]
    })

    client = MCPClient(socket_path="/tmp/test.sock")
    profile = await client.get_subordinate_profile("worker-01")

    assert len(profile.skills) == 1
    assert profile.skills[0].name == "コードレビュー"
    assert profile.skills[0].description == "コードの品質をレビューする"
    assert profile.skills[0].directory_name == "code-review"
```

**ファイル:** `runner/src/aiagent_runner/mcp_client.py`

- [ ] `SkillDefinition` データクラス追加
- [ ] `SubordinateProfile.skills` フィールド追加

```python
@dataclass
class SkillDefinition:
    id: str
    name: str
    description: str
    directory_name: str
    content: str

@dataclass
class SubordinateProfile:
    agent_id: str
    name: str
    system_prompt: str
    skills: list[SkillDefinition] = field(default_factory=list)
```

### 2.4 リファクタリング

- [ ] directoryName バリデーション関数の共通化
- [ ] エラーメッセージの統一

### 2.5 進捗ログ

| 日時 | 作業内容 | 担当 |
|------|---------|------|
| - | - | - |

---

## Phase 3: UI（スキル管理）

**目的:** スキルのマスタ管理画面を作成

### 3.1 テスト作成（RED）

**ファイル:** `AIAgentPMUITests/SkillManagementTests.swift`

- [ ] `test_skillManagementScreen_showsSkillList`: スキル一覧が表示されること
- [ ] `test_createSkill_success`: スキル作成フロー
- [ ] `test_editSkill_updatesContent`: スキル編集フロー
- [ ] `test_deleteSkill_removesFromList`: スキル削除フロー
- [ ] `test_directoryName_validation`: バリデーションエラー表示

**テストコード例:**
```swift
func test_createSkill_success() throws {
    // 設定画面を開く
    app.buttons["Settings"].click()
    app.buttons["Skill Management"].click()

    // 追加ボタンをクリック
    app.buttons["Add Skill"].click()

    // フォーム入力
    app.textFields["Skill Name"].typeText("Code Review")
    app.textFields["Description"].typeText("Review code quality")
    app.textFields["Directory Name"].typeText("code-review")
    app.textViews["Content"].typeText("# Code Review Steps")

    // 保存
    app.buttons["Save"].click()

    // 一覧に表示されることを確認
    XCTAssertTrue(app.staticTexts["Code Review"].exists)
    XCTAssertTrue(app.staticTexts["Review code quality"].exists)
}
```

### 3.2 実装（GREEN）

**ファイル:** `Sources/Views/Settings/SettingsView.swift`

- [ ] 「スキル管理」メニュー項目追加

**ファイル:** `Sources/Views/Settings/SkillManagementView.swift`

- [ ] スキル一覧表示（List）
- [ ] 追加ボタン（+）
- [ ] 編集・削除コンテキストメニュー

**ファイル:** `Sources/Views/Settings/SkillEditorView.swift`

- [ ] スキル名入力フィールド
- [ ] 概要説明入力フィールド（description）
- [ ] ディレクトリ名入力フィールド（バリデーション付き）
- [ ] 内容エディタ（TextEditor、等幅フォント）

**ファイル:** `Sources/ViewModels/SkillManagementViewModel.swift`

- [ ] スキル一覧取得
- [ ] スキル作成・更新・削除

### 3.3 リファクタリング

- [ ] アクセシビリティ対応
- [ ] キーボードナビゲーション

### 3.4 進捗ログ

| 日時 | 作業内容 | 担当 |
|------|---------|------|
| 2026-01-29 | DependencyContainerにスキルリポジトリ・ユースケース追加 | Claude |
| 2026-01-29 | SkillManagementView.swift作成（一覧・作成・編集・削除） | Claude |
| 2026-01-29 | SettingsViewにSkillsタブ追加 | Claude |
| 2026-01-29 | Feature15_SkillManagementTests.swift作成 | Claude |
| 2026-01-29 | ビルド確認・xcodegen再生成 | Claude |

---

## Phase 4: UI（スキル割り当て）

**目的:** エージェントへのスキル割り当てUIを作成

### 4.1 テスト作成（RED）

**ファイル:** `AIAgentPMUITests/AgentSkillAssignmentTests.swift`

- [ ] `test_agentDetail_showsSkillsButton`: スキル設定ボタンが表示されること
- [ ] `test_skillAssignment_showsAvailableSkills`: 利用可能スキル一覧が表示されること
- [ ] `test_skillAssignment_saveUpdatesAgent`: 保存で割り当てが反映されること

**テストコード例:**
```swift
func test_skillAssignment_saveUpdatesAgent() throws {
    // エージェント詳細画面を開く
    app.buttons["Worker-01"].click()

    // スキル設定ボタンをクリック
    app.buttons["Skill Settings"].click()

    // スキルを選択
    app.checkBoxes["Code Review"].click()

    // 保存
    app.buttons["Save"].click()

    // 詳細画面にスキルが表示されることを確認
    XCTAssertTrue(app.staticTexts["Code Review"].exists)
}
```

### 4.2 実装（GREEN）

**ファイル:** `Sources/Views/Agent/AgentDetailView.swift`

- [ ] 「スキル設定」ボタン追加
- [ ] 割り当て済みスキルの表示

**ファイル:** `Sources/Views/Agent/AgentSkillAssignmentView.swift`

- [ ] 利用可能スキル一覧（チェックボックス付き）
- [ ] 割り当て済みスキルは選択状態で表示
- [ ] 保存ボタンで全置換

**ファイル:** `Sources/ViewModels/AgentDetailViewModel.swift`

- [ ] `assignedSkills` プロパティ追加
- [ ] `saveSkillAssignments` メソッド追加

### 4.3 リファクタリング

- [ ] アクセシビリティ対応

### 4.4 進捗ログ

| 日時 | 作業内容 | 担当 |
|------|---------|------|
| 2026-01-29 | AgentSkillAssignmentView.swift作成（スキル割り当てシート） | Claude |
| 2026-01-29 | AgentSkillsSection作成（エージェント詳細のスキルセクション） | Claude |
| 2026-01-29 | SkillBadge・FlowLayout作成（スキルバッジ表示） | Claude |
| 2026-01-29 | AgentDetailViewにスキルセクション統合 | Claude |
| 2026-01-29 | Feature15_SkillManagementTestsにPhase 4テスト追加 | Claude |
| 2026-01-29 | ビルド確認 | Claude |

---

## Phase 5: Coordinator

**目的:** エージェント起動時にスキルファイルを配置

### 5.1 テスト作成（RED）

**ファイル:** `runner/tests/test_coordinator.py`

- [ ] `test_write_skills_creates_directories`: スキルディレクトリが作成されること
- [ ] `test_write_skills_creates_skill_md`: SKILL.md が作成されること
- [ ] `test_write_skills_clears_existing`: 既存スキルがクリアされること
- [ ] `test_write_skills_empty_list`: スキルが空の場合も正常動作
- [ ] `test_prepare_agent_context_includes_skills`: スキルが配置されること

**テストコード例:**
```python
def test_write_skills_creates_directories(tmp_path, coordinator):
    """スキルディレクトリとSKILL.mdが作成されること"""
    config_dir = tmp_path / ".claude"
    config_dir.mkdir()

    skills = [
        SkillDefinition(
            id="skill_001",
            name="コードレビュー",
            description="コードの品質をレビューする",
            directory_name="code-review",
            content="---\nname: code-review\n---\n## Steps"
        )
    ]

    coordinator._write_skills(config_dir, skills)

    skill_file = config_dir / "skills" / "code-review" / "SKILL.md"
    assert skill_file.exists()
    assert "## Steps" in skill_file.read_text()

def test_write_skills_clears_existing(tmp_path, coordinator):
    """既存スキルがクリアされ再生成されること"""
    config_dir = tmp_path / ".claude"
    skills_dir = config_dir / "skills" / "old-skill"
    skills_dir.mkdir(parents=True)
    (skills_dir / "SKILL.md").write_text("old content")

    skills = [
        SkillDefinition(
            id="skill_001",
            name="新スキル",
            description="新しいスキル",
            directory_name="new-skill",
            content="new content"
        )
    ]

    coordinator._write_skills(config_dir, skills)

    # 古いスキルは削除
    assert not (config_dir / "skills" / "old-skill").exists()
    # 新しいスキルが存在
    assert (config_dir / "skills" / "new-skill" / "SKILL.md").exists()
```

### 5.2 実装（GREEN）

**ファイル:** `runner/src/aiagent_runner/coordinator.py`

```python
def _write_skills(self, config_dir: Path, skills: list[SkillDefinition]):
    """スキルファイルを配置する（Claude/Gemini共通）"""
    skills_dir = config_dir / "skills"

    # 既存スキルをクリア（毎回再生成）
    if skills_dir.exists():
        shutil.rmtree(skills_dir)

    if not skills:
        return

    for skill in skills:
        skill_dir = skills_dir / skill.directory_name
        skill_dir.mkdir(parents=True, exist_ok=True)

        skill_file = skill_dir / "SKILL.md"
        skill_file.write_text(skill.content)

        logger.debug(f"Wrote skill: {skill_file}")
```

### 5.3 `_prepare_agent_context` 拡張

```python
# 既存コード拡張
profile = await self.mcp_client.get_subordinate_profile(agent_id)
system_prompt = profile.system_prompt
skills = profile.skills  # 追加

# ... 設定ファイル書き込み ...

# スキル配置（Claude/Gemini共通）
self._write_skills(config_dir, skills)
```

### 5.4 リファクタリング

- [ ] ログ出力の統一
- [ ] エラーハンドリング

### 5.5 進捗ログ

| 日時 | 作業内容 | 担当 |
|------|---------|------|
| 2026-01-29 | MCPServer.swift: get_subordinate_profileにスキル情報追加 | Claude |
| 2026-01-29 | mcp_client.py: SkillDefinitionデータクラス追加、skillsパース実装 | Claude |
| 2026-01-29 | coordinator.py: _write_skillsメソッド追加、_prepare_agent_context統合 | Claude |
| 2026-01-29 | Pythonテスト全パス確認 | Claude |

---

## Phase 6: 統合テスト

**目的:** スキル機能の E2E 動作確認

### 6.1 テストシナリオ

#### 6.1.1 スキル管理 E2E

- [ ] スキルを作成 → 一覧に表示される
- [ ] スキルを編集 → 変更が反映される
- [ ] スキルを削除 → 一覧から消える

#### 6.1.2 スキル割り当て E2E

- [ ] エージェントにスキルを割り当て → 詳細画面に表示される
- [ ] 割り当てを解除 → 詳細画面から消える

#### 6.1.3 起動時配置 E2E

- [ ] エージェント起動 → `.claude/skills/` にスキルが配置される
- [ ] エージェント起動 → `.gemini/skills/` にスキルが配置される
- [ ] スキル変更 → 再起動で新しいスキルが反映される

#### 6.1.4 スキル利用確認

- [ ] Claude CLI でスキルが認識される（`/skill_name` で呼び出し可能）
- [ ] Gemini CLI でスキルが認識される

### 6.2 進捗ログ

| 日時 | 作業内容 | 担当 |
|------|---------|------|
| 2026-01-29 | test_coordinator.py: TestCoordinatorWriteSkillsクラス追加（6テスト） | Claude |
| 2026-01-29 | test_mcp_client.py: TestSubordinateProfileWithSkills・TestSkillDefinitionDataclass追加（5テスト） | Claude |
| 2026-01-29 | 全テストパス確認（40テスト） | Claude |

---

## 依存関係

```
Phase 1（データモデル）
    ↓
Phase 2（MCP API）
    ↓
    ├── Phase 3（UI: スキル管理）
    │       ↓
    │   Phase 4（UI: スキル割り当て）
    │
    └── Phase 5（Coordinator）
            ↓
        Phase 6（統合テスト）
```

**前提条件:**
- AGENT_CONTEXT_DIRECTORY 機能が完了していること ✅

---

## リスクと対策

| リスク | 影響 | 対策 |
|-------|------|------|
| スキル content が大きすぎる | メモリ・DB負荷 | 64KB 制限を設ける |
| directoryName の重複 | スキル上書き | UNIQUE 制約で防止 |
| 削除時に割り当て済み | 参照エラー | CASCADE DELETE または警告表示 |
| Claude/Gemini でスキル形式が異なる | 互換性問題 | 同一形式で配置、動作確認 |

---

## 完了条件

- [x] Phase 1〜5 の全テストが GREEN
- [x] Phase 6 の統合テスト成功（Python: 40テストパス）
- [ ] Claude CLI でスキルが動作すること（手動確認）
- [ ] Gemini CLI でスキルが動作すること（手動確認）
- [ ] 設計書のレビュー完了
- [ ] CHANGELOG への追記

---

## 変更履歴

| 日付 | 内容 |
|------|------|
| 2026-01-29 | 初版作成（設計書から分離、テストファースト形式） |
| 2026-01-29 | Phase 1〜6 完了（自動テスト全パス） |
