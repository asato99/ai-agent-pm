# ランナー動的設定取得設計

## 概要

Webクライアント利用者がランナーを簡単に起動できるよう、設定ファイルを不要にし、コマンドラインから直接起動できる仕組みを設計する。

---

## 現状と課題

### 現状のフロー

```
1. macOSアプリで「Export Coordinator Config」
2. coordinator.yaml をダウンロード
3. ユーザーに共有（メール、チャット等）
4. ユーザーが適切なディレクトリに配置
5. aiagent-runner --coordinator -c /path/to/coordinator.yaml
```

### 課題

| 課題 | 詳細 |
|------|------|
| 設定ファイルの意識 | ユーザーが「設定ファイル」という概念を理解する必要がある |
| 配置場所の問題 | どこに配置すべきか、パスをどう指定するか |
| 共有の手間 | ファイルを受け渡す必要がある |
| 更新の困難さ | 設定変更時に再配布が必要 |

---

## 提案するソリューション

### 目指す姿

```bash
# Webクライアントからコピーしたコマンドをペーストして実行
pip install aiagent-runner[http] && aiagent-runner --coordinator --server http://192.168.24.32:8080 --token 7u7piKN86+...
```

### 特徴

- **設定ファイル不要**: コマンドライン引数のみで起動
- **任意のディレクトリから実行可能**: グローバルインストール
- **動的設定取得**: 起動時にサーバーから最新設定を取得
- **ワンライナー**: コピー＆ペーストで完結

---

## アーキテクチャ

### 動作フロー

```
┌─────────────────────────────────────────────────────────────────┐
│ Webクライアント                                                   │
│   「起動コマンドをコピー」ボタン                                    │
│      ↓                                                          │
│   クリップボードにコマンドをコピー                                  │
│   pip install aiagent-runner[http] && \                         │
│   aiagent-runner --coordinator --server xxx --token yyy         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ ユーザーのターミナル                                              │
│   1. pip install aiagent-runner[http]                           │
│   2. aiagent-runner --coordinator --server xxx --token yyy      │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ ランナー起動                                                      │
│   1. GET /api/coordinator/config                                 │
│      Headers: Authorization: Bearer <token>                      │
│   2. 設定を取得（agents, ai_providers, root_agent_id等）         │
│   3. 通常の Coordinator モードで動作開始                          │
└─────────────────────────────────────────────────────────────────┘
```

### コンポーネント関係図

```
┌────────────────────────────────────────────────────────────────────┐
│                    macOS App (AIAgentPM)                           │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                     REST Server                               │  │
│  │  ┌────────────────────────────────────────────────────────┐  │  │
│  │  │ GET /api/coordinator/config                             │  │  │
│  │  │   - coordinator_token で認証                            │  │  │
│  │  │   - agents, ai_providers, root_agent_id を返却         │  │  │
│  │  └────────────────────────────────────────────────────────┘  │  │
│  └──────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────┘
                              ▲
                              │ HTTP
                              │
┌────────────────────────────────────────────────────────────────────┐
│                    ランナー (aiagent-runner)                       │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ 起動オプション                                                │  │
│  │   --server http://192.168.24.32:8080                         │  │
│  │   --token 7u7piKN86+...                                      │  │
│  │                                                              │  │
│  │ 動作                                                          │  │
│  │   1. サーバーから設定取得                                      │  │
│  │   2. CoordinatorConfig を構築                                 │  │
│  │   3. 通常の Coordinator ループ開始                             │  │
│  └──────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────┘
```

---

## API設計

### GET /api/coordinator/config

Coordinator設定を動的に取得するエンドポイント。

#### リクエスト

```http
GET /api/coordinator/config HTTP/1.1
Host: 192.168.24.32:8080
Authorization: Bearer 7u7piKN86+OY1eZh0VyG8VZbbrvsAEnP38CEIaapBxM=
```

#### レスポンス

```json
{
  "polling_interval": 2,
  "max_concurrent": 3,
  "root_agent_id": "agt_fe9d4df5-e5f",
  "mcp_socket_path": "http://192.168.24.32:8081/mcp",
  "ai_providers": {
    "claude": {
      "cli_command": "claude",
      "cli_args": [
        "--dangerously-skip-permissions",
        "--max-turns",
        "50",
        "--verbose"
      ]
    },
    "gemini": {
      "cli_command": "gemini",
      "cli_args": ["-y", "-d"]
    }
  },
  "agents": {
    "agt_75bc1c38-a12": {
      "passkey": "test"
    },
    "agt_71392d21-685": {
      "passkey": "test"
    }
  },
  "log_directory": "~/Library/Logs/AIAgentPM/coordinator"
}
```

#### エラーレスポンス

| ステータス | 説明 |
|-----------|------|
| 401 Unauthorized | トークンが無効または未指定 |
| 403 Forbidden | リモートアクセスが許可されていない |

```json
{
  "error": "invalid_token",
  "message": "The provided coordinator token is invalid"
}
```

---

## ランナー側の変更

