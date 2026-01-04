# Feature09/Feature10 UIテスト修正計画

## 概要
Feature09（ワークフローテンプレート）とFeature10（内部監査）のUIテストで発生している14件の失敗を修正する。

## 現状
- **Feature09:** 11テスト実行、11失敗
- **Feature10:** 11テスト実行、3失敗、8パス
- **合計:** 22テスト、14失敗、0スキップ

---

## 失敗テスト一覧

### Feature09（11件）
| # | テスト名 | 失敗理由 | 対応方針 |
|---|---------|---------|---------|
| 1 | testTemplatesSectionExistsWithProject | NewTemplateButton未発見 | 調査中 |
| 2 | testNewTemplateFormOpens | NewTemplateButton未実装 | 調査中 |
| 3 | testTemplateNameRequired | TemplateFormSaveButton未実装 | 調査中 |
| 4 | testAddTaskToTemplate | TemplateNameField未実装 | 調査中 |
| 5 | testAddVariableToTemplate | TemplateNameField未実装 | 調査中 |
| 6 | testSaveTemplate | TemplateNameField未実装 | 調査中 |
| 7 | testInstantiateFromTemplateDetail | TemplateRow未発見 | 調査中 |
| 8 | testVariableInputFieldsDisplayed | インスタンス化シート開けない | 調査中 |
| 9 | testInstantiateCreatesTasks | インスタンス化シート開けない | 調査中 |
| 10 | testEditTemplate | TemplateRow未発見 | 調査中 |
| 11 | testArchiveTemplate | TemplateRow未発見 | 調査中 |

### Feature10（3件）
| # | テスト名 | 失敗理由 | 対応方針 |
|---|---------|---------|---------|
| 1 | testToggleAuditRuleEnabled | テストデータにAudit Ruleがない | 調査中 |
| 2 | testStatusChangedTriggerConfiguration | TriggerStatusPicker未実装 | 調査中 |
| 3 | testDeadlineExceededTriggerConfiguration | TriggerGraceMinutesField未実装 | 調査中 |

---

## 進捗

### Phase 1: 原因調査
- [ ] Feature09の根本原因を特定
- [ ] Feature10の根本原因を特定

### Phase 2: 修正実装
- [ ] Feature09の修正
- [ ] Feature10の修正

### Phase 3: 検証
- [ ] 全テスト実行・確認

---

## 作業ログ

### 2026-01-04 16:15 - 調査開始

**Feature09の根本原因:**
- SwiftUI ListのセクションヘッダーボタンはXCUITestで見つけにくい
- CommonUITests.swiftのコメント：「NewProjectButtonはツールバーボタンのためXCUITestに公開されない」
- 解決策：キーボードショートカット（⇧⌘T）またはツールバーメニュー経由でテスト

**対応方針:**
1. `openNewTemplateForm()`ヘルパーをキーボードショートカット使用に変更
2. テンプレートフォームUI（シート）が未実装の場合はUIを実装
3. テストデータにテンプレートをシード

### 2026-01-04 16:20 - Feature09修正開始
