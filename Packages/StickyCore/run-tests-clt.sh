#!/bin/bash
#
# run-tests-clt.sh — run StickyCore SwiftPM tests in a Command Line Tools-only
# environment (no full Xcode install).
#
# The CLT Swift 6.4 toolchain ships Testing.framework but not XCTest, and the
# TestingMacros plugin lives at a non-default path. These flags make Swift
# Testing work end-to-end. They are NOT needed in a full Xcode 26.x install.
#
# See Documentation/toolchain.md for the full toolchain note.
#
set -euo pipefail

# Run from the StickyCore package directory (where Package.swift lives).
cd "$(dirname "$0")"

CLT_ROOT="/Library/Developer/CommandLineTools"

exec swift test \
  -Xswiftc -load-plugin-library \
  -Xswiftc "$CLT_ROOT/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib" \
  -Xlinker -rpath -Xlinker "$CLT_ROOT/Library/Developer/Frameworks" \
  -Xlinker -rpath -Xlinker "$CLT_ROOT/Library/Developer/usr/lib" \
  "$@"
