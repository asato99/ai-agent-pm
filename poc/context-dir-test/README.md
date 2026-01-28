# PoC: エージェントコンテキストディレクトリからの親ディレクトリ編集

## 目的

Claude Code / Gemini CLI をサブディレクトリから起動し、親ディレクトリのファイルを編集できるか検証する。

## ディレクトリ構造

```
poc/context-dir-test/
├── README.md                          ← このファイル
├── src/
│   └── test.txt                       ← 編集対象ファイル
│
└── .aiagent/
    └── agents/
        └── test-agent/
            ├── .claude/
            │   ├── CLAUDE.md          ← Claude 用システムプロンプト
            │   └── settings.json      ← additionalDirectories 設定
            │
            └── .gemini/
                ├── GEMINI.md          ← Gemini 用システムプロンプト
                └── settings.json      ← includeDirectories 設定
```

---

## 調査結果

### Claude Code
- **追加ディレクトリ設定**: `additionalDirectories` in `settings.json`
- **システムプロンプト**: `CLAUDE.md`

### Gemini CLI
- **追加ディレクトリ設定**: `includeDirectories` in `settings.json`
- **システムプロンプト**: `GEMINI.md`
- **参考**: [PR #5354](https://github.com/google-gemini/gemini-cli/pull/5354)

---

## Claude Code PoC

### 手順

```bash
# 1. コンテキストディレクトリに移動
cd /Users/asatokazu/Documents/dev/mine/business/ai-agent-pm/poc/context-dir-test/.aiagent/agents/test-agent

# 2. Claude Code 起動
claude
```

### 検証プロンプト

```
src/test.txt を読んで、内容を "Modified by Claude" に変更してください
```

### 結果記録

| 項目 | 結果 |
|------|------|
| 親ディレクトリ読み取り | ✅ 成功 |
| 親ディレクトリ書き込み | ✅ 成功 |
| 権限プロンプト表示 | |
| 備考 | |

---

## Gemini CLI PoC

### 手順

```bash
# 1. コンテキストディレクトリに移動
cd /Users/asatokazu/Documents/dev/mine/business/ai-agent-pm/poc/context-dir-test/.aiagent/agents/test-agent

# 2. Gemini CLI 起動
gemini
```

### 検証プロンプト

```
src/test.txt を読んで、内容を "Modified by Gemini" に変更してください
```

### 結果記録

| 項目 | 結果 |
|------|------|
| 親ディレクトリ読み取り | |
| 親ディレクトリ書き込み | |
| 権限プロンプト表示 | |
| 備考 | |

---

## 確認後のクリーンアップ

```bash
# test.txt を元に戻す
echo "Hello, World!" > src/test.txt
```

---

## 参考資料

- [Gemini CLI Configuration](https://github.com/google-gemini/gemini-cli/blob/main/docs/get-started/configuration.md)
- [PR: Multi-Directory Workspace Support](https://github.com/google-gemini/gemini-cli/pull/5354)
