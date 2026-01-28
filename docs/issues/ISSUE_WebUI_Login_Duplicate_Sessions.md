# Issue: Web UI ログイン時のセッション重複作成

## 概要

Web UI のログイン処理（`handleLogin`）で、既存セッションのチェックなしに毎回新しいセッションを作成している。これにより、同じエージェントが複数回ログインすると重複セッションが蓄積される。

## 発見日

2026-01-28

## 影響範囲

- `RESTServer.swift` の `handleLogin` メソッド
- Human エージェントの Web UI ログイン

## 現象

UC001 統合テスト実行後のデータベース状態：

```sql
SELECT id, agent_id, project_id, purpose, state, created_at FROM agent_sessions;

asn_1b40dc9e-416|integ-owner|prj_default|task|active|2026-01-28 00:57:46.170
asn_a4ea18b1-112|integ-owner|prj_default|task|active|2026-01-28 00:57:46.653
asn_8cef66ed-6c8|integ-owner|prj_default|task|active|2026-01-28 00:57:47.352
asn_dcc3722a-c24|integ-owner|prj_default|task|active|2026-01-28 00:57:48.503
asn_5ff4a463-424|integ-worker|integ-project|task|active|2026-01-28 00:58:03.851
asn_d3ff8c09-427|integ-owner|prj_default|task|active|2026-01-28 00:59:03.085
```

`integ-owner` のセッションが5つ重複作成されている。

## 原因コード

`Sources/RESTServer/RESTServer.swift:305-316`:

```swift
private func handleLogin(request: Request, context: AuthenticatedContext) async throws -> Response {
    // ... validation ...

    // Get default project for session (required in Phase 4)
    let defaultProjectId = ProjectID(value: AppConfig.DefaultProject.id)

    // Create session using the standard init (generates token internally)
    let expiresAt = Date().addingTimeInterval(24 * 60 * 60) // 24 hours
    let session = AgentSession(
        agentId: agentId,
        projectId: defaultProjectId,
        purpose: .task,
        expiresAt: expiresAt
    )
    try sessionRepository.save(session)  // 既存チェックなし

    // ...
}
```

## 問題点

1. **既存セッションの確認がない**: ログインのたびに新しいセッションを作成
2. **プロジェクト固定**: 常に `prj_default` に対してセッションを作成
3. **purpose 固定**: 常に `.task` でセッションを作成

## 修正案

### Option A: 既存セッションの再利用

```swift
// Check for existing active session
if let existingSession = try sessionRepository.findActiveSession(
    agentId: agentId,
    projectId: defaultProjectId
) {
    // Return existing session token
    return jsonResponse(LoginResponse(
        sessionToken: existingSession.token,
        agent: AgentDTO(from: agent),
        expiresAt: ISO8601DateFormatter().string(from: existingSession.expiresAt)
    ))
}

// Create new session only if none exists
let session = AgentSession(...)
try sessionRepository.save(session)
```

### Option B: 古いセッションの削除

```swift
// Delete existing sessions for this agent
try sessionRepository.deleteByAgentId(agentId, projectId: defaultProjectId)

// Create new session
let session = AgentSession(...)
try sessionRepository.save(session)
```

### Option C: Web UI セッションの分離

Web UI 用の軽量な認証トークン（JWT等）を使用し、`agent_sessions` テーブルは MCP/Coordinator 経由のセッションのみに使用する。

## 推奨

**Option A** を推奨。理由：
- セッション数の増加を防ぐ
- 既存のトークンを再利用できる
- ユーザー体験に影響なし

## 優先度

Medium - 機能に直接影響はないが、データベースの肥大化とクリーンアップの必要性が生じる。

## 関連

- Session Spawn Architecture 実装とは無関係
- UC001, UC010 等の統合テストで検出
