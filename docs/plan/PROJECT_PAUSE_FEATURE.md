# プロジェクト一時停止機能 設計検討

## 概要

プロジェクト全体の進行を一時的に停止し、再開時に続きから作業を再開できる機能の設計検討。

---

## テーマ1: 目的とユースケース

### 1.1 なぜ一時停止が必要か

**管理者視点での課題:**
- プロジェクトが思わぬ方向に進んでいると感じた際に、一度停止して立て直す余裕が欲しい
- 現状の「停止」はセッションがクリアされ、再開時に文脈が失われる
- 「アーカイブ」は完全終了であり、一時的な中断には適さない

**求められる状態:**
- エージェントの自動進行は止まる
- しかし管理者による介入（状況確認、タスク修正）は可能
- 再開時に続きから作業できる

### 1.2 想定されるユースケース

**典型的なフロー:**
```
一時停止 → 状況確認（チャット等） → タスク修正 → 再開
```

**具体的なシナリオ:**
1. **軌道修正**: タスクの方向性がズレていると感じ、確認・修正してから再開
2. **レビュー介入**: 成果物を確認し、必要に応じてタスクを追加・修正してから再開
3. **優先度変更**: 別の作業を優先するため一時的に停止、後日再開

**頻度:** 日常的ではないが、珍しくもない（週に数回程度？）

**緊急性:** 「すぐ止めたい」ケースが多い（問題を感じた時点で停止）

### 1.3 誰が、いつ、どのような判断で使うか

**操作権限:**
- UI（管理者）からのみ
- エージェントからの一時停止は不可

**判断基準:**
- 管理者が「このまま進めるべきではない」と判断した時
- 外部要因（会議、レビュー待ち等）で進行を止めたい時

**期間:**
- 短期（数時間〜1日）が主なユースケース
- 長期停止も想定するが、頻度は低い

### 1.4 決定事項

- [x] 目的: 管理者がプロジェクトの方向性を立て直すための「介入可能な停止状態」
- [x] 操作権限: UIからのみ（エージェント不可）
- [x] 完全フリーズではない: チャットでの状況確認、タスク修正は可能
- [x] 典型フロー: 一時停止 → 確認・修正 → 再開

### 1.5 残課題（テーマ2以降で検討）

- 「チャットでの状況確認」の具体的な実現方法
- 一時停止中に許可される操作の範囲
- 稼働中エージェントの停止タイミング

---

## テーマ2: 「一時停止」の定義

### 2.1 何が止まり、何が継続するのか

**前提: 現在のアーキテクチャ**
- チャットプロセスとタスク処理プロセスは分離されている
- `get_agent_action`がエージェントのタスク処理ライフサイクルを制御
- チャットは独立したプロセスとして機能

| 項目 | 停止 | 継続 | 実現方法 |
|------|:----:|:----:|----------|
| タスク処理用のエージェント起動 | ✓ | | `get_agent_action`が"hold"を返す |
| タスクの自動処理・割り当て | ✓ | | 同上 |
| UIからの操作 | | ✓ | 管理者権限で常に可能 |
| タスクの手動追加・修正 | | ✓ | 軌道修正のため必須 |
| 状態の閲覧 | | ✓ | 状況確認のため必須 |
| チャット対話 | | ✓ | 別プロセスのため影響なし |

### 2.2 既存の状態との違い

| 状態 | タスク処理 | チャット | データ | 再開 | 用途 |
|------|:----------:|:--------:|:------:|:----:|------|
| active | ✓ | ✓ | 読み書き | - | 通常運用 |
| **paused** | ✗ | ✓ | 読み書き | ✓ | 介入・軌道修正 |
| archived | ✗ | ✗ | 読み取りのみ | ✗ | 完全終了 |

**pausedの位置づけ:**
- activeの「タスク処理のみを停止した状態」
- archivedとは異なり、書き込み可能・再開可能
- 管理者による介入を目的とした一時的な状態

### 2.3 一時停止中に許可される操作

**読み取り操作（すべて可能）:**
- プロジェクト状態の閲覧
- タスク一覧・詳細の閲覧
- エージェント状態の閲覧
- 実行ログ・コンテキストの閲覧

**書き込み操作（可能）:**
- タスクの追加・修正・削除
- タスクの優先度・依存関係変更
- エージェントへのタスク割り当て変更

**チャット操作（可能）:**
- エージェントとの対話開始・継続
- 状況確認・指示のメッセージ送受信

**不可（一時停止の意味を成すため）:**
- タスク処理の自動進行
- 新規タスクの自動割り当て

### 2.4 実装上の整理

**1. ProjectStatusへの追加:**
```
active → paused → active（再開）
       ↘ archived
```

