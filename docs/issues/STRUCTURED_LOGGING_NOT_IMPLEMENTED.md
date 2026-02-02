# Issue: 構造化ログが実装されていない

## 概要

MCPサーバーのログシステムで、構造化ログ（JSON形式）が設計されているが実際には使用されておらず、全てのログ出力がテキスト形式になっている。これにより、ツール呼び出しの引数などの詳細情報（`details`）がログに記録されない。

## 発見日

2026-01-30

## 現状

### 設計意図

- `LogEntry.toJSON()`: 構造化された完全な情報（`details` 含む）
- `LogEntry.toText()`: 人間が読みやすいデバッグ用（`details` なし）

### 実際の実装

- `RotatingFileLogOutput`: デフォルトが `.text`（41行目）
- `MCPServer.swift:148`: `format` パラメータ未指定でファイル出力
- `StderrLogOutput`: `.text` 固定

**結果**: 構造化ログ（`.json`）はどこにも出力されていない

## 影響

1. ツール呼び出しの引数がログに記録されない
2. セッション情報（purpose など）がログに含まれない
3. デバッグ時に詳細情報を追跡できない

## 関連ファイル

- `Sources/Infrastructure/Logging/LogEntry.swift` - `toText()` が `details` を出力しない
- `Sources/Infrastructure/Logging/RotatingFileLogOutput.swift` - デフォルト `.text`
- `Sources/Infrastructure/Logging/LogOutput.swift` - `StderrLogOutput`
- `Sources/MCPServer/MCPServer.swift:148-151` - ログ出力設定

## 提案される修正

### 短期対応（暫定）

`toText()` に `details` の出力を追加

### 長期対応

1. ファイル出力を `.json` に変更
2. コンソール出力は `.text` のまま維持
3. 環境変数 `MCP_LOG_FORMAT` による切り替えを有効化

## ステータス

保留（暫定対応として `toText()` に `details` 出力を追加）
