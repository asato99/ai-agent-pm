# Windows環境でのGeminiエージェントSpawn問題

## 概要

Windows環境でrunner（aiagent-runner）からGeminiエージェントをspawnする際、プロンプトの改行処理に起因する問題が発生している。

## 問題の詳細

### 発生条件
- OS: Windows
- Provider: Gemini
- 操作: Coordinatorからエージェントインスタンスをspawn

### 症状
Gemini CLIが正しくプロンプトを受け取れず、エージェントが正常に起動しない。

## 原因分析

### 問題箇所
`runner/src/aiagent_runner/coordinator.py`

### 根本原因

1. **Windowsでの`shell=True`使用**（行727-732）
   ```python
   process = subprocess.Popen(
       cmd,
       cwd=working_dir,
       stdout=log_f,
       stderr=subprocess.STDOUT,
       shell=is_windows(),  # Windowsではcmd.exe経由
       ...
   )
   ```
   - Windowsでは`shell=True`により`cmd.exe`経由でコマンドを実行
   - 複数行の引数が正しく渡されない

2. **Geminiのプロンプト渡し方法**（行700-704）
   ```python
   if provider == "gemini":
       cmd.append(prompt)  # 位置引数として直接追加
   else:
       cmd.extend(["-p", prompt])  # Claudeは-pフラグ
   ```
   - Geminiは位置引数としてプロンプトを受け取る
   - 複数行の長いプロンプトが直接コマンドライン引数に追加される

3. **プロンプト内容**（行823-862）
   ```python
   return """You are an AI Agent Instance managed by the AI Agent PM system.

   ## Authentication (CRITICAL: First Step)
   ...
   """
   ```
   - 約40行のMarkdown形式の複数行テキスト
   - 改行文字（`\n`）を多数含む

### cmd.exeでの問題

Windowsの`cmd.exe`では：
- コマンドライン引数の最大長制限がある（約8191文字）
- 改行を含む文字列の扱いが異なる
- 特殊文字（`"`, `&`, `|`, `<`, `>`, `^`等）のエスケープが必要

## 修正方針

### 推奨案: 一時ファイル + stdin経由

1. プロンプトを一時ファイルに書き出す
2. Gemini CLIにstdin経由でパイプする

```python
# 修正イメージ
if is_windows() and provider == "gemini":
    # プロンプトを一時ファイルに保存
    with tempfile.NamedTemporaryFile(
        mode='w',
        suffix='.txt',
        prefix='prompt_',
        delete=False,
        encoding='utf-8'
    ) as f:
        f.write(prompt)
        prompt_file_path = f.name

    # type コマンドでパイプ
    # Windows: type prompt.txt | gemini
    shell_cmd = f'type "{prompt_file_path}" | {" ".join(cmd)}'
    process = subprocess.Popen(
        shell_cmd,
        cwd=working_dir,
        stdout=log_f,
        stderr=subprocess.STDOUT,
        shell=True,
        env=env
    )
else:
    # 既存のロジック
    ...
```

### 代替案

1. **環境変数経由**
   - プロンプトを環境変数`AGENT_PROMPT`に設定
   - Gemini CLI側で環境変数から読み取り（要CLI側対応）

2. **ファイル引数**
   - Gemini CLIの`@file`構文を使用
   - `gemini @prompt.txt`

3. **shell=False + shutil.which**
   - `shell=False`を使用し、`shutil.which()`でコマンドパスを解決
   - より安全だが、PATH解決の追加実装が必要

## 参考資料

- [Gemini CLI Commands](https://google-gemini.github.io/gemini-cli/docs/cli/commands.html)
- [Gemini CLI Headless Mode](https://google-gemini.github.io/gemini-cli/docs/cli/headless.html)
- [Python subprocess on Windows](https://docs.python.org/3/library/subprocess.html#subprocess-replacements)

## 影響範囲

- `runner/src/aiagent_runner/coordinator.py`
  - `_spawn_instance()` メソッド
  - `AgentInstanceInfo` データクラス（一時ファイル管理用フィールド追加）
  - `_cleanup_finished()` メソッド（一時ファイルのクリーンアップ）

## ステータス

- [ ] 調査完了: 2026-01-26
- [ ] 修正実装: 未着手
- [ ] テスト: 未着手
- [ ] リリース: 未着手

## 備考

macOS/Linux環境では`shell=False`で実行されるため、この問題は発生しない。
