# 命名規則ガイドライン

本ドキュメントはコードベース全体で一貫した命名規則を定義する。

---

## ファイル・型命名

| 種類 | パターン | 例 |
|------|----------|-----|
| Entity | `{Name}` | `Task`, `User` |
| UseCase | `{Action}{Entity}UseCase` | `CreateTaskUseCase` |
| Protocol | `{Name}Protocol` | `TaskRepositoryProtocol` |
| Repository | `{Entity}Repository` | `TaskRepository` |
| ViewModel | `{View}ViewModel` | `TaskListViewModel` |
| View | `{Name}View` | `TaskListView` |
| Test | `{Target}Tests` | `CreateTaskUseCaseTests` |

---

## テストメソッド命名

```swift
// パターン: test_{メソッド名}_{条件}_{期待結果}
func test_execute_withEmptyTitle_returnsValidationError()
func test_save_withValidTask_callsRepository()
func test_findById_whenNotExists_returnsNil()
```

---

## ID型命名

| 種類 | パターン | 例 |
|------|----------|-----|
| Entity ID型 | `{Entity}ID` | `TaskID`, `AgentID` |
| ID文字列プレフィックス | `{entity短縮}_` | `tsk_`, `agt_`, `prj_` |

---

## 変更履歴

| 日付 | バージョン | 変更内容 |
|------|-----------|----------|
| 2024-12-30 | 1.0.0 | ARCHITECTURE.mdから分離して初版作成 |