### コマンドライン引数の追加

```python
# __main__.py への追加

parser.add_argument(
    "--server",
    help="Server URL for dynamic config fetch (e.g., http://192.168.24.32:8080)"
)
parser.add_argument(
    "--token",
    help="Coordinator token for authentication"
)
```

### 設定取得ロジック

```python
# coordinator_config.py への追加

@classmethod
async def from_server(cls, server_url: str, token: str) -> "CoordinatorConfig":
    """サーバーから設定を動的に取得する。

    Args:
        server_url: サーバーのベースURL (例: http://192.168.24.32:8080)
        token: coordinator_token

    Returns:
        CoordinatorConfig インスタンス

    Raises:
        AuthenticationError: トークンが無効な場合
        ConnectionError: サーバーに接続できない場合
    """
    import aiohttp

    url = f"{server_url.rstrip('/')}/api/coordinator/config"
    headers = {"Authorization": f"Bearer {token}"}

    async with aiohttp.ClientSession() as session:
        async with session.get(url, headers=headers) as response:
            if response.status == 401:
                raise AuthenticationError("Invalid coordinator token")
            if response.status == 403:
                raise AuthenticationError("Remote access not allowed")
            response.raise_for_status()

            data = await response.json()

    # mcp_socket_path はサーバーから取得した値を使用
    # coordinator_token はコマンドラインで指定されたものを使用
    return cls(
        polling_interval=data.get("polling_interval", 2),
        max_concurrent=data.get("max_concurrent", 3),
        root_agent_id=data.get("root_agent_id"),
        mcp_socket_path=data["mcp_socket_path"],
        coordinator_token=token,
        ai_providers=data.get("ai_providers", {}),
        agents=data.get("agents", {}),
        log_directory=data.get("log_directory"),
    )
```

### 設定ロードの優先順位

```python
def load_coordinator_config(args: argparse.Namespace) -> CoordinatorConfig:
    """設定のロード優先順位:

    1. --server + --token: サーバーから動的取得（新規）
    2. -c/--config: ローカル設定ファイル
    3. デフォルト設定ファイル
    """
    if args.server and args.token:
        # 新規: サーバーから動的取得
        return asyncio.run(
            CoordinatorConfig.from_server(args.server, args.token)
        )
    elif args.config and args.config.exists():
        return CoordinatorConfig.from_yaml(args.config)
    else:
        # 既存のデフォルト設定ロジック
        ...
```

---

## サーバー側の変更

### REST API エンドポイント追加

```swift
// Sources/RESTServer/Endpoints/CoordinatorConfigEndpoint.swift

import Hummingbird

struct CoordinatorConfigEndpoint {
    let appSettingsRepository: AppSettingsRepository
    let agentRepository: AgentRepositoryProtocol
    let agentCredentialRepository: AgentCredentialRepositoryProtocol

    func register(with router: Router<some RequestContext>) {
        router.get("/api/coordinator/config", use: getConfig)
    }

    @Sendable
    func getConfig(request: Request, context: some RequestContext) async throws -> Response {
        // 1. Authorization ヘッダーからトークン取得
        guard let authHeader = request.headers[.authorization].first,
              authHeader.hasPrefix("Bearer ") else {
            throw HTTPError(.unauthorized, message: "Missing authorization header")
        }
        let token = String(authHeader.dropFirst(7))

        // 2. トークン検証
        let settings = try appSettingsRepository.get()
        guard settings.coordinatorToken == token else {
            throw HTTPError(.unauthorized, message: "Invalid coordinator token")
        }

        // 3. リモートアクセス許可チェック
        guard settings.allowRemoteAccess else {
            throw HTTPError(.forbidden, message: "Remote access not allowed")
        }

        // 4. 設定を構築して返却
        let config = try buildCoordinatorConfig(settings: settings)
        return try Response(status: .ok, body: .init(data: JSONEncoder().encode(config)))
    }

    private func buildCoordinatorConfig(settings: AppSettings) throws -> CoordinatorConfigResponse {
        // root_agent_id に基づいて管轄エージェントを取得
        let agents = try getAgentsWithCredentials(rootAgentId: settings.rootAgentId)

        return CoordinatorConfigResponse(
            pollingInterval: 2,
            maxConcurrent: 3,
            rootAgentId: settings.rootAgentId,
            mcpSocketPath: buildMCPSocketPath(),
            aiProviders: getAIProviders(),
            agents: agents,
            logDirectory: "~/Library/Logs/AIAgentPM/coordinator"
        )
    }
}
```

### レスポンス型

