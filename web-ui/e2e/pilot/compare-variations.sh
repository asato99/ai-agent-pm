#!/bin/bash
#
# Variation Comparison Runner
#
# 複数のバリエーションを実行して比較レポートを生成
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# デフォルト値
SCENARIO="hello-world"
VARIATIONS=""

# 使用方法
usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  -s, --scenario NAME         シナリオ名 (default: hello-world)
  -v, --variations V1,V2,...  比較するバリエーション（カンマ区切り）
  --all                       全バリエーションを比較
  -h, --help                  ヘルプ表示

Examples:
  $0 --all                                    # 全バリエーションを比較
  $0 -v baseline,explicit-flow                # 特定のバリエーションを比較
  $0 -s hello-world -v baseline,explicit-flow # シナリオとバリエーションを指定
EOF
  exit 0
}

# 引数解析
while [[ $# -gt 0 ]]; do
  case $1 in
    -s|--scenario)
      SCENARIO="$2"
      shift 2
      ;;
    -v|--variations)
      VARIATIONS="$2"
      shift 2
      ;;
    --all)
      # 全バリエーションを取得
      VARIATIONS=$(ls "$SCRIPT_DIR/scenarios/$SCENARIO/variations/"*.yaml 2>/dev/null | xargs -n1 basename | sed 's/.yaml$//' | tr '\n' ',' | sed 's/,$//')
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown option: $1"
      usage
      ;;
  esac
done

if [ -z "$VARIATIONS" ]; then
  echo "Error: No variations specified. Use -v or --all"
  usage
fi

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "=== Variation Comparison Runner ==="
log "Scenario: $SCENARIO"
log "Variations: $VARIATIONS"

# バリエーションを配列に変換
IFS=',' read -ra VARIATION_ARRAY <<< "$VARIATIONS"

FAILED_VARIATIONS=()
PASSED_VARIATIONS=()

# 各バリエーションを実行
for variation in "${VARIATION_ARRAY[@]}"; do
  log "--- Running: $variation ---"

  if "$SCRIPT_DIR/run-pilot.sh" -s "$SCENARIO" -v "$variation"; then
    PASSED_VARIATIONS+=("$variation")
    log "✅ $variation: PASSED"
  else
    FAILED_VARIATIONS+=("$variation")
    log "❌ $variation: FAILED"
  fi

  # 次の実行前に少し待機
  sleep 5
done

# 比較レポートを生成
log "Generating comparison report..."

cd "$SCRIPT_DIR"
npx tsx lib/report-generator.ts "$SCENARIO"

# サマリー
log "=== Comparison Complete ==="
log "Passed: ${PASSED_VARIATIONS[*]:-none}"
log "Failed: ${FAILED_VARIATIONS[*]:-none}"
log "Reports: $SCRIPT_DIR/reports/"

# 失敗があれば終了コード1
if [ ${#FAILED_VARIATIONS[@]} -gt 0 ]; then
  exit 1
fi
