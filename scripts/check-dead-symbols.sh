#!/bin/bash
# check-dead-symbols.sh — Roadmap G2: 死符号零引用门控。
#
# 规则：对每个受审计的死符号（R3.2 删除批次，D-7…D-17），全仓
# （App/Sources、AppTests、Packages/StickyCore 的 Sources/Tests、Resources）
# 引用计数必须为 0；命中即非零退出。
#
# 用法：scripts/check-dead-symbols.sh [path]（默认仓库根）
# 退出码：0 = 通过；1 = 命中违规（输出违规列表）。

set -u

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
FAILURES=0

# 死符号清单：符号 -> 首次审计引用（roadmap R3.2 / 审计 D-7…D-17）
declare -a SYMBOLS=(
  "SecurityCoreModule"
  "SyncCoreModule"
  "match(atStartOf"
  "AccessibilityAdaptations"
  "DisplayFormatters.dateTime"
  "NotePalette.color(for:"
  "ReadableTheme.background(for:"
  "saveFirstLaunchState"
  "markOnboardingHintSeen"
  "resetFirstLaunchState"
  "AppMetrics.tightSpacing"
  "AppMetrics.sectionSpacing"
  "AppMetrics.cardTitleSize"
)

# 扫描范围：源码 + 测试 + 资源（排除 .build / DerivedData / 本脚本）
FILES=$(find "$ROOT/App/Sources" "$ROOT/AppTests" \
  "$ROOT/Packages/StickyCore/Sources" "$ROOT/Packages/StickyCore/Tests" \
  "$ROOT/App/Resources" \
  -type f \( -name "*.swift" -o -name "*.plist" -o -name "*.xcstrings" \) \
  2>/dev/null | grep -v "/.build/" | grep -v "/DerivedData/" | sort)

for symbol in "${SYMBOLS[@]}"; do
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    if grep -qF -- "$symbol" "$file" 2>/dev/null; then
      echo "VIOLATION [$symbol] referenced in: $file"
      FAILURES=$((FAILURES + 1))
    fi
  done <<< "$FILES"
done

if [[ "$FAILURES" -gt 0 ]]; then
  echo ""
  echo "check-dead-symbols: $FAILURES reference(s) to audited dead symbols (Roadmap G2)."
  exit 1
fi
echo "check-dead-symbols: OK (zero references to audited dead symbols)."