**2. get_agent_actionでの制御:**
- プロジェクトが`paused`の場合 → action: "hold"
- チャット目的の起動は別経路のため影響なし

**3. 既存アーキテクチャとの整合性:**
- チャットとタスク処理の分離が既に実現されている
- 追加実装は`get_agent_action`のチェック追加が中心

### 2.5 決定事項

- [x] タスク処理のみ停止、チャット・管理操作は継続
- [x] ProjectStatusに`paused`を追加（active/paused/archived）
- [x] 実装は`get_agent_action`でのプロジェクト状態チェック追加が中心
- [x] 既存のチャット/タスク分離アーキテクチャを活用

---

## テーマ3: 稼働中エージェントの扱い

### 3.1 現在のアーキテクチャの理解

**holdの意味:**
- holdは「Coordinatorが起動アクションを取らない」という意味
- 新規起動は防げるが、**既に実行中のエージェントには影響しない**

```swift
// 例: already_runningでhold
if !activeSessions.isEmpty {
    return ["action": "hold", "reason": "already_running"]
}

// 例: project_pausedでhold（新規追加）
if project.status == .paused {
    return ["action": "hold", "reason": "project_paused"]
}
```

**重要:** holdで新規起動は防げるが、実行中エージェントを止めるには別の対応が必要

### 3.2 一時停止の方針

**即時性と復帰のバランス:**
- 停止: ある程度強引に行う（即時性重視）
- 復帰: 再開時に全員に状況確認と復帰対応を指示

### 3.3 停止フロー

```
1. 一時停止ボタン押下
   ↓
2. プロジェクトステータスを paused に変更
   ↓
3. 実行中エージェントが次にMCPツールを呼ぶ
   ↓
4. プロジェクトがpausedであることを検出
   ↓
5. 「プロジェクトが一時停止されました。作業を軽く整理してexitしてください」を返す
   ↓
6. エージェントが整理（必要ならコミット等）→ logout呼び出し
   ↓
7. セッションを無効化 → クリーンな状態
```

**フォールバック:**
- エージェントがlogoutせずに放置した場合 → セッション有効期限切れで自動クリーンアップ

### 3.4 後処理時間の制限

**問題:**
- exit指示を受けたエージェントがいつまでも整理作業を続ける可能性
- 「一時停止」の効果が遅延する

**解決策: セッション有効期限の明確化**

一時停止時にセッションの有効期限を短縮し、後処理時間を限定する：

```
1. 一時停止ボタン押下
   ↓
2. プロジェクトステータスを paused に変更
   ↓
3. 該当プロジェクトのアクティブセッションの有効期限を短縮
   （例: 現在時刻 + 5分）
   ↓
4. エージェントは5分以内に整理→logout
   ↓
5. 5分経過後、未logoutセッションは強制無効化
```

**設定値（初期実装案）:**
- 後処理猶予時間: 5分
- 理由: コミット・プッシュなど基本的な整理作業には十分、長すぎない

**実装:**
```swift
// 一時停止時にセッション有効期限を短縮
func pauseProject(_ projectId: ProjectID) {
    project.status = .paused

    // アクティブセッションの有効期限を短縮
    let gracePeriod: TimeInterval = 5 * 60  // 5分
    let newExpiry = Date().addingTimeInterval(gracePeriod)

    for session in activeSessionsForProject(projectId) {
        if session.expiresAt > newExpiry {
            session.expiresAt = newExpiry
        }
    }
}
```

**効果:**
- 一時停止から最大5分で全エージェントが確実に停止
- 「即時性」の要件を満たしつつ、最低限の整理時間を確保

### 3.5 実装ポイント

**1. get_agent_action の変更:**
- プロジェクトがpausedの場合、holdを返す（reason: project_paused）
- これにより新規起動を防ぐ

**2. 各MCPツールでのチェック追加:**
- プロジェクトがpausedなら、exit指示を返す
- 対象ツール: get_next_action, get_my_task, report_completed など

**3. 返すメッセージ例:**
```json
{
  "action": "exit",
  "instruction": "プロジェクトが一時停止されました。作業を軽く整理してlogoutを呼び出してください。",
  "reason": "project_paused"
}
```

### 3.6 作業途中の状態

| 項目 | 扱い | 理由 |
|------|------|------|
| タスクステータス | in_progressのまま | 再開時に続きから |
| AgentSession | logout後に無効化 | クリーンな状態にするため |
| Context | 保持 | 再開時に状況把握 |
| Handoff | 保持 | 委任関係の維持 |

### 3.7 決定事項

