# ADR-2026-08-15: macOS 27 生态对齐评估（R3.9 Research Spike）

**Status**: Accepted（记录决策，代码随评估结论落定）

**Date**: 2026-08-15

**Scope**: `App/Sources`（编辑器、捕获、DesignSystem）+ `EditorCore`

## 背景

Roadmap R3.9（Phase 3）：评估 macOS 26/27 生态对齐机会，产出采用/搁置决策记录。Spike 结论喂给 R3.8（API 现代化批次）并同步过时文档/注释。

## 决策 1：AttributedTextSelection — 搁置（不迁移）

**评估对象**: [AttributedTextSelection](https://developer.apple.com/documentation/swiftui/attributedtextselection)（macOS 26+，SwiftUI）

**结论**: 不替换自建选区桥（`EditorSelectionBridge`/`EditorRegistry`/scalar↔UTF-16 换算）。

**依据**:
- `AttributedTextSelection` 是 SwiftUI `Text`/`TextEditor` 的 **display-only** selection binding——它反映系统渲染文本的选区，不提供富文本 marks 的读写控制面。
- 本项目编辑器是 **AppKit `NSTextView` 系**（`RichTextView`/`CodeTextView`），选区经 `NSTextViewDelegate` 实时发布到 `EditorSelectionBridge`（scalar↔UTF-16 换算、跨块选区组装、插入目标解析）。SwiftUI 的 selection API 与 NSTextView 编辑器**不共存**——没有桥可以把 `AttributedTextSelection` 接到 NSTextView 上。
- 迁移成本（重写编辑器宿主为 SwiftUI TextEditor + 富文本渲染器）远超收益，且会丢失既有 FR-053/FR-054 跨块复制、marks 往返、IME 安全等已验证能力。

**影响**: 自建选区桥保留；`EditorSelectionBridge` 的 scalar↔UTF-16 换算注释补充上述依据。

## 决策 2：EditorAppBridge "TextEditor 无 selection API" 论断 — 修正

**评估对象**: [EditorAppBridge.swift](App/Sources/Features/Editor/EditorAppBridge.swift) 头部注释（"SwiftUI `TextEditor` exposes no selection API"）

**结论**: 论断**基本正确但需精确化**——macOS 26 的 SwiftUI `Text`/`TextEditor` 仍不暴露编程式 selection 控制 API；新增的 `AttributedTextSelection` 是显示绑定（反映渲染选区），不能用于程序化设置/读取 marks，也不能接 NSTextView。注释更新为引用决策 1 的精确表述。

**影响**: 注释修正（含链接），无代码改动。

## 决策 3：CGRequestScreenCaptureAccess — 未废弃，保留

**评估对象**: [CGRequestScreenCaptureAccess](https://developer.apple.com/documentation/coregraphics/1454423-cgrequestscreencaptureaccess)（macOS 27 SDK）

**结论**: 该函数在 macOS 27 SDK 中**未废弃**，仍是屏幕录制权限的权威请求入口；`CGPreflightScreenCaptureAccess` 仍是只读状态检查（不弹窗，FR-014a/T210 启动路径约束不变）。ScreenCaptureKit（`SCContentSharingPicker`/`SCStream`）负责捕获管线，权限门仍由 CoreGraphics 系列函数把关。

**影响**: `PermissionService`（SystemBridge）保持现状；FR-131 的用户发起式请求语义不变。

## 决策 4：Liquid Glass 使用面 — 保持现状（确认合规）

**评估对象**: `.glassEffect`/`.buttonStyle(.glass)`（`BlockInsertionControl`/`RichTextBlockView`/`MenuBarLibraryScene` 等 7 处）

**结论**: 使用面与 macOS 26/27 SDK 对齐；`#available(macOS 26)` 守卫已在 R3.2 清除（部署目标即 26.0，else 分支不可达）。R3.2 的不可达 else 删除正是本项复核的落地。

**影响**: 无新增改动；R3.8 不涉及 Liquid Glass。

## 决策 5（衍生）：Task.sleep/DateFormatter 现代化 — 已由 R3.8 落地

Spike 结论确认 R3.8 的机械项（`Task.sleep(for:)`、`Date.FormatStyle`）与编辑器选区无关，可独立推进——R3.8 已按此完成。

## 归档同步

- `Documentation/toolchain.md`: 无变更（部署目标/语言模式不受影响）。
- `EditorAppBridge.swift` 注释按决策 2 更新。
- 本 ADR 归档于 `Documentation/adr/`。
