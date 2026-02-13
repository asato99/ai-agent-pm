# Issue: プロセス終了時のinvalidateSessionによる他プロセスのセッション破壊

## 概要

同一(agent_id, project_id)でchatプロセスとtaskプロセスが共存する場合、一方の終了時に`invalidateSession`が全セッションを削除し、他方のセッションが巻き添えで破壊される。

## 発生条件

2026-02-12 `agt_051585cc-07c` / `prj_a3d2d309-82c` にて確認。

## 問題1: 稼働中プロセスがあるのにinvalidateSessionを呼んでしまう

### 現象

Coordinatorはプロセス終了時に`invalidateSession`を呼ぶ。`invalidateSession`は(agent_id, project_id)の全セッションを削除するため、同じkeyで別プロセスがまだ稼働中の場合、そのセッションも巻き添えで破壊される。

### 原因

chatプロセスとtaskプロセスは正規の流れで共存するが、Coordinatorはプロセス終了時に無条件で`invalidateSession(agent_id, project_id)`を呼び、全セッションを削除する。他プロセスが稼働中かどうかを考慮していない。

### 該当コード

`runner/src/aiagent_runner/coordinator.py:340-357` — プロセス終了時にinvalidateSession呼び出し

### 実際のログ

```
02:58:47  invalidateSession → deleted 2 AgentSession(s)  ← Process 1のセッションも削除
02:59:35  Process 1: send_message → "Invalid session_token" → 退出
```

## 問題2: Coordinatorがchat/taskプロセスを区別できない

### 現象

Coordinatorの`_instances`は`(agent_id, project_id)`をキーとし、プロセスがchat用かtask用かを区別していない。同じ(agent_id, project_id)でchatプロセスとtaskプロセスが共存しうるが、どちらが終了した際にどのセッション（chat/task）をinvalidateすべきか判断できない。

### 該当コード

`runner/src/aiagent_runner/coordinator.py:32-45` — `AgentInstanceInfo`にpurpose(chat/task)フィールドがない
`runner/src/aiagent_runner/coordinator.py:340-357` — invalidateSession呼び出し時にchat/taskの区別なし

### 設計制約

Coordinatorは可能な限りステートレスかつシンプルであるべきという設計方針がある。現状chat/taskの判別を行っていないのもその方針に基づく。安易にCoordinatorに状態を持たせる方向ではなく、この制約を踏まえた解決策の検討が必要。

## 今回の障害の連鎖

```
Process 1 (chat起動) → start_task_from_chat → タスクをin_progressに変更
  → getAgentAction: .taskセッションなし → hasTaskWork=true → Process 2 (task) spawn（正規の流れ）
    → Process 2 終了 → invalidateSession → 全セッション削除
      → Process 1 のchatセッション破壊 → 完了報告不可 → 退出
```