- [x] 停止方針: 即時性重視、次のAPI呼び出し時にexit指示
- [x] エージェントには「整理してexit」を伝える（軽いグレースフル）
- [x] logout後にセッション無効化でクリーンな状態に
- [x] 後処理時間を制限: セッション有効期限を短縮（例: 5分）
- [x] タスクはin_progressのまま保持
- [x] 復帰時の対応はテーマ4で検討

---

## テーマ4: 状態保存と再開

### 4.1 「続きから」の定義

**エージェント視点での「続きから」:**
- 自分が担当しているタスク（in_progress）がある
- 前回の作業コンテキスト（Context）が参照できる
- 中断された状況を理解した上で、適切に作業を再開できる

**技術的には:**
- タスクステータスはin_progressのまま保持されている
- Contextに作業履歴が残っている
- 再開時に「一時停止からの復帰」であることを認識させる

### 4.2 保存される状態（テーマ3で決定済み）

| 状態 | 一時停止時 | 再開時 |
|------|-----------|--------|
| タスクステータス | in_progressのまま | そのまま利用 |
| Context | 保持 | 参照可能 |
| Handoff | 保持 | そのまま利用 |
| AgentSession | logout時に無効化 | 新規作成 |

### 4.3 再開フロー

```
1. 再開ボタン押下
   ↓
2. プロジェクトステータスを active に変更
   ↓
3. project.resumedAt = 現在時刻 を記録
   ↓
4. Coordinatorがポーリングでget_agent_actionを呼ぶ
   ↓
5. in_progressタスクがあるエージェントにstartを返す
   ↓
6. エージェント起動 → authenticate → get_my_task
   ↓
7. get_my_taskがresumedAtを見て復帰フラグを返す
   ↓
8. エージェントは状況を確認し、適切に作業を再開
```

### 4.4 復帰検知の実装（Project.resumedAt方式）

**なぜContext.progressではなくProject.resumedAtか:**
- pauseはプロジェクト単位の操作、Contextはタスク単位
- Context.progressはエージェントの作業フェーズを表すもので、外部介入とは意味が異なる
- プロジェクト単位の状態変化はプロジェクトで管理すべき

**Projectモデルへの追加:**
```swift
public struct Project {
    // 既存フィールド...
    var resumedAt: Date?  // pausedからactiveに変更された時刻
}
```

**再開時の処理:**
```swift
func resumeProject(_ projectId: ProjectID) {
    project.status = .active
    project.resumedAt = Date()  // 復帰時刻を記録
    try projectRepository.save(project)
}
```

**get_my_taskでの復帰検知:**
```swift
func getMyTask(session: AgentSession) throws -> [String: Any] {
    let project = try projectRepository.findById(session.projectId)

    var result: [String: Any] = [
        "task": taskDict,
        "context": contextDict
    ]

    // 復帰検知: セッション作成がresumedAt直後かどうか
    if let resumedAt = project?.resumedAt,
       session.createdAt > resumedAt,
       session.createdAt.timeIntervalSince(resumedAt) < 300 {  // 5分以内
        result["resumed_from_pause"] = true
        result["instruction"] = """
            一時停止から復帰しました。
            前回の作業状況を確認し、中断された作業を適切に再開してください。
            必要に応じてファイルの状態を確認し、整合性を確保してから作業を続けてください。
            """
    }

    return result
}
```

**判定ロジック:**
- `session.createdAt > resumedAt`: このセッションが再開後に作成された
- `session.createdAt - resumedAt < 300秒`: 再開から5分以内に起動（復帰直後）

### 4.5 エージェントに期待する動作

復帰フラグを受け取ったエージェントは:
1. 前回のContextを確認（どこまで進んでいたか）
2. 作業ディレクトリの状態を確認（中途半端な変更がないか）
3. 必要に応じて整理・修正してから作業継続

### 4.6 長期停止時の考慮

**問題になりうる点:**
- 外部環境の変化（リポジトリの変更、依存関係の更新など）
- コンテキストの陳腐化

**対応方針:**
- これらはエージェントの判断に委ねる
- 「一時停止からの復帰」の指示に「環境変化の可能性を考慮」を含める
- 複雑な自動検出機能は初期実装では不要

### 4.7 決定事項

- [x] 再開はUIからの手動操作（プロジェクトステータスをactiveに）
- [x] 復帰検知はProject.resumedAt方式（プロジェクト単位の状態はプロジェクトで管理）
- [x] get_my_taskでresumedAtを見て「一時停止からの復帰」フラグを返す
- [x] エージェント自身が状況確認・適切な再開を行う
- [x] 長期停止時の環境変化はエージェント判断に委ねる

---

## テーマ5: 他機能との関係

### 5.1 Internal Auditとの関係

**Audit実行中に一時停止された場合:**
- Auditもプロジェクト配下のエージェントとして動作
- 一時停止時、他のエージェントと同様にexit指示を受ける
- Audit結果は途中でも保存されている範囲で参照可能

