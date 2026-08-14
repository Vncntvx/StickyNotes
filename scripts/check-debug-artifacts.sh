#!/bin/bash
# check-debug-artifacts.sh — Roadmap G3: 拦截发布版临时调试物。
#
# 规则（Roadmap §5 G3）：
#   1. App/Sources 内禁止 `NSTemporaryDirectory()` 直写日志/文件（诊断信息必须
#      经 StickyLogger 消毒出口，FR-165/191）。
#   2. 禁止未 `#if DEBUG` 包裹的临时文件写入模式（FileHandle 直写、.write(to:)
#      到临时目录）。
#   3. 禁止调试关键字文件（如 sticky-diagnose.log 命名）。
#
# 用法：scripts/check-debug-artifacts.sh [path]（默认扫描 App/Sources/）
# 退出码：0 = 通过；1 = 命中违规（输出违规列表）。

set -u

TARGET="${1:-App/Sources}"
FAILURES=0

while IFS= read -r file; do
  lineno=0
  while IFS= read -r line; do
    lineno=$((lineno + 1))
    # 跳过纯注释行
    trimmed="$(echo "$line" | sed 's/^[[:space:]]*//')"
    case "$trimmed" in
      //*|\/\**) continue ;;
    esac
    if [[ "$line" == *"NSTemporaryDirectory()"* ]]; then
      echo "VIOLATION [$file:$lineno] NSTemporaryDirectory() direct temp-file usage (发布版临时调试物): $line"
      FAILURES=$((FAILURES + 1))
    fi
    if [[ "$line" == *"FileHandle(forWritingAtPath:"* ]]; then
      echo "VIOLATION [$file:$lineno] raw FileHandle write (应经 StickyLogger): $line"
      FAILURES=$((FAILURES + 1))
    fi
    if [[ "$line" == *"sticky-diagnose"* ]]; then
      echo "VIOLATION [$file:$lineno] debug artifact keyword 'sticky-diagnose': $line"
      FAILURES=$((FAILURES + 1))
    fi
  done < "$file"
done < <(find "$TARGET" -name "*.swift" -type f 2>/dev/null | sort)

if [[ "$FAILURES" -gt 0 ]]; then
  echo ""
  echo "check-debug-artifacts: $FAILURES violation(s) found (Roadmap G3)."
  exit 1
fi
echo "check-debug-artifacts: OK (no temp-file debug artifacts in $TARGET)."