```swift
struct CoordinatorConfigResponse: Codable {
    let pollingInterval: Int
    let maxConcurrent: Int
    let rootAgentId: String?
    let mcpSocketPath: String
    let aiProviders: [String: AIProviderConfig]
    let agents: [String: AgentCredentialConfig]
    let logDirectory: String

    enum CodingKeys: String, CodingKey {
        case pollingInterval = "polling_interval"
        case maxConcurrent = "max_concurrent"
        case rootAgentId = "root_agent_id"
        case mcpSocketPath = "mcp_socket_path"
        case aiProviders = "ai_providers"
        case agents
        case logDirectory = "log_directory"
    }
}

struct AIProviderConfig: Codable {
    let cliCommand: String
    let cliArgs: [String]

    enum CodingKeys: String, CodingKey {
        case cliCommand = "cli_command"
        case cliArgs = "cli_args"
    }
}

struct AgentCredentialConfig: Codable {
    let passkey: String
}
```

---

## Webクライアント側の変更

### 起動コマンドコピー機能

設定画面またはダッシュボードに「起動コマンドをコピー」ボタンを追加。

#### UI設計

```
┌─────────────────────────────────────────────────────────────────┐
│ ランナー設定                                                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ 起動コマンド                                                      │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ pip install aiagent-runner[http] && \                       │ │
│ │ aiagent-runner --coordinator \                              │ │
│ │   --server http://192.168.24.32:8080 \                      │ │
│ │   --token 7u7piKN86+OY1eZh0VyG8VZbbrvsAEnP38CEIaapBxM=     │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
│                              [コマンドをコピー]                   │
│                                                                 │
│ ───────────────────────────────────────────────────────────────│
│                                                                 │
│ ⚠️ このコマンドには認証トークンが含まれています。                    │
│    信頼できる相手にのみ共有してください。                           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### React コンポーネント

```typescript
// web-ui/src/components/RunnerSetupCommand.tsx

import { useState, useEffect } from 'react';
import { useAppSettings } from '../hooks/useAppSettings';

export function RunnerSetupCommand() {
  const { settings } = useAppSettings();
  const [copied, setCopied] = useState(false);

  const serverUrl = window.location.origin;
  const token = settings?.coordinatorToken || '';

  const command = `pip install aiagent-runner[http] && \\
aiagent-runner --coordinator \\
  --server ${serverUrl} \\
  --token ${token}`;

  const handleCopy = async () => {
    await navigator.clipboard.writeText(command.replace(/\\\n/g, ''));
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <div className="runner-setup">
      <h3>起動コマンド</h3>
      <pre className="command-block">
        <code>{command}</code>
      </pre>
      <button onClick={handleCopy}>
        {copied ? 'コピーしました!' : 'コマンドをコピー'}
      </button>
      <p className="warning">
        ⚠️ このコマンドには認証トークンが含まれています。
        信頼できる相手にのみ共有してください。
      </p>
    </div>
  );
}
```

---

## セキュリティ考慮事項

### トークンの扱い

| 項目 | 対応 |
|------|------|
| トークンの露出 | コマンド履歴に残る可能性あり（ユーザー教育） |
| トークンの有効期限 | 現状なし（将来的に検討） |
| トークンの再生成 | 既存機能で対応済み |

### 通信

| 項目 | 対応 |
|------|------|
| HTTPS | 本番環境では推奨（現状はHTTP） |
| LAN内限定 | allowRemoteAccess フラグで制御 |

### 警告表示

Webクライアントでコマンドをコピーする際に以下を表示:

- トークンが含まれていることの注意
- 信頼できる相手のみに共有すること
- 履歴に残る可能性があること

---

## 互換性

### 既存機能との共存

| 起動方法 | 対応状況 |
|----------|---------|
| `--server` + `--token` | 新規（動的取得） |
| `-c coordinator.yaml` | 既存（変更なし） |
| デフォルト設定ファイル | 既存（変更なし） |

### 設定の優先順位

1. `--server` + `--token`（最優先）
2. `-c/--config` で指定したファイル
3. デフォルト設定ファイル

---

## 実装計画

### Phase 1: サーバー側 API 追加

1. `/api/coordinator/config` エンドポイント実装
2. トークン認証ロジック
3. 設定レスポンス構築

### Phase 2: ランナー側対応

1. `--server` / `--token` オプション追加
2. `CoordinatorConfig.from_server()` 実装
3. 設定ロード優先順位の変更

### Phase 3: Webクライアント UI

1. `RunnerSetupCommand` コンポーネント作成
2. 設定画面への組み込み
3. セキュリティ警告の表示

### Phase 4: ドキュメント・テスト

1. README 更新
2. 統合テスト追加
3. エラーハンドリングの確認

---

## 将来の拡張

### 検討事項

| 項目 | 説明 |
|------|------|
| トークン有効期限 | 一定期間後に失効させる |
| ワンタイムトークン | 一度使用したら無効化 |
| QRコード | モバイル端末でのスキャン対応 |
| インストールスクリプト | `curl \| bash` 形式のセットアップ |

---

## 変更履歴

| 日付 | 内容 |
|------|------|
| 2026-02-02 | 初版作成 |

## 関連ドキュメント

- [マルチデバイス アーキテクチャ設計](./MULTI_DEVICE_ARCHITECTURE.md)
- [マルチデバイス 実装プラン](./MULTI_DEVICE_IMPLEMENTATION_PLAN.md)
