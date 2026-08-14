#!/bin/bash
# check-empty-assertions.sh — Roadmap G1: 拦截"测试自证"空断言。
#
# 规则（Roadmap §5 G1）：
#   1. 裸 `#expect(true)`：除非豁免——该行前 3 行内存在 `Issue.record(`（fail-closed
#      catch 配对）或同行/前一行存在豁免注释（`// allowed` / `// fail-closed`）。
#   2. 字面量空串断言 `#expect(!"..." .isEmpty)` 形式：恒真断言，一律拦截。
#
# 用法：scripts/check-empty-assertions.sh [path]（默认扫描 AppTests/）
# 退出码：0 = 通过；1 = 命中违规（输出违规列表）。

set -u

TARGET="${1:-AppTests}"
FAILURES=0

while IFS= read -r file; do
  lineno=0
  prev=""
  prev2=""
  prev3=""
  while IFS= read -r line; do
    lineno=$((lineno + 1))
    # 规则 2：字面量空串断言 #expect(!"literal".isEmpty)
    if [[ "$line" =~ \#expect\(\!\"[^\"]*\"\.isEmpty\) ]]; then
      echo "VIOLATION [$file:$lineno] literal empty-string assertion (恒真断言): $line"
      FAILURES=$((FAILURES + 1))
      prev="$line"
      continue
    fi
    # 规则 1：裸 #expect(true)
    if [[ "$line" =~ \#expect\(true\) ]]; then
      exempt=false
      # 豁免 A：前 3 行内有 Issue.record（fail-closed catch 配对）
      if [[ "$prev3" == *"Issue.record("* ]]; then
        exempt=true
      fi
      if [[ "$prev" == *"Issue.record("* ]]; then
        exempt=true
      fi
      # 豁免 B：同行或前一行有豁免注释
      if [[ "$line" == *"// allowed"* || "$line" == *"// fail-closed"* \
         || "$prev" == *"// allowed"* || "$prev" == *"// fail-closed"* ]]; then
        exempt=true
      fi
      if [[ "$exempt" != true ]]; then
        echo "VIOLATION [$file:$lineno] bare #expect(true) (测试自证空断言): $line"
        FAILURES=$((FAILURES + 1))
      fi
    fi
    prev3="$prev2"
    prev2="$prev"
    prev="$line"
  done < "$file"
done < <(find "$TARGET" -name "*.swift" -type f 2>/dev/null | sort)

if [[ "$FAILURES" -gt 0 ]]; then
  echo ""
  echo "check-empty-assertions: $FAILURES violation(s) found (Roadmap G1)."
  exit 1
fi
echo "check-empty-assertions: OK (no bare #expect(true) / literal empty-string assertions)."
