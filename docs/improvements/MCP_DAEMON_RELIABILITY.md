# MCP Daemon 信頼性改善提案

## 概要

MCPデーモン管理において、ゾンビ/スレールプロセスが残りやすい問題と、それに対する改善案をまとめます。

## 現在の問題点

### 1. Fork-based Daemon アーキテクチャの問題

**場所**: `Sources/App/Core/Services/MCPDaemonManager.swift:179`

```swift
process.arguments = ["daemon"]  // No --foreground: daemon forks and runs independently
```

**問題**:
- デーモン起動時に`fork()`が発生し、子プロセスが独立して動作
- `daemonProcess` は親プロセス（すぐに終了）への参照を保持
- 子プロセス（実際のデーモン）への直接的な制御ができない
- PIDファイルに依存した間接的な管理になっている

### 2. waitForSocket タイムアウト後の処理漏れ

**場所**: `MCPDaemonManager.swift:328-346`

```swift
private func waitForSocket(timeout: TimeInterval) async throws {
    // ...
    throw DaemonError.socketNotCreated  // ← プロセスを終了しない
}
```

**問題**:
- ソケット作成のタイムアウト時、起動したプロセスを終了しない
- エラーをスローするだけで、孤立したプロセスが残る

**改善案**:
```swift
private func waitForSocket(timeout: TimeInterval) async throws {
    // ... 既存のロジック ...

    // タイムアウト時はプロセスを強制終了
    killDaemonProcess()
    throw DaemonError.socketNotCreated
}

private func killDaemonProcess() {
    // PIDファイルからPIDを取得して終了
    if let pidString = try? String(contentsOfFile: pidPath, encoding: .utf8),
       let pid = Int32(pidString.trimmingCharacters(in: .whitespacesAndNewlines)) {
        kill(pid, SIGKILL)  // SIGTERMではなくSIGKILL
    }
    try? FileManager.default.removeItem(atPath: pidPath)
    try? FileManager.default.removeItem(atPath: socketPath)
}
```

### 3. checkExistingDaemon の不完全なクリーンアップ

**場所**: `MCPDaemonManager.swift:310-317`

```swift
kill(pid, SIGTERM)
usleep(500_000)  // 500ms
try? FileManager.default.removeItem(atPath: pidPath)
status = .stopped
```

**問題**:
- SIGTERMを送信して500ms待つだけ
- プロセスが実際に終了したかどうかを確認していない
- SIGTERMで終了しない場合の処理がない

**改善案**:
```swift
kill(pid, SIGTERM)
usleep(500_000)  // 500ms

// プロセスがまだ生きている場合はSIGKILLで強制終了
if kill(pid, 0) == 0 {
    NSLog("[MCPDaemonManager] SIGTERM failed, sending SIGKILL to PID \(pid)")
    kill(pid, SIGKILL)
    usleep(200_000)  // 200ms
}

// 最終確認
if kill(pid, 0) == 0 {
    NSLog("[MCPDaemonManager] WARNING: Process \(pid) still running after SIGKILL")
}
```

### 4. stop() 関数のPIDファイル依存

**場所**: `MCPDaemonManager.swift:237-241`

**問題**:
- PIDファイルが存在しない/破損している場合、デーモンを停止できない
- 孤立したデーモンプロセスが残る

**改善案**:
```swift
public func stop() async {
    // ... 既存のPIDファイルベースの停止処理 ...

    // フォールバック: プロセス名でgrepして強制終了
    let task = Process()
    task.launchPath = "/usr/bin/pkill"
    task.arguments = ["-9", "-f", "mcp-server-pm daemon"]
    try? task.run()
    task.waitUntilExit()
}
```

### 5. テストセットアップでのクリーンアップ不足

**場所**: XCUITestのsetUp()

**問題**:
- 前回のテストから残ったゾンビプロセスの影響を受ける可能性
- スクリプトでのクリーンアップはあるが、XCUITest内でも保証すべき

**改善案**:
```swift
// UC003UITestCase.swift
override func setUp() {
    super.setUp()

    // 古いMCPプロセスをクリーンアップ
    let task = Process()
    task.launchPath = "/bin/bash"
    task.arguments = ["-c", "pkill -9 -f 'mcp-server-pm' || true"]
    try? task.run()
    task.waitUntilExit()

    // ソケット/PIDファイルを削除
    let supportDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/AIAgentPM")
    try? FileManager.default.removeItem(at: supportDir.appendingPathComponent("mcp.sock"))
    try? FileManager.default.removeItem(at: supportDir.appendingPathComponent("daemon.pid"))
}
```

## 根本的な改善案

### A. Foreground モードへの移行

現在のfork-basedデーモンから、foregroundモードに移行することで、プロセス管理を簡素化できます。

```swift
// 現在
process.arguments = ["daemon"]  // forks

// 改善案
process.arguments = ["daemon", "--foreground"]  // does not fork
daemonProcess = process  // 直接制御可能
```

**メリット**:
- `daemonProcess.terminate()` で直接終了可能
- PIDファイルへの依存が減る
- プロセスライフサイクルの明確な管理

**デメリット**:
- アプリ終了時にデーモンも終了（UITesting時は考慮が必要）

### B. プロセスグループの使用

```swift
// デーモン起動時にプロセスグループを設定
process.qualityOfService = .utility

// 終了時にプロセスグループ全体を終了
kill(-pgid, SIGKILL)  // 負のPIDでプロセスグループを指定
```

### C. LaunchAgent への移行

macOS標準のLaunchAgentを使用することで、OSレベルでのプロセス管理を委譲できます。

```xml
<!-- ~/Library/LaunchAgents/com.aiagentpm.mcp.plist -->
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.aiagentpm.mcp</string>
    <key>ProgramArguments</key>
    <array>
        <string>/path/to/mcp-server-pm</string>
        <string>daemon</string>
        <string>--foreground</string>
    </array>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
```

**メリット**:
- OSによる自動再起動
- ログ管理（`/var/log/`）
- 確実なプロセス終了

### D. Health Check の追加

```swift
public func healthCheck() async -> Bool {
    // 1. PIDファイルの存在確認
    // 2. プロセスの生存確認
    // 3. ソケットの存在確認
    // 4. ソケット接続テスト（ping/pong）

    // いずれかが失敗した場合、デーモンを再起動
}
```

## 優先度

| 改善項目 | 優先度 | 実装コスト | 効果 |
|---------|--------|-----------|------|
| waitForSocket タイムアウト処理 | 高 | 低 | プロセス残留防止 |
| checkExistingDaemon の SIGKILL | 高 | 低 | 確実なクリーンアップ |
| テストsetUpでのクリーンアップ | 高 | 低 | テスト安定性向上 |
| stop() のフォールバック | 中 | 低 | 確実な停止 |
| Foreground モードへの移行 | 中 | 中 | 管理の簡素化 |
| Health Check の追加 | 中 | 中 | 自己修復機能 |
| LaunchAgent への移行 | 低 | 高 | 抜本的な改善 |

## 関連ファイル

- `Sources/App/Core/Services/MCPDaemonManager.swift`
- `Sources/MCPServer/Daemon/DaemonCommand.swift`
- `UITests/Base/UITestBase.swift`
- `scripts/tests/test_uc003_app_integration.sh`
