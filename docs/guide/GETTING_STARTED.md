# AI Agent PM はじめ方ガイド

サーバーの起動からエージェントの実行までの一連の流れを説明します。

---

## 全体像

```
┌──────────────────────────────────────────────────────────────────┐
│  Step 1: サーバー起動                                              │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐          │
│  │ REST Server  │   │  MCP Server  │   │   Web UI     │          │
│  │ (Swift)      │   │  (Swift)     │   │ (React/Vite) │          │
│  │ port 8080    │   │ Unix Socket  │   │ port 5173    │          │
│  └──────────────┘   └──────────────┘   └──────────────┘          │
├──────────────────────────────────────────────────────────────────┤
│  Step 2: 初期設定（Web UI）                                        │
│  ・ログイン → Settings → Coordinator トークン生成                   │
├──────────────────────────────────────────────────────────────────┤
│  Step 3: Coordinator 起動（Python）                                │
│  ・--server --token でサーバーから設定を自動取得                      │
│  ・YAML 不要、エージェント情報はサーバーから動的に取得                  │
├──────────────────────────────────────────────────────────────────┤
│  Step 4: タスク実行                                                │
│  ・Web UI でタスク作成 → エージェント割当 → 自動実行                   │
└──────────────────────────────────────────────────────────────────┘
```

---

## Step 1: サーバーを起動する

### macOS（Xcode でビルド済みの場合）

macOS GUI アプリを起動すれば REST Server / MCP Server は自動で立ち上がります。
Web UI だけ別途起動が必要です:

```bash
cd web-ui
npm install    # 初回のみ
npm run dev    # → http://localhost:5173
```

### macOS / Linux / WSL2（CLI ビルド）

```bash
# Swift サーバーのビルド（初回のみ）
swift build -c release --product rest-server-pm
swift build -c release --product mcp-server-pm

# Web UI 依存パッケージ（初回のみ）
cd web-ui && npm install && cd ..

# 一括起動スクリプト（REST Server + Web UI）
./scripts/cross-platform/start-dev.sh
```

起動オプション:

```bash
./scripts/cross-platform/start-dev.sh --port 8085          # ポート変更
./scripts/cross-platform/start-dev.sh --db /tmp/test.db    # DB パス指定
./scripts/cross-platform/start-dev.sh --no-webui           # Web UI なし
```

### Windows

Windows ネイティブでは Swift バイナリが動作しないため、WSL2 経由で起動します。

```powershell
# 初回セットアップ
wsl ./scripts/cross-platform/setup-wsl2.sh

# 起動
wsl ./scripts/cross-platform/start-dev.sh
# または
.\scripts\cross-platform\start-dev.ps1
```

詳細: [CROSS_PLATFORM_SETUP.md](CROSS_PLATFORM_SETUP.md)

### 起動確認

```bash
# REST Server のヘルスチェック
curl http://localhost:8080/health

# Web UI にブラウザでアクセス
open http://localhost:5173    # macOS
xdg-open http://localhost:5173  # Linux
```

### プラットフォーム別のパス

| 項目 | macOS | Linux / WSL2 |
|------|-------|-------------|
| データベース | `~/Library/Application Support/AIAgentPM/pm.db` | `~/.local/share/AIAgentPM/pm.db` |
| MCP ソケット | `~/Library/Application Support/AIAgentPM/mcp.sock` | `~/.local/share/aiagent-runner/mcp.sock` |
| ログ | `~/Library/Application Support/AIAgentPM/` | `~/.local/share/AIAgentPM/` |

> 環境変数 `AIAGENTPM_DB_PATH` でデータベースパスを上書きできます。

---

## Step 2: Web UI で初期設定を行う

### 2-1. ログイン

ブラウザで `http://localhost:5173` を開き、管理者エージェントでログインします。

### 2-2. Settings ページを開く

ヘッダー右上の **歯車アイコン** をクリックして Settings ページに移動します。

### 2-3. Coordinator トークンを生成

1. **Coordinator** タブを開く
2. **Generate Token** ボタンをクリック
3. マスクされたトークン（例: `****abcd`）が表示されることを確認

> トークンはサーバー側に保存されます。Web UI では下4桁のみ表示されます。
> トークンの全文は API レスポンスでのみ確認できます。

### 2-4. (オプション) その他の設定

| タブ | 設定項目 | 説明 |
|------|----------|------|
| **General** | Agent Base Prompt | 全エージェント共通のシステムプロンプト |
| **General** | Pending Purpose TTL | エージェント起動目的の有効期間（秒） |
| **Coordinator** | Remote Access | 他デバイスからの接続を許可（LAN 内） |
| **Runner Setup** | 起動コマンド | コピー用のコマンドが表示される |

---

## Step 3: Coordinator を起動する

### 3-1. Runner パッケージをインストール

```bash
cd runner
pip install -e ".[http]"    # HTTP 経由で設定取得するため [http] extra が必要
```

### 3-2. 設定取得の動作確認（curl）

```bash
curl -s -H "Authorization: Bearer <YOUR_TOKEN>" \
  http://localhost:8080/api/coordinator/config | jq .
```

