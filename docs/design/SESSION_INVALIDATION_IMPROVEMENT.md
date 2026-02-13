# セッションinvalidation改善設計

参照: `docs/issues/INVALIDATE_SESSION_COLLATERAL_DAMAGE.md`

## 背景

同一(agent_id, project_id)でchatプロセスとtaskプロセスが共存する場合、一方の終了時に`invalidateSession`が全セッションを削除し、他方のセッションが巻き添えで破壊される。

### invalidateSessionの本来の役割

予期せぬプロセス終了時にサーバに残った孤児セッションをクリーンアップする救済機能。正常終了時はエージェントが`logout`ツールで自身のセッションを削除するが、LLMベースのエージェントは必ずしも`logout`を呼ぶとは限らないため、invalidateSessionによる救済が必要。

### 設計制約

- Coordinatorは可能な限りステートレスかつシンプルであるべき
- Coordinatorはプロセスがchat用かtask用かを判別できない（認証時にサーバ側で決定されるため、起動指示時点では確定しない）

## 方針

**Coordinatorは事実（残存プロセス数）を報告し、判断はサーバに委ねる。**

サーバは残存プロセス数とセッションの現在の状態を組み合わせて、どのセッションが孤児かを判定する。孤児判定には、認証時にセッションのpurposeを決定するのと同じ仕事判定ロジック（WorkDetectionService）を再利用する。

## 変更概要

### 1. Coordinator: `_instances`の複数プロセス対応

**現状**: `dict[AgentInstanceKey, AgentInstanceInfo]` — 1キーに1プロセスのみ。後から起動したプロセスが先のプロセスの参照を上書きし、参照が失われる。

**変更**: `dict[AgentInstanceKey, list[AgentInstanceInfo]]` — 1キーに複数プロセスを保持。

これにより残存プロセス数の正確な報告が可能になる。新しい概念の追加ではなく、「起動したプロセスの参照を正しく保持する」という既存責務の修正。

#### 影響範囲

| 箇所 | 現状 | 変更 |
|------|------|------|
| `_spawn_instance` | `self._instances[key] = info` | `self._instances[key].append(info)` |
| `_cleanup_finished` | `del self._instances[key]` | リストから該当プロセスを除去 |
| `_run_once` Step 4 | `key in self._instances` | `len(self._instances.get(key, [])) > 0` |
| `_stop_instance` | `self._instances.get(key)` | リストから該当プロセスを検索 |
| max_concurrent | `len(self._instances)` | 全リストの合計プロセス数 |

#### 該当コード

- `runner/src/aiagent_runner/coordinator.py:94` — `_instances`定義
- `runner/src/aiagent_runner/coordinator.py:482-574` — `_cleanup_finished`
- `runner/src/aiagent_runner/coordinator.py:1249` — `_spawn_instance`での登録

### 2. API変更: `invalidateSession` → `reportProcessExit`

**現状**: `invalidateSession(agent_id, project_id)` → 全セッション無条件削除

**変更**: `reportProcessExit(agent_id, project_id, remaining_processes)` に置換

Coordinator側の呼び出しは単純:

```python
# coordinator.py _run_once Step 3
for key, info, exit_code in finished_instances:
    remaining = len(self._instances.get(key, []))
    await self.mcp_client.report_process_exit(
        agent_id=key.agent_id,
        project_id=key.project_id,
        remaining_processes=remaining
    )
```

#### 該当コード

- `runner/src/aiagent_runner/coordinator.py:340-357` — invalidateSession呼び出し → reportProcessExit呼び出しに変更
- `runner/src/aiagent_runner/mcp_client.py:512-532` — `invalidate_session` → `report_process_exit`
- `Sources/MCPServer/Handlers/CoordinatorAPI.swift:391-433` — `invalidateSession` → `reportProcessExit`

### 3. サーバ側判定ロジック

`reportProcessExit`を受けたサーバが、残存プロセス数と現在のセッション状態に基づいて判断する。

#### ケース分析

```
remaining_processes = 0 の場合:
  → 全セッション削除（現状と同じ。安全。）

remaining_processes > 0 の場合:
  セッション数を確認:

  セッション0個: 何もしない（死んだプロセスがlogout済み、または認証前に死亡）

  セッション1個: 何もしない（死んだプロセスがlogout済みで残存プロセスのセッションのみ）

  セッション2個: 判別が必要 ← ここが本設計のポイント
```

#### セッション2個の判別ロジック

残存プロセスが1つあり、セッションが2つ（chat + task）ある場合、どちらが孤児かを判定する。

**判定方法: 認証時と同じ仕事判定ロジックの再利用**

`AuthenticateUseCaseV3`は認証時に`WorkDetectionService`を使い、現在の状態からchat/taskのどちらのセッションを作成すべきか判定する。同じロジックで「今の状態ではどちらのセッションが必要か」を判定できる。

ただし、`WorkDetectionService`の`hasChatWork`/`findTaskWork`はセッションの存在をチェックしている（セッションがあれば「仕事なし」を返す）。セッションが2つある状態では両方とも「仕事なし」を返してしまう。

