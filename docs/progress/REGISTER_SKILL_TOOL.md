# register_skill MCPツール実装 - 進捗ドキュメント

## 概要

CLIからスキルをDBに登録するMCPツール `register_skill` を実装する。

- **認可レベル**: `authenticated`
- **スコープ**: SKILL.mdテキスト + フォルダパスの両方に対応

## 実装ステップ

### Step 1: RED - テスト作成 ✅
- [x] `Tests/MCPServerTests/SkillToolsTests.swift` 新規作成
  - [x] `testRegisterSkillToolIsDefined` - ツール定義テスト
  - [x] `testRegisterSkillPermissionIsAuthenticated` - 権限テスト
  - [x] `testRegisterSkillWithContent` - SKILL.md登録テスト
  - [x] `testRegisterSkillWithFolderPath` - フォルダ登録テスト
  - [x] `testRegisterSkillValidation` - バリデーションテスト（5サブケース）

### Step 2: GREEN - 最小実装 ✅
- [x] `Sources/MCPServer/Tools/ToolDefinitions.swift` - `registerSkill` 定義追加
- [x] `Sources/MCPServer/Authorization/ToolAuthorization.swift` - `"register_skill": .authenticated` 追加
- [x] `Sources/MCPServer/MCPServer.swift` - `case "register_skill"` ディスパッチ追加
- [x] `Sources/MCPServer/Handlers/SkillTools.swift` - ハンドラー実装（新規）
- [x] `Sources/Infrastructure/Database/DatabaseSetup.swift` - `createZipArchive`/`crc32` を `public` に変更

### Step 3: REFACTOR + テスト確認 ✅
- [x] ビルド確認（MCPServer + AIAgentPMApp 両方成功）
- [x] 全5テスト GREEN確認
- [x] 既存テスト（ToolAuthorizationTests, MCPServerTests）のリグレッション確認
- [x] `testToolCount` のツール数を 38 → 47 に更新（register_skill追加 + 既存の未カウント分）

---

## 変更ファイル一覧

| ファイル | 操作 | 内容 |
|----------|------|------|
| `Tests/MCPServerTests/SkillToolsTests.swift` | **新規** | テスト5ケース |
| `Sources/MCPServer/Tools/ToolDefinitions.swift` | 編集 | `registerSkill` ツール定義 + `all()` に追加 |
| `Sources/MCPServer/Authorization/ToolAuthorization.swift` | 編集 | `"register_skill": .authenticated` 追加 |
| `Sources/MCPServer/MCPServer.swift` | 編集 | `executeToolImpl` に `case "register_skill"` 追加 |
| `Sources/MCPServer/Handlers/SkillTools.swift` | **新規** | `registerSkill()` ハンドラー + ZIPフォルダ作成ヘルパー |
| `Sources/Infrastructure/Database/DatabaseSetup.swift` | 編集 | `createZipArchive`/`crc32` を `public` に変更 |
| `Tests/MCPServerTests/MCPServerTests.swift` | 編集 | `testToolCount` のツール数更新 (38→47) |

## 進捗ログ

### 2026-02-10

**13:20 - 既存コード調査完了**
- `ToolDefinitions.swift`: `enum ToolDefinitions` に `static let` でツール定義、`all()` で一覧返却
- `ToolAuthorization.swift`: `ToolAuthorization.permissions` 辞書に権限マッピング
- `MCPServer.swift`: `executeToolImpl` の switch-case でディスパッチ
- `SkillDefinition.swift`: エンティティ + `isValidDirectoryName()` + `validate()`
- `SkillDefinitionRepository.swift`: `save()`, `findByDirectoryName()` メソッド
- `DatabaseSetup.createZipArchive(skillMdContent:)`: SKILL.md単体のZIP作成

**13:22 - Step 1 完了**: テスト5ケース作成

**13:24 - Step 2 実装開始**: ツール定義、権限、ディスパッチ、ハンドラーを追加

**13:25 - 初回ビルドエラー修正**:
- `MCPError.invalidArgument` → `MCPError.validationError` に変更（`invalidArgument` は存在しない）
- `log()` → `Self.log()` に変更（static メソッド）

**13:26 - 初回テスト: 2 pass / 3 fail**
- agents テーブルの `role` NOT NULL制約違反
- INSERT文を修正: `hierarchy_type, passkey` → `role, role_type`

**13:27 - 全5テスト GREEN 確認**

**13:28 - リグレッション確認**: `testToolCount` が 38 → 47 で失敗
- 実ツール数が47個（以前から更新漏れあり）に修正

**13:30 - 全テスト通過、ビルド成功、実装完了**