期待されるレスポンス:

```json
{
  "server_url": "http://localhost:8080",
  "polling_interval": 10,
  "max_concurrent": 3,
  "agents": {
    "agent-id-1": { "passkey": "..." },
    "agent-id-2": { "passkey": "..." }
  },
  "ai_providers": {
    "claude": { "cli_command": "claude", "cli_args": ["--dangerously-skip-permissions", ...] },
    "gemini": { "cli_command": "gemini", "cli_args": ["-y", "-d"] }
  },
  "agent_base_prompt": "..."
}
```

認証エラーの確認:

```bash
curl -s -w "\nHTTP %{http_code}\n" \
  -H "Authorization: Bearer wrong-token" \
  http://localhost:8080/api/coordinator/config
# → HTTP 401
```

### 3-3. Coordinator を起動

```bash
aiagent-runner --coordinator \
  --server http://localhost:8080 \
  --token <YOUR_TOKEN>
```

成功時のログ:

```
Fetching config from server: http://localhost:8080
Config loaded from server (N agents)
Running in Coordinator mode (Phase 4)
Configured agents: ['agent-id-1', 'agent-id-2']
Polling interval: 10s
Max concurrent: 3
```

### 3-4. (オプション) マルチデバイス運用

別のマシンから Coordinator を起動する場合:

1. Web UI の Settings → Coordinator → **Remote Access を ON** にする
2. サーバーを再起動する（設定反映のため）
3. 別マシンから起動:

```bash
aiagent-runner --coordinator \
  --server http://192.168.1.100:8080 \
  --token <YOUR_TOKEN> \
  --root-agent-id human-frontend-lead    # オプション: 管理対象を絞る
```

### 3-5. (代替) YAML で起動

サーバーに接続できない環境では YAML 設定ファイルで起動できます:

```bash
aiagent-runner --coordinator -c coordinator_config.yaml
```

```yaml
# coordinator_config.yaml
server_url: http://192.168.1.100:8080
polling_interval: 10
max_concurrent: 3

agents:
  agt_developer:
    passkey: secret123
  agt_reviewer:
    passkey: secret456

ai_providers:
  claude:
    cli_command: claude
    cli_args: ["--dangerously-skip-permissions"]
```

---

## Step 4: タスクを実行する

1. Web UI でプロジェクトを開く
2. タスクを作成し、エージェントをアサイン
3. タスクのステータスを **in_progress** に変更
4. Coordinator が自動検知してCLIツール（claude / gemini）を起動
5. 実行結果は Web UI のタスク詳細画面で確認

---

## クイックリファレンス

### 起動コマンド一覧

```bash
# サーバー一括起動
./scripts/cross-platform/start-dev.sh

# Coordinator 起動（動的設定）
aiagent-runner --coordinator --server http://localhost:8080 --token <TOKEN>

# Coordinator 起動（YAML）
aiagent-runner --coordinator -c config.yaml

# Legacy Runner 起動（単一エージェント）
aiagent-runner --agent-id agt_xxx --passkey secret --project-id proj_xxx
```

### Coordinator CLI オプション

| オプション | 説明 |
|-----------|------|
| `--coordinator` | Coordinator モードで起動 |
| `--server <URL>` | サーバー URL（動的設定取得） |
| `--token <TOKEN>` | Coordinator トークン |
| `--root-agent-id <ID>` | 管理対象エージェントの絞り込み |
| `-c, --config <PATH>` | YAML 設定ファイル |
| `-v, --verbose` | 詳細ログ出力 |
| `--polling-interval <SEC>` | ポーリング間隔（秒） |
| `--log-directory <PATH>` | ログ出力先 |

### REST API エンドポイント

| メソッド | パス | 認証 | 説明 |
|---------|------|------|------|
| `GET` | `/api/settings` | Session | 設定取得 |
| `PATCH` | `/api/settings` | Session | 設定更新 |
| `POST` | `/api/settings/regenerate-token` | Session | トークン再生成 |
| `DELETE` | `/api/settings/coordinator-token` | Session | トークン削除 |
| `GET` | `/api/coordinator/config` | Bearer Token | Coordinator 用設定取得 |

---

## トラブルシューティング

### サーバーが起動しない

```bash
# ポートが使用中でないか確認
lsof -i :8080       # macOS / Linux
ss -tlnp | grep 8080  # Linux

# 別のポートで起動
./scripts/cross-platform/start-dev.sh --port 8085
```

### Coordinator がサーバーに接続できない

```bash
# サーバーが起動しているか確認
curl http://localhost:8080/health

# Remote Access が必要か確認（別マシンから接続する場合）
# → Settings → Coordinator → Remote Access を ON にしてサーバーを再起動
```

### トークンが無効

```bash
# トークンの状態を確認（Web UI の Settings → Coordinator で確認可能）
# トークンを再生成する場合は Regenerate Token をクリック
# ※ 再生成すると既存の Coordinator は再起動が必要
```

### CLI ツールが見つからない

```bash
# claude / gemini がインストールされているか
which claude
which gemini

# PATH が通っているか確認（Coordinator はシェル環境を引き継ぐ）
echo $PATH
```