**一時停止中にAuditがトリガーされた場合:**
- プロジェクトがpausedなのでAuditエージェントも起動されない
- 再開後に必要であれば手動でAuditを再トリガー

**方針:** 一時停止はプロジェクト全体に適用。Auditも例外ではない。

### 5.2 スケジューリング機能との関係（将来）

**初期実装では対象外:**
- 定時一時停止
- 自動再開
- カレンダー連携

**将来的な拡張として検討可能**

### 5.3 複数プロジェクト運用時の影響

**同一エージェントが複数プロジェクトに参加している場合:**
- 一時停止はプロジェクト単位
- プロジェクトAが一時停止されても、プロジェクトBは継続

**実装上の考慮:**
- get_agent_actionはproject_idを受け取る
- プロジェクトごとに独立してステータスをチェック
- 問題なし

### 5.4 決定事項

- [x] Internal Auditも一時停止の対象（例外なし）
- [x] スケジューリング機能は将来拡張として先送り
- [x] 複数プロジェクト運用: プロジェクト単位で独立して動作

---

## 実装方針

### アーキテクチャ変更

**1. ProjectStatus に paused を追加:**
```swift
public enum ProjectStatus: String, Codable, Sendable {
    case active
    case paused    // 新規追加
    case archived
}
```

**2. get_agent_action の変更:**
```swift
// プロジェクトがpausedの場合、新規起動を防ぐ
guard project.status == .active else {
    return ["action": "hold", "reason": "project_paused"]
}
```

**3. MCPツールでのpausedチェック追加:**
対象: get_next_action, get_my_task, report_completed, create_task, assign_task など
```swift
// プロジェクトがpausedの場合、exit指示を返す
if project.status == .paused {
    return [
        "action": "exit",
        "instruction": "プロジェクトが一時停止されました。作業を軽く整理してlogoutを呼び出してください。",
        "reason": "project_paused"
    ]
}
```

**4. Project に resumedAt を追加:**
```swift
public struct Project {
    // 既存フィールド...
    var resumedAt: Date?  // pausedからactiveに変更された時刻
}
```

**5. get_my_task での復帰フラグ:**
```swift
// Project.resumedAt方式: セッション作成がresumedAt直後かどうか
if let resumedAt = project?.resumedAt,
   session.createdAt > resumedAt,
   session.createdAt.timeIntervalSince(resumedAt) < 300 {  // 5分以内
    result["resumed_from_pause"] = true
    result["instruction"] = "一時停止から復帰しました。状況を確認し、適切に作業を再開してください。"
}
```

### 影響範囲

| レイヤー | ファイル | 変更内容 |
|---------|---------|---------|
| Domain | ProjectStatus.swift | paused追加 |
| Domain | Project.swift | resumedAt追加 |
| MCPServer | MCPServer.swift | pausedチェック追加、復帰検知追加 |
| UI | ProjectDetailView.swift | 一時停止/再開ボタン |
| UseCase | （必要に応じて） | 一時停止/再開ユースケース |

### 実装フェーズ

**Phase 1: 基本機能**
1. ProjectStatusにpaused追加
2. get_agent_actionでpausedチェック
3. 主要MCPツールでexit指示

**Phase 2: UI対応**
4. プロジェクト詳細画面に一時停止/再開ボタン
5. 一時停止中の視覚的表示

**Phase 3: 復帰対応**
6. get_my_taskでresumed_from_pauseフラグ
7. 復帰時の指示メッセージ

### テスト観点

- 一時停止時に新規エージェントが起動されないこと
- 実行中エージェントにexit指示が返ること
- logout後にセッションがクリーンアップされること
- 再開後にin_progressタスクが正常に継続できること
- 複数プロジェクト環境で独立して動作すること

---

## 変更履歴

| 日付 | 内容 |
|------|------|
| 2026-01-14 | 初版作成：テーマ分割 |
| 2026-01-14 | テーマ1決定：目的とユースケース |
| 2026-01-14 | テーマ2決定：一時停止の定義（タスク処理停止、チャット継続） |
| 2026-01-14 | テーマ3決定：停止方針（即時性重視、exit指示→logout→クリーンアップ） |
| 2026-01-14 | テーマ4決定：再開方針（resumed_from_pauseフラグ、エージェント判断で復帰） |
| 2026-01-14 | テーマ5決定：他機能との関係（Audit含む全体適用、プロジェクト単位独立） |
| 2026-01-14 | 実装方針策定完了 |
| 2026-01-14 | テーマ3追記：後処理時間の制限（セッション有効期限短縮） |
| 2026-01-14 | テーマ4詳細化：復帰検知はProject.resumedAt方式に決定 |