そのため、判定には**セッション存在チェックを除外した**仕事判定が必要:

```swift
// reportProcessExit内の判定（概念コード）
func determineOrphanSession(agentId: AgentID, projectId: ProjectID) -> AgentPurpose? {
    let sessions = sessionRepository.findByAgentIdAndProjectId(agentId, projectId)
    guard sessions.count == 2 else { return nil }

    // セッション存在を無視して、純粋な仕事の有無を判定
    let hasInProgressTask = taskRepository.findByAssignee(agentId)
        .contains { $0.status == .inProgress && $0.projectId == projectId }
    let hasUnreadChat = !chatRepository.findUnreadMessages(projectId, agentId).isEmpty

    // 認証時と同じ優先順位: task優先
    if hasInProgressTask {
        // タスク仕事がある → 残存プロセスはtaskセッション側 → chatセッションが孤児
        return .chat
    } else if hasUnreadChat {
        // チャット仕事がある → 残存プロセスはchatセッション側 → taskセッションが孤児
        return .task
    } else {
        // どちらの仕事もない → 判別困難 → 安全側に倒して何もしない
        // （セッションはTTL(1h)で自然失効する）
        return nil
    }
}
```

**「どちらの仕事もない」ケースについて**: 残存プロセスが仕事を完了して退出直前の場合などに起こりうる。この場合は即座の判定を諦め、セッションの自然失効（最大1時間）に委ねる。残存プロセスが退出すれば`remaining_processes=0`で全削除される。

#### 判定フロー全体図

```
reportProcessExit(agent_id, project_id, remaining_processes)
│
├─ remaining_processes = 0
│   └─ 全AgentSession削除
│      ワークフローSession終了(abandoned)
│      Conversation（会話セッション）終了
│      （現invalidateSessionと同じ）
│
└─ remaining_processes > 0
    │
    ├─ セッション 0-1個 → 何もしない
    │
    └─ セッション 2個
        │ 仕事判定（セッション存在チェック除外版）
        │
        ├─ in_progressタスクあり → .chatセッション削除
        ├─ 未読チャットあり    → .taskセッション削除
        └─ どちらもなし       → 何もしない（TTL失効に委ねる）
```

## 関連セッションの終了処理

現在の`invalidateSession`はAgentSession（認証セッション）の削除に加え、以下の関連セッションも終了している:

- ワークフローSession（作業セッション）の終了（abandoned扱い）
- Conversation（エージェント間の会話セッション）の終了

`remaining_processes = 0`の場合はこれらも全て実行する（現状と同じ）。

`remaining_processes > 0`で孤児AgentSessionを1つ削除する場合は、そのセッションに紐づく関連セッションのみ終了する。詳細は実装時に検討。

## 実装ステップ

### Phase 1: Coordinator `_instances` list化

1. `AgentInstanceInfo`と`_instances`のデータ構造変更
2. `_spawn_instance`、`_cleanup_finished`、`_stop_instance`の修正
3. max_concurrent判定の修正
4. 既存テストの修正

**この時点でのinvalidateSession呼び出しは現状のまま。** list化により残存プロセス数を正確に把握可能になるが、APIはまだ変更しない。

### Phase 2: `reportProcessExit` API + 孤児セッション判定

1. セッション存在チェックを除外した仕事判定メソッド追加（WorkDetectionServiceまたは新UseCase）
2. MCPServer: `reportProcessExit`ハンドラ追加（判定ロジック込み）
   - `remaining_processes=0`: 現行`invalidateSession`と同じ動作（全削除）
   - `remaining_processes>0`: セッション数に応じた判定・孤児セッション削除
3. MCPClient (Python): `report_process_exit`メソッド追加
4. Coordinator: `invalidate_session`呼び出しを`report_process_exit`に置換
5. テスト: 各ケースの検証（remaining=0全削除、remaining>0の判定、判定不能時のフォールバック）

### Phase 3（任意）: 旧API廃止

1. `invalidateSession`を非推奨化
2. 十分な安定期間後に削除

## リスクと考慮事項

### 仕事判定の正確性

仕事判定は「現在の状態」に基づくため、タイミングによっては正しく判定できない場合がある（例: タスクが完了直後でin_progressからdoneに遷移した瞬間）。判定できない場合は安全側（何もしない）に倒し、TTL失効に委ねる。

### 孤児セッションによるfindTaskWorkブロック

仕事判定で「どちらの仕事もない」と判定された場合、孤児セッションが残りfindTaskWorkをブロックする可能性がある（最大1時間）。ただし残存プロセスが退出すれば`remaining_processes=0`で全削除されるため、実害は限定的。

### 既存テストへの影響

`_instances`のデータ構造変更により、coordinatorのテストに広範な修正が必要になる可能性がある。

### `invalidateSession`の他の呼び出し元

現在`invalidateSession`はCoordinatorからのみ呼ばれているか確認が必要。他の呼び出し元がある場合、`reportProcessExit`への移行計画に含める。
