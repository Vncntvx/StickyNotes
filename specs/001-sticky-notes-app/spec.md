# Feature Specification: macOS Sticky Notes

**Feature Branch**: `001-sticky-notes-app`

**Created**: 2026-08-06

**Status**: Draft

**Input**: User description: "Build a minimalist, native sticky-notes application for macOS 26 and later. Use 'macOS Sticky Notes' only as a working title; do not invent a final product or brand name."

## Clarifications

The product-behavior clarifications confirmed in the 2026-08-07 sessions are
encoded directly in the sections below: FR-012a, FR-014b, FR-022a, FR-022b,
FR-023a, FR-031a, FR-040a, FR-041a, FR-050a, FR-072a, FR-072b, FR-090a,
FR-090b, FR-094a, FR-110a, FR-140a, FR-141a, FR-152a, FR-154,
FR-160a–FR-160e, FR-162a, FR-174, FR-180a, FR-191,
and the "different vault detected" edge case. The original question-and-answer
log is preserved in the feature branch history.

### Session 2026-08-07

- Q: 在判断一个新建笔记是否可以被自动删除时（FR-012/FR-013），什么标准界定"有意义的文本"——仅含空白字符不算，那么仅含一个非空白字符、一个 emoji、或仅含标点符号的笔记是否算"有意义"从而不被自动删除？ → A: 含至少一个非空白字符（Unicode 非 whitespace）即视为"有意义"。
- Q: 在配置同步时如果用户输入了错误的同步密码，应用在多少次失败尝试后应采取额外限制（如延迟或锁定），还是不限制重试次数仅每次都失败关闭？ → A: 不限制重试次数；每次失败都失败关闭且不缓存密码；依赖 Argon2id 计算成本节流。
- Q: 在应用启动时，已配置并启用自动同步的 vault 应如何处理 unlock 状态——是要求用户每次启动手动输入同步密码解锁，还是在未重启 Mac 时（FR-162a 的"remember unlocked vault"启用时）静默从 Keychain 恢复解锁状态并立即开始同步？ → A: 启用 remember 时，Mac 未重启则静默恢复解锁并触发启动同步；未启用 remember 时要求手动输入密码。
- Q: 当用户在 Settings 中切换"remember unlocked vault"开关（从启用改为禁用，且 vault 当前处于解锁状态）时，应用应立即清空 Keychain 中记住的密钥并保留当前解锁状态直到退出，还是立即锁定 vault 强制重新输入密码？ → A: 立即清空 Keychain 中记住的密钥；保留当前解锁状态直到用户显式锁定或退出应用。
- Q: 在 Trash 中恢复一个笔记时（FR-014/US6），其原始的 manual sort-key（FR-022a）应如何处理——保留它被删除前的原 sort-key、还是分配一个新的 sort-key 放到 Manual 排序末尾，以避免与删除期间新增的笔记 sort-key 冲突？ → A: 分配新 sort-key = 当前最大 key + 1024，放到 Manual 排序末尾。
- Q: 当一个笔记的窗口已经打开时，用户从菜单栏库或废纸篓中删除该笔记，应用应如何处理已打开的窗口？ → A: 立即关闭窗口并显示一次性轻提示（"已移入废纸篓" / "已永久删除"）。
- Q: 当用户在 macOS 增强对比度（Increased Contrast）模式下使用自定义笔记颜色与较高透明度时，应用应使用什么客观可验证的对比度阈值来判定文本/控件"可读"，并在不达标时如何处理？ → A: 采用 WCAG 2.2 AA（正文 ≥4.5:1，大字/控件 ≥3:1）；不达标时自动调整前景色至达标而非拒绝。
- Q: 当用户从菜单栏库（或全局快捷键）创建新笔记窗口时，键盘焦点应如何转移？ → A: 新笔记窗口立即获得键盘焦点；库窗口保持打开但不持有焦点。
- Q: 当用户打开一个包含 100 个以上 todo 项的笔记时，编辑器与笔记卡片应如何处理 todo 列表的展示与性能？ → A: 编辑器虚拟化滚动；卡片显示 "完成/总数"，超过 99 项显示 "99+ 完成"。
- Q: 当用户删除一个笔记中被选为封面（cover）的截图 block 时，应用应如何在同一事务中处理 `Note.coverScreenshotBlockId` 引用？ → A: 同一事务内自动置空 `coverScreenshotBlockId`，无额外提示，卡片回退为无封面。
- Q: 首次发布是否需要支持笔记 JSON 导入，且导出是否复用同步用的规范 JSON 信封格式？ → A: 首发支持导出+导入且往返一致；导出复用规范 JSON 信封 schema（编码为 FR-031a）。
- Q: 首发版本界面文案需要本地化为哪些语言？ → A: zh-Hans 与 en 双语，跟随系统语言自动切换（编码为 FR-180a）。
- Q: 是否需要定义单笔记/单资产规模上限及超限行为？ → A: 设明确上限——单资产 ≤ 50 MB 且最长边 ≤ 16,384 像素；单笔记结构化内容 ≤ 5 MB；超限时拒绝该次插入并给出本地化说明，不影响其余编辑（编码为 FR-090b）。
- Q: 自动保存的节奏与非正常退出时的可接受输入丢失窗口如何定义？ → A: 输入停顿 500ms 后防抖落盘（与同步防抖解耦），关闭/删除/退出前同步刷新；崩溃时最多丢失最近一个防抖窗口内的输入（编码为 FR-141a）。
- Q: 两台 Mac 在 Manual 排序下对同一批笔记做了不同重排（仅排序位置分叉）时，同步如何解决？ → A: 排序键按每笔记最后写入者胜出（LWW）单独协调，不产生内容冲突副本（编码为 FR-022b）。
- Q: 首发是否需要「导出全部笔记」与「批量导入」作为整库备份/迁移手段？ → A: 不需要；首发仅支持单笔记 JSON 导出/导入（FR-031a），整库批量备份/导入明确列为非目标。
- Q: 六种内置笔记颜色（Yellow、Pink、Purple、Blue、Green、Gray）首发是否需要定义为具体 sRGB hex 值？ → A: 需要，每色一个规范 hex，亮/暗模式共用（编码为 FR-040a）。
- Q: 桌面 widget 的内容刷新策略是什么？ → A: 变更驱动刷新——主应用在本地数据变更后主动触发相关 widget 时间线刷新，无固定高频轮询间隔（编码为 FR-110a）。
- Q: 笔记背景透明度的可调范围、步长与默认值是什么？ → A: 不透明度默认 100%，可调范围 40%–100%，步长 5%；低于 100% 时按 FR-042 自动调整前景色（编码为 FR-041a）。
- Q: 编辑器中的 block 被清空时应如何处置？ → A: 光标停留时保留空 block 继续输入；光标移出后自动移除（合并入相邻块），最后一块保留为新的空段落；移除必须可 Undo（编码为 FR-050a）。
- Q: 首发是否需要「清空回收站」批量永久删除动作？ → A: 需要，弹确认并明确说明立即永久删除、不再有 30 天恢复期（编码为 FR-014b）。

## User Scenarios & Testing *(mandatory)*

<!--
  User journeys are organized as independently testable stories prioritized
  P1 → P2 → P3. Each story is a standalone slice: implementing only its
  acceptance scenarios must still deliver usable value. Priorities follow the
  intended order supplied in the feature description:
    P1: local creation, editing, storage, retrieval, independent windows,
        search, note appearance, todos, code blocks, file references, Trash,
        and essential menu-bar behavior.
    P2: screenshot capture and association, pasted images, widgets, global
        shortcuts, Dock behavior, display-position recovery, and permission
        management.
    P3: WebDAV and S3-compatible synchronization, end-to-end encryption,
        multi-device conflict behavior, remote deletion safety, and
        synchronization diagnostics.
-->

### User Story 1 - Local Note Capture and Editing (Priority: P1)

A user opens the menu-bar library, creates a blank note, types information
into an independent window, and closes the window knowing the note is saved
without pressing a Save button.

**Why this priority**: Capture is the reason the product exists. If nothing
else works, a user must be able to write a note and trust it is kept. This is
the minimum viable sticky-notes experience.

**Independent Test**: Can be fully tested by clicking the menu-bar icon,
creating a note, typing text, closing the window, reopening the note from the
library, and verifying the typed text is present and unchanged.

**Acceptance Scenarios**:

1. **Given** the application is running, **When** the user clicks the menu-bar
   icon, **Then** a note-library window opens directly beneath and visually
   attached to the menu bar, and **When** the user clicks outside that window,
   **Then** it dismisses automatically.
2. **Given** the library window is open, **When** the user creates a new note,
   **Then** an independent note window opens, ready for typing.
3. **Given** an open note window, **When** the user types text and then closes
   the window without pressing a Save button, **Then** the note's content is
   preserved exactly as typed.
4. **Given** a note whose window was closed, **When** the user reopens it from
   the menu-bar library, **Then** the previously typed content is present and
   the note is not duplicated.
5. **Given** the user has multiple different notes, **When** the user opens
   several of them, **Then** multiple independent note windows are open
   simultaneously, and **When** the user selects a note that is already open,
   **Then** the existing window is focused and no duplicate window is created.
6. **Given** the menu-bar library is already open and focused, **When** the user
   clicks the menu-bar icon again, **Then** the library is dismissed; **Given**
   the library is open but not focused, **When** the user clicks the icon,
   **Then** the library is focused and no second library window appears.

---

### User Story 2 - Retrieval, Browsing, and Search (Priority: P1)

A user returns later, searches across all active notes by any word they
remember, switches how notes are sorted, and finds the right note with minimal
effort.

**Why this priority**: Captured information is worthless if it cannot be
retrieved. Search and browsing are the second half of the core loop and must
work fully offline.

**Independent Test**: Can be tested by creating several notes with varied
titles and content, then searching for a word that appears only in a body,
a todo, a code block, or a file-reference name, and confirming the matching
note appears.

**Acceptance Scenarios**:

1. **Given** a library with several notes, **When** the user enters a search
   query, **Then** results update promptly as the query changes and match
   manual titles, normal text, todo text, code-block text, file display names,
   and screenshot captions.
2. **Given** the library, **When** the user switches the sorting method,
   **Then** notes reorder among Recently Modified, Recently Created, Title
   order, and Manual order.
3. **Given** Manual order is selected, **When** the user reorders notes,
   **Then** the chosen order persists.
4. **Given** a note with no manual title, **When** it is displayed as a card,
   **Then** a generated summary from its first meaningful content is shown as a
   temporary title, **And** that generated summary does not silently become a
   permanent manual title.
5. **Given** the application is fully offline, **When** the user searches and
   browses, **Then** retrieval works identically to online use.

---

### User Story 3 - Note Appearance and Independent Windows (Priority: P1)

A user keeps a note visible on the desktop as a colored sheet, sets it to stay
on top of other windows, adjusts its transparency and text size, and the note
remembers its size and position.

**Why this priority**: "Keep information visible when needed" is a core
responsibility. Note windows that look like sheets of paper and stay on top are
what differentiate this from a plain text editor.

**Independent Test**: Can be tested by opening a note, choosing a color,
enabling Always on Top, resizing and moving the window, closing and reopening
it, and verifying the appearance, on-top state, size, and position persist.

**Acceptance Scenarios**:

1. **Given** an open note window, **When** the pointer enters the upper area,
   **Then** window controls become visible and allow editing an optional title,
   changing note color, changing transparency, changing text size, toggling
   Always on Top, adding a screenshot, adding a file reference, opening
   additional actions, and closing the window.
2. **Given** a note window, **When** the user chooses a built-in color (Yellow,
   Pink, Purple, Blue, Green, or Gray) or a custom color, **Then** the note
   adopts it and the choice persists.
3. **Given** a note window, **When** the user enables Always on Top, **Then**
   that note stays above other windows, and **When** the user disables it,
   **Then** it returns to normal stacking; the setting is independent per note.
4. **Given** a note window, **When** the user resizes and repositions it,
   **Then** the note remembers its last window size and preferred position.
5. **Given** a note window that would become inaccessible because its display
   was disconnected, **When** the application detects this, **Then** the window
   is moved into the visible area of the main display, **And** the preferred
   position for the disconnected display is preserved so the note can return
   when that display reconnects.

---

### User Story 4 - Todos, Code Blocks, and File References (Priority: P1)

A user adds a checklist of todo items to a note, inserts a multiline code
block with a copy button, and drops a file from Finder as a reference that can
be opened or revealed without being copied into the note.

**Why this priority**: Lightweight formatting, todos, code, and file references
are the structured content that makes a sticky note more than plain text. They
round out the P1 capture/edit/retrieve surface.

**Independent Test**: Can be tested by adding todos and toggling them,
inserting a code block and copying it, and dragging a file into a note then
opening it from the note and revealing it in Finder.

**Acceptance Scenarios**:

1. **Given** a note, **When** the user creates todo items, **Then** each can be
   marked complete or incomplete (with a visible completed state and
   strikethrough, communicated by more than color alone), dragged to reorder,
   indented as a subtask, un-indented, edited, and deleted.
2. **Given** two todo items with identical text, **When** they are reordered or
   their text changes, or one is updated from a widget, or notes synchronize
   between devices, **Then** each todo retains a stable identity distinct from
   its text.
3. **Given** a note, **When** the user inserts a multiline code block, **Then**
   it shows monospaced display, preserved spaces/tabs/line breaks, a copy
   button, an optional language label, and readable presentation of long lines
   via wrapping or horizontal scrolling; copying copies only the code contents.
4. **Given** a file dragged from Finder into a note, **When** it is dropped,
   **Then** it is represented as a reference card (not copied into the
   application, not uploaded as an attachment) showing file name, file
   icon/type, approximate size when available, date added, availability status,
   and the Mac where the reference was created.
5. **Given** a file-reference card, **When** the file is available, **Then** the
   user can open it, reveal it in Finder, copy its path, and drag it from the
   note into Finder or another application; ordinary drag-out copies the file
   and does not silently move or delete the original.
6. **Given** a file-reference card whose original can no longer be found,
   **When** the file is missing or unavailable, **Then** the card is preserved
   and relinking is offered; the application does not automatically scan the
   entire filesystem or silently delete the card.

---

### User Story 5 - Markdown Input and Undo (Priority: P1)

A user types Markdown-style shortcuts that convert into formatted content, and a
single Undo restores the exact Markdown syntax that existed before conversion,
without corrupting Chinese input or input-method composition.

**Why this priority**: Markdown shortcuts make capture fast, and reliable Undo
is essential to trust. Correctness with Chinese and marked-text composition is
a non-negotiable correctness requirement, not a polish item.

**Independent Test**: Can be tested by typing each supported Markdown pattern,
verifying it converts, then pressing Undo once and verifying the exact original
syntax returns; then repeating with active Chinese input-method composition.

**Acceptance Scenarios**:

1. **Given** an empty line, **When** the user types `# ` then text, **Then** the
   line converts to a heading; `- ` converts to a bulleted item; `- [ ] `
   converts to a todo item.
2. **Given** text being typed, **When** the user enters valid inline syntax
   (`**bold**`, `*italic*` or `_italic_`, `~~strike~~`, backticked inline code,
   triple-backtick code blocks with an optional language label), **Then** it
   converts after a valid closing delimiter and is finalized when the insertion
   point leaves the range or the user confirms the line.
3. **Given** an automatic conversion just occurred, **When** the user presses
   Undo once, **Then** the exact Markdown syntax and formatting state that
   existed before conversion is restored.
4. **Given** active Chinese input-method marked text, mixed Chinese and English,
   emoji, or partially entered syntax, **When** automatic conversion runs,
   **Then** it does not corrupt the composition, the marked text, or the
   partially entered syntax.

---

### User Story 6 - Trash and Deletion Lifecycle (Priority: P1)

A user deletes a note, finds it in Trash, restores it, or permanently deletes
it; deleted notes stay recoverable for 30 days. An empty note that never held
content may be auto-removed on close, but a note that previously held content is
never deleted just because its text is now empty.

**Why this priority**: Non-destructive behavior is a constitutional guarantee.
Users must trust that closing or deleting does not silently lose information.

**Independent Test**: Can be tested by deleting a note, opening Trash,
restoring it, permanently deleting another, and by emptying a note's text after
it had content and confirming it is not auto-deleted.

**Acceptance Scenarios**:

1. **Given** a note, **When** the user explicitly deletes it, **Then** it enters
   Trash and remains recoverable for 30 days unless permanently deleted
   earlier.
2. **Given** a note in Trash, **When** the user restores it, **Then** it returns
   to the active library; **When** the user permanently deletes it, **Then** it
   is removed beyond Trash recovery.
3. **Given** a newly created note that has never contained meaningful text, a
   title, a todo, an image, a screenshot, a code block, or a file reference,
   **When** its window is closed, **Then** it may be removed automatically.
4. **Given** a note that previously contained meaningful content, **When** its
   current text becomes empty, **Then** it is not deleted merely because the
   text is empty.
5. **Given** the menu-bar library, **When** the user opens Trash, **Then** the
   user can distinguish a note in local Trash from a normal active note.

---

### User Story 7 - Screenshot Capture and Clipboard Images (Priority: P2)

A user captures a screen region or an application window into a new or existing
note, pastes an image from the clipboard, views screenshots at full size, and
selects one as the note card's cover image. Screenshots are static; the product
never continuously records or controls another application.

**Why this priority**: Screenshots and pasted images add the visual-capture
dimension. They depend on screen-recording permission, so they sit in P2 and
must degrade gracefully when permission is denied.

**Independent Test**: Can be tested by capturing a region into a new note,
adding a window screenshot to an existing note, pasting a clipboard image, and
opening the screenshot viewer to zoom, copy, and navigate between screenshots.

**Acceptance Scenarios**:

1. **Given** the user invokes region capture, **When** screen-recording
   permission is granted, **Then** the user can select a screen region and
   create a new note containing that screenshot, or add it to an existing note.
2. **Given** the user invokes application-window capture, **When** permission is
   granted, **Then** the user can select an application window and create a new
   note containing its screenshot, or add it to an existing note; the note may
   preserve application name, application icon, window title, capture date and
   time, the original screenshot, a thumbnail, and an optional caption.
3. **Given** a note with screenshot associations, **When** the user selects one
   as the cover, **Then** its thumbnail appears as the note card's cover image;
   selecting a screenshot opens a large viewer supporting zoom, actual size,
   fit-to-window, copy, drag out, Save As, delete association, edit caption,
   and navigation between screenshots of the same note.
4. **Given** a screenshot association, **When** the viewer is open, **Then** the
   application does not automatically start, switch to, or control the original
   application.
5. **Given** an image on the clipboard, **When** the user pastes it into a note,
   **Then** an embedded copy is preserved (because a reliable original file may
   not exist) and the user can view, open a larger view, copy, drag out, save
   elsewhere, and remove it; embedded clipboard images participate in optional
   encrypted synchronization.
6. **Given** screen-recording permission is denied, **When** the user attempts
   capture, **Then** ordinary notes remain fully usable, the screenshot
   features clearly explain why they are unavailable, and the user can open the
   appropriate system settings.

---

### User Story 8 - Widgets, Global Shortcuts, Dock, and Permissions (Priority: P2)

A user adds a desktop widget showing a note or todos, toggles todos from the
widget, configures global shortcuts, hides the Dock icon while keeping all
functions reachable, and grants permissions only when actually needed.

**Why this priority**: Widgets, shortcuts, and Dock behavior extend the
always-available surface. Permission management is grouped here because widgets
and shortcuts may surface the same features that need permissions.

**Independent Test**: Can be tested by adding each widget form, marking a todo
from a widget, configuring a global shortcut, disabling the Dock icon, and
verifying Settings/Help/About/sync status/Quit remain reachable from the
menu-bar interface.

**Acceptance Scenarios**:

1. **Given** the system supports widgets, **When** the user adds a widget,
   **Then** available forms include a small widget for one user-selected note, a
   small widget for the most recently modified eligible note, a medium widget
   for multiple recent notes, a medium widget for todos from a selected note, a
   large widget for a broader overview, and a quick-create action.
2. **Given** a widget, **When** the user interacts with it, **Then** the user
   may open a specific note window, mark an individual todo complete or
   incomplete, create a new note, and move between eligible recent notes where
   appropriate; widgets do not attempt full rich-text editing.
3. **Given** a note, **When** the user excludes it from widgets, **Then** its
   title, body, todo text, images, screenshots, and summaries do not appear in
   widget timelines, previews, placeholders, or snapshots.
4. **Given** settings, **When** the user configures a global shortcut, **Then**
   available actions include opening/closing the menu-bar library, creating a
   blank note, capturing a region into a new note, selecting a window into a new
   note, creating a note from clipboard contents, searching all notes, and
   showing or hiding open note windows; the application detects conflicts and
   does not silently replace an existing system or application shortcut.
5. **Given** the Dock icon is enabled by default, **When** the user disables it
   in Settings, **Then** Settings, Help, About, synchronization status, and Quit
   remain reachable from the menu-bar interface.
6. **Given** accessibility permission is denied, **When** the user uses the
   product, **Then** ordinary notes and manual screenshot selection remain
   usable and only advanced window-identification behavior is unavailable;
   accessibility permission is never requested merely because a future feature
   might use it.

---

### User Story 9 - Optional Encrypted Synchronization (Priority: P3)

A user configures exactly one WebDAV or S3-compatible repository, sets a
synchronization password, and notes replicate end-to-end encrypted between their
Macs. The remote provider cannot read note content or meaningful metadata.
Local editing never waits for synchronization.

**Why this priority**: Sync is optional and additive. It is valuable for
multi-Mac users but must never compromise the local-first core, so it is the
last priority.

**Independent Test**: Can be tested by configuring one repository, triggering
manual synchronization, editing offline, reconnecting, and confirming changes
appear on another Mac while the remote provider cannot read the content.

**Acceptance Scenarios**:

1. **Given** synchronization settings, **When** the user configures a
   repository, **Then** exactly one repository is supported at a time — one
   WebDAV repository or one S3-compatible repository — and S3-compatible
   synchronization allows a configurable endpoint (not restricted to one
   vendor); the user can test the connection, enable/disable automatic
   synchronization, trigger manual synchronization, view the last successful
   synchronization time, view actionable errors, and remove local configuration
   without deleting local notes.
2. **Given** an active repository, **When** content changes, **Then**
   synchronization occurs through a combination of a short delay after changes,
   periodic synchronization, application startup, application shutdown when
   practical, manual synchronization, and network reconnection; local editing
   does not wait for synchronization to complete.
3. **Given** synchronized content, **When** it leaves the device, **Then** all
   note content and meaningful metadata are encrypted on the user's Mac before
   upload, and the remote service cannot read note titles, bodies, todo text,
   code-block contents, file-reference names, application names, window titles,
   screenshot captions, device display names, or the semantic type of each
   remote object; remote object names do not reveal contents.
4. **Given** the synchronization password, **When** the user forgets it,
   **Then** the product clearly explains that the encrypted remote data may be
   permanently unrecoverable and that neither the developer nor the storage
   provider can restore it.
5. **Given** a network outage, **When** the user continues editing locally,
   **Then** local work continues and is not blocked by network failures.

---

### User Story 10 - Synchronization Conflicts and Remote Deletion (Priority: P3)

When two Macs independently modify the same note, both versions are preserved
as the original note plus a clearly labeled conflict copy; when one device
deletes a note while another edits it, the edited content is preserved as a
recovered conflict copy; deletions propagate safely with a 30-day tombstone.

**Why this priority**: Non-destructive conflict handling and deletion safety are
constitutional guarantees for synchronization. They must hold even when devices
are offline for extended periods.

**Independent Test**: Can be tested by editing the same note on two offline
Macs, synchronizing both, and confirming both versions survive as original plus
conflict copy; then deleting on one device while editing offline on another and
confirming the edited content survives as a recovered conflict copy.

**Acceptance Scenarios**:

1. **Given** two Macs that independently modified the same note from a common
   earlier version, **When** they synchronize, **Then** one version remains the
   original note and the other is preserved as a new conflict-copy note, clearly
   labeled with useful origin and time information, with text, todos, code
   blocks, images, screenshots, and file-reference metadata preserved; the user
   can compare, edit, or delete either version; no automatic character-level or
   block-level merging is attempted.
2. **Given** one device deletes a note while another offline device modifies it,
   **When** they synchronize, **Then** the modified content is preserved as a
   recovered conflict copy rather than being silently lost or silently
   resurrecting the deleted original.
3. **Given** a deletion on one device, **When** another device is offline,
   **Then** a deletion record remains available for 30 days so the offline
   device cannot immediately recreate the deleted note; after the retention
   period, deleted content may be cleaned up only when doing so does not violate
   synchronization safety.
4. **Given** the library and Trash, **When** the user views notes, **Then** the
   user can distinguish a note in local Trash, a permanently deleted note, a
   recovered conflict copy, and a normal active note.
5. **Given** synchronization, **When** a remote error occurs, **Then** it is
   visible through non-blocking status and diagnostics without interrupting
   normal local editing; credentials and unlocked secrets never appear in logs
   or ordinary exported diagnostics.

---

### Edge Cases

Each case below is a testable scenario; the authoritative rule lives in the
cited FR.

- The menu-bar icon is clicked while the library window is already open: if the
  library is the focused window it is dismissed, otherwise it is focused, and a
  second instance is never opened (FR-009).
- A note window is positioned on a display that is then disconnected: the
  window reappears on the main display's visible area, and its preferred
  position for the disconnected display is preserved for return (FR-033).
- Pasted rich text contains unsupported or private attributed-string
  formatting: only application-supported formatting may persist; unsupported
  properties must not silently enter the durable format (FR-053).
- A todo item is toggled complete from a widget on one Mac while the note is
  open and being edited on another: todo identity stays stable and the change
  reconciles without losing either side (FR-071; US10).
- The user changes the synchronization password: this does not require
  uploading all unchanged content again (FR-164).
- The user configures synchronization against a repository that already
  contains a different vault's bootstrap; the application MUST fail closed
  with a clear "different vault detected" message, MUST NOT modify any local
  or remote data, and MUST prompt the user to choose a different repository
  or start a new empty vault (which bootstraps alongside the existing one
  without overwriting it).
- A device that was offline longer than 30 days returns online after another
  device has already purged the remote tombstone for a deleted note: the
  returning device MUST NOT auto-delete any local content, MUST treat the
  absence of a remote tombstone as "no deletion record found" (preserving
  locally-present notes), MUST NOT re-upload notes the user deleted on the
  returning device unless explicitly restored, and MUST inform the user that
  some synchronization history has aged out (FR-174).
- A screenshot is captured of an application window whose title or icon is
  unavailable: the note preserves whatever metadata is available and still
  stores the static screenshot.
- The user drags out a file reference whose original has since been moved:
  ordinary drag-out copies when possible and never silently moves or deletes
  the original (FR-102).
- The system is in increased-contrast mode with a custom note color and high
  transparency: text and controls remain readable (FR-042, FR-180, FR-182).
- A newly created note containing only whitespace is closed: it may be
  auto-removed, but a note that previously held content and is later emptied
  is never auto-deleted (FR-012, FR-013).
- Two todo items have byte-identical text: each remains independently
  identifiable and toggleable (FR-071).
- A note is deleted from the library or Trash while one of its windows is
  already open: the open window MUST close immediately and a one-time
  transient toast announces the deletion outcome ("Moved to Trash" or
  "Permanently Deleted"); the deletion itself is not blocked by the open
  window, and closing the window does not cancel the deletion (FR-009a).
- A note contains 100 or more todo items: the editor MUST render the todo
  list via virtualized scrolling (only visible rows realized) so editing and
  scrolling remain lag-free; the note card MUST show todo progress as
  "completed/total", switching to "99+ completed" when the total exceeds 99
  to avoid width overflow (FR-072b).
- A screenshot block that is currently selected as the note card's cover is
  deleted: `Note.coverScreenshotBlockId` MUST be nullified in the same
  transaction as the block deletion (no dangling reference ever observable);
  the note card falls back to a no-cover state with no extra confirmation
  (FR-094b).

## Requirements *(mandatory)*

### Scope

**In scope (initial release)**:

- A menu-bar-primary sticky-notes utility with a card-grid library and
  independent note windows.
- Local-first capture, editing, search, browsing, todos, code blocks, file
  references, clipboard images, and static screenshots.
- Note appearance (colors, transparency, text size, Always on Top, position
  memory) and Trash with 30-day recovery.
- Markdown-style input shortcuts with single-Undo restoration.
- Native desktop widgets (multiple forms), global shortcuts, Dock toggling, and
  graceful permission management.
- Optional end-to-end encrypted synchronization to exactly one WebDAV or
  S3-compatible repository, with non-destructive conflict handling and safe
  deletion propagation.

**Out of scope / Non-goals (initial release)**:

- Drawing or handwriting; image annotation.
- User accounts; developer-hosted cloud storage; a developer-operated
  synchronization server.
- Sharing or collaboration; real-time multi-user editing; comments or mentions.
- Reminders or alarms; calendar integration; recurring tasks;
  project-management features.
- Backlinks or relationship graphs; nested notebook hierarchies; Notion-style
  databases.
- Plugin execution of untrusted code.
- Live or continuously refreshed application-window previews.
- Full Markdown source editing (Markdown is an input convenience only).
- Code syntax highlighting, language detection, or execution; line numbers in
  code blocks.
- Automatic screenshot OCR in the initial release (OCR may be introduced later
  solely to expand search; if so, recognized text is searchable but OCR itself
  is not a stored rich-text attribute).
- Synchronization of referenced file contents.
- Whole-library bulk export/import (backup and restore of all notes at once);
  only single-note JSON export/import is provided (FR-031a).
- Simultaneous synchronization to multiple repositories.
- Automatic reopening of note windows after application relaunch.
- Displaying note windows across every macOS Space in the initial release.

### Functional Requirements

**Menu-bar library and primary experience**

- **FR-001**: The application MUST live primarily in the macOS menu bar, and
  clicking the menu-bar icon MUST open the note-library window directly beneath
  and visually attached to the menu bar.
- **FR-002**: The library MUST display notes as a compact card grid inspired by
  the Windows 11 Sticky Notes experience while following macOS interaction
  conventions.
- **FR-002a**: The card grid MUST display notes in a grid with a default of 3
  columns, card width of approximately 220 points, card height of
  approximately 160 points, and 12-point inter-card spacing. The grid MUST
  be responsive: columns reduce to 2 below 600 points window width and to 1
  below 400 points. These dimensions are tuned for the macOS 26 default
  system font at regular size.
- **FR-003**: Clicking outside the menu-bar window MUST dismiss it
  automatically.
- **FR-004**: From the library, the user MUST be able to create a note, search,
  change sorting, open Trash, view synchronization status, initiate manual
  synchronization, open Settings and Help, and quit the application.
- **FR-005**: Clicking a note card MUST open that note in an independent desktop
  window; multiple different note windows MAY be open simultaneously, but the
  same note MUST NOT open in duplicate windows — selecting an already-open note
  MUST focus its existing window.
- **FR-006**: Closing a note window MUST hide the window and preserve the note;
  closing MUST NEVER delete the note.
- **FR-007**: Note windows MUST NOT be automatically restored when the
  application is relaunched.
- **FR-007a**: When a new note window is created (from the menu-bar library,
  a global shortcut, a deep link, or a widget action), the new note window
  MUST immediately receive keyboard focus so the user can begin typing
  without an extra click (US1 capture intent). The menu-bar library window,
  if open, MUST remain open but MUST yield focus to the new note window — it
  MUST NOT auto-dismiss on note creation, so the user can create several
  notes in succession without re-invoking the menu-bar icon. When a global
  shortcut creates a new note while another application is focused, the
  StickyNotes application MUST be activated and the new note window MUST
  become the key window. Opening an already-existing note (FR-005) follows
  the same focus rule: focus the existing window rather than creating a
  duplicate. This makes note-creation focus behavior objectively testable
  and supports SC-003 (new note window presented within 200 ms) without a
  post-creation focus step that would add latency.
- **FR-008**: The Dock icon MUST be enabled by default and MAY be disabled by
  the user in Settings; when disabled, Settings, Help, About, synchronization
  status, and Quit MUST remain reachable from the menu-bar interface.
- **FR-009**: Clicking the menu-bar icon while the library window is already
  open MUST focus the library if it is not already the focused window, and MUST
  dismiss the library if it is already the focused window; a second library
  window MUST NEVER be opened.
- **FR-009a**: When a note is deleted from the menu-bar library or Trash while
  one of its independent windows is already open, the application MUST
  immediately close that open window and present a one-time, non-blocking
  transient toast/announcement confirming the deletion outcome ("Moved to
  Trash" or "Permanently Deleted", localized). The toast MUST NOT block other
  interaction and MUST NOT require dismissal for ordinary use; it auto-dismisses
  within a short, bounded period. The immediate-close rule keeps open surfaces
  consistent with lifecycle state (Constitution X) and is independent of FR-006
  (closing a window never deletes a note — here deletion causes the close, not
  the reverse). VoiceOver MUST announce the deletion outcome for accessibility
  (FR-180). A note deleted to Trash remains restorable per FR-014; restoring
  from Trash does NOT auto-reopen its window (FR-007 applies).

**Note lifecycle**

- **FR-010**: The user MUST be able to create a blank note from the library and
  create a blank note with a global keyboard shortcut.
- **FR-011**: The user MUST be able to open a note, edit without a Save button,
  close without deleting, reopen a hidden note, explicitly delete, restore from
  Trash, permanently delete, search active notes, change sorting, and manually
  reorder notes under manual sorting.
- **FR-012**: A newly created note that has never contained meaningful text, a
  title, a todo, an image, a screenshot, a code block, or a file reference MAY
  be removed automatically when its window is closed.
- **FR-013**: A note that previously contained meaningful content MUST NOT be
  deleted merely because its current text is empty.
- **FR-012a**: "Meaningful text" in FR-012/FR-013 MUST be defined as the
  presence of at least one non-whitespace Unicode character in the note's
  title field or any rich-text block. A single character (letter, digit,
  CJK character, emoji, punctuation, or any other non-whitespace code
  point) is sufficient to qualify as meaningful; whitespace-only content
  (spaces, tabs, newlines, and other Unicode whitespace) does NOT qualify.
  The same one-non-whitespace-character rule applies to the other
  meaningful-content categories (a todo, image, screenshot, code block,
  or file reference): the presence of any one such block counts as
  meaningful content regardless of its text length. This makes the
  auto-removal decision in FR-012 objectively testable and ensures a
  note in which the user typed even a single character is never silently
  deleted on close (Constitution III).
- **FR-014**: Deleted notes MUST remain recoverable in Trash for 30 days unless
  permanently deleted earlier.
- **FR-014a**: The first-launch experience MUST present an empty library
  with a clear call-to-action to create the first note (via button or
  keyboard shortcut). No permission prompts MUST be shown on first launch
  unless the user invokes a feature requiring them. If synchronization has
  not been configured, the sync-status area MUST show "not configured"
  rather than an error. The empty-library state MUST include a brief
  onboarding hint (dismissible, never shown again after the first note is
  created) explaining auto-save and the menu-bar-primary model.
- **FR-014b**: The application MUST provide an "Empty Trash" action that
  permanently deletes all notes currently in Trash (FR-014) in one batch.
  The action MUST require explicit user confirmation before executing, and
  the confirmation MUST state that emptying Trash permanently deletes the
  notes immediately and that the 30-day recoverability guarantee (FR-014)
  no longer applies to them. After execution, the deleted notes MUST follow
  the permanent-deletion path (unrecoverable via Trash; tombstones and
  sync-safety rules still apply per FR-174). The action MUST remain
  available from the Trash view in the menu-bar library, MUST be
  keyboard-accessible (FR-181), and its confirmation dialog MUST follow the
  FR-180a localization requirements.

**Note cards and browsing**

- **FR-020**: A card MAY show a manual title, a generated summary when no manual
  title exists, a short body preview, note color, last-modified time, todo
  completion progress, indicators for screenshots/images/file references, a
  selected screenshot thumbnail as cover, and a conflict or synchronization
  warning when applicable.
- **FR-021**: When a note has no manual title, the first meaningful content MAY
  be shown as a temporary summary, but it MUST NOT silently become a permanent
  manual title.
- **FR-022**: The user MUST be able to switch sorting among Recently Modified,
  Recently Created, Title order, and Manual order.
- **FR-022a**: Under Manual order, each note's sort position MUST be
  represented by an integer sort key with a gap of 1024 between adjacent
  notes. When a note is inserted between two existing notes, its sort key is
  set to the midpoint of the surrounding keys. When any adjacent gap within a
  contiguous run of notes falls below 64, the affected run MUST be
  renormalized by renumbering its sort keys with 1024 gaps; this
  renormalization MUST execute within a single database transaction so that
  no intermediate ordering is observable.   These concrete values (gap=1024,
  renormalize-at-<64) make reordering persistence deterministic and the
  gap-exhaustion edge case objectively testable. When a note is restored
  from Trash (FR-014), its manual sort-key MUST be reset to
  (current maximum sort-key among active notes) + 1024, placing it at the
  end of Manual order. The pre-deletion sort-key MUST NOT be retained,
  because notes may have been inserted or reordered during the deleted
  note's absence and the original position is no longer semantically
  valid. This makes restore-under-Manual-order behavior deterministic and
  conflict-free (the new key is strictly greater than all existing keys,
  so   no renormalization is triggered by restore alone).
- **FR-022b**: Manual-order sort-key divergence during synchronization MUST be
  reconciled per note by last-writer-wins (LWW): when two devices reorder
  notes independently and only sort-key positions diverge (note content is
  unchanged), the application MUST apply the most recently written sort key
  per note and MUST NOT create content conflict copies (FR-171) for
  sort-key-only divergence. Content divergence is evaluated on content
  fields only. This is a deliberate, scoped interpretation of Constitution
  VIII: the no-silent-overwrite guarantee protects user content, while a
  reorder position is presentation metadata (FR-160a) whose loss carries no
  data-loss risk and whose conflict copies would be user-hostile noise. The
  LWW decision MUST be deterministic (e.g., by comparing the note version's
  timestamp/sequence) and MUST be covered by synchronization tests including
  the crossed-reorder case (A moves X above Y while B moves Y above X).
- **FR-023**: Search MUST match manual titles, normal text, todo text,
  code-block text, file display names, and screenshot captions, and MUST match
  text recognized from screenshots if OCR is introduced later.
- **FR-023a**: The full-text search index MUST be implemented as an FTS5
  external-content table backed by the canonical note/block rows, with an
  explicit mapping between FTS5 rowid and Note.id. The external-content
  design guarantees the search index cannot drift from canonical data
  (Constitution IV): when a note is deleted, its FTS5 index entry MUST be
  removed automatically via the canonical-row relationship. The rowid-to-
  Note.id mapping MUST be deterministic and stable across migrations. If the
  FTS5 index is ever detected as inconsistent with canonical rows, the
  application MUST rebuild it from canonical data without data loss. This
  makes drift-detection and rebuild logic objectively testable.
- **FR-024**: Search results MUST update promptly as the query changes.
- **FR-024a**: "Promptly" in FR-024 means search results MUST begin updating
  within 100 milliseconds of a query change and MUST complete within the
  SC-005 target (200 milliseconds for 10,000 notes). The update MAY be
  incremental (partial results shown before full completion).

**Independent note windows**

- **FR-030**: Each note window SHOULD look like a lightweight sheet of note
  paper while retaining normal macOS window behavior.
- **FR-030a**: A note window MUST have a borderless or thin-title-bar
  appearance with a 1-point subtle border, corner radius of 8 points, and a
  soft shadow (radius 8, opacity 0.15). The window background MUST use the
  selected note color at the configured transparency. The title-bar area
  MUST be visually integrated with the note background (no distinct toolbar
  chrome).
- **FR-031**: Most window controls SHOULD remain hidden until the pointer enters
  the upper area; that area MUST allow editing an optional title, changing note
  color, changing transparency, changing text size, toggling Always on Top,
  adding a screenshot, adding a file reference, opening a contextual menu
   with note-level actions (duplicate note, export note as JSON, copy note as
   Markdown, move to Trash), and closing the window.
- **FR-031a**: The "export note as JSON" note-level action (FR-031) MUST
  produce a versioned JSON document that reuses the canonical
  note-envelope schema used for encrypted synchronization (deterministic,
  versioned JSON per Constitution IV/VII), so the same schema is the
  single format contract for sync, export, and import. The initial
  release MUST also support importing such a JSON document (library-level
  action), and export→import MUST be round-trip faithful for: text and
  supported rich-text attributes, todos (text, completion state, nesting,
  ordering), code blocks, embedded clipboard images and screenshots
  (embedded as assets in the export), and note appearance (color,
  transparency, text size, Always-on-Top). File-reference blocks MUST
  export their generic metadata only (display name, content type,
  approximate size, origin device, added date) — never device-local
  bookmark data or absolute paths (FR-105). Import MUST validate the
  envelope schema version and fail closed on unsupported or corrupted
  envelopes without creating partial notes. Export/import round-trip MUST
  be covered by automated tests (Constitution XII), and on another Mac a
  re-linked file-reference card MAY show its generic metadata as
  unavailable (per FR-104).
- **FR-032**: Each note MUST remember its last window size and preferred
  position.
- **FR-033**: If a display is disconnected and a window would become
  inaccessible, the application MUST move it into the visible area of the main
  display and MUST preserve the preferred position for the disconnected display
  so the note can return when that display reconnects.
- **FR-034**: Always on Top MUST be configured separately per note.
- **FR-035**: The first release MUST NOT display note windows across every
  Space and MUST NOT force them over full-screen applications.

**Note appearance**

- **FR-040**: The user MUST be able to choose at least Yellow, Pink, Purple,
  Blue, Green, and Gray built-in colors, plus a custom color.
- **FR-040a**: Each built-in note color (FR-040) MUST have exactly one
  canonical sRGB hex value shared across light and dark appearance: Yellow
  `#FFE08A`, Pink `#F9A8C4`, Purple `#C9A8E8`, Blue `#A8CFF9`, Green
  `#A8E8B8`, Gray `#D8D8DC`. These canonical values are the deterministic
  input for the FR-042 WCAG 2.2 contrast validation (text and controls on
  each color MUST meet ≥4.5:1 normal / ≥3:1 large text and controls, with
  automatic foreground adjustment as the fallback). Any change to a
  canonical value MUST update FR-042's contrast tests in the same change
  (Constitution IV).
- **FR-041**: Notes MUST support adjustable background transparency while
  keeping text and controls readable.
- **FR-041a**: The background transparency adjustment (FR-041) MUST expose a
  bounded range: note background opacity MUST be adjustable between 40% and
  100% (inclusive), in steps of 5 percentage points, with a default of 100%
  (fully opaque). Whenever the chosen opacity is below 100%, the FR-042
  contrast validation and automatic foreground-color adjustment MUST be
  applied against the effective rendered background (note color composited
  at the chosen opacity over the desktop). This makes the transparency
  space finite (13 steps) and the contrast guarantee testable for every
  step (Constitution X/XI).
- **FR-042**: The interface MUST adapt to light mode, dark mode,
  increased-contrast preferences, and custom note colors. Readable contrast
  MUST be objectively verified against WCAG 2.2 AA: normal text MUST meet a
  contrast ratio of at least 4.5:1 against its rendered background, and large
  text (≥18 pt, or ≥14 pt bold) plus active controls MUST meet at least 3:1.
  When a user-selected custom note color combined with the configured
  transparency and the current system appearance (light/dark/Increased
  Contrast) would cause any text or control to fall below these thresholds,
  the application MUST automatically adjust the foreground color (e.g. shift
  toward black or white) until the threshold is met, rather than rejecting
  the user's color choice. This makes "readable" in FR-041/FR-042/FR-182
  objectively testable (Constitution X) and ensures no custom-color +
  transparency + Increased-Contrast combination produces illegible text.
- **FR-043**: The user MUST choose one global font preference for Chinese and
  English text; all notes MUST use that preference with appropriate fallback for
  unsupported characters; each note MAY use its own text size.
- **FR-044**: Color MUST NEVER be the only way to communicate state.

**Editor experience**

- **FR-050**: The editor MUST support normal rich text, an optional title, bold,
  italic, underline, strikethrough, bulleted lists, a simple heading style,
  auto-recognized web links, email addresses, telephone numbers, emoji, inline
  code, todo items, multiline code blocks, file-reference cards, embedded
  clipboard images, and static screenshot blocks.
- **FR-050a**: When a block's content is emptied in the editor (paragraph,
  list item, todo item, heading), the empty block MUST remain in place while
  the cursor is still within it, so the user can continue typing without the
  block disappearing mid-edit. When the cursor moves out of an empty block
  (via arrow keys, click, Enter at the wrong position, or focus change), the
  application MUST remove the empty block by merging its location with the
  adjacent block (or deleting it when no merge is possible). The final block
  of a note MUST never be removed this way — it MUST remain as an empty
  paragraph for continued typing. Every such automatic removal MUST be
  reversible with a single Undo (Constitution V), and the removal MUST NOT
  fire while an input-method composition is active (FR-063).
- **FR-051**: The user MUST be able to Undo and Redo normal editing operations
  and automatic formatting transformations.
- **FR-052**: Formatting tools SHOULD remain unobtrusive and MAY appear through
  selection controls, contextual menus, keyboard shortcuts, or pointer-hover
  controls rather than a permanent complex toolbar.
- **FR-052a**: Formatting tools MAY appear as a contextual popover on
  selection (shown within 200 milliseconds of selection, dismissed on
  deselect or click-away), as keyboard shortcuts (documented in Help), or
  as pointer-hover controls in the upper area (per FR-031). A permanent
  formatting toolbar MUST NOT be displayed. The contextual popover MUST
  contain at most 8 visible controls.
- **FR-053**: Rich text MUST store only formatting capabilities explicitly
  supported by the application; unsupported or private attributed-string
  properties MUST NOT silently enter the durable format.

**Markdown input shortcuts**

- **FR-060**: Markdown is an input convenience, not a source-editing mode. The
  editor MUST recognize `# ` (heading), `- ` (bulleted item), `- [ ] ` (todo
  item), `**text**` (bold), `*text*` or `_text_` (italic), `~~text~~`
  (strikethrough), backticked inline code, and triple-backtick code blocks with
  an optional language label.
- **FR-061**: Line-level patterns MUST convert when the user completes the
  prefix with a space or confirms the line; inline patterns MUST convert after a
  valid closing delimiter; conversions MUST be finalized when the insertion
  point leaves the range or the user confirms the line.
- **FR-062**: A single Undo MUST restore the exact Markdown syntax and
  formatting state that existed before an automatic conversion.
- **FR-063**: Automatic conversion MUST NOT corrupt Chinese input, marked-text
  composition, mixed Chinese and English text, emoji, or partially entered
  syntax.

**Todo items**

- **FR-070**: The user MUST be able to create, mark complete/incomplete, drag to
  reorder, indent as a subtask, un-indent, edit, and delete todo items;
  completing adds a visible completed state and strikethrough.
- **FR-071**: Every todo item MUST have a stable identity independent of its
  text, preserved when two todos share identical text, when text changes, when
  reordered, when updated from a widget, and when notes synchronize between
  devices.
- **FR-072**: The first release MUST NOT require due dates, reminders, priority
  levels, recurring tasks, assignees, or automatic movement of completed items.
- **FR-072a**: Todo nesting depth MUST be bounded at a maximum of 6 levels.
  The editor MUST disable the indent action when the active todo is already
  at depth 6, and the data model + synchronization validation MUST reject
  any todo hierarchy deeper than 6 levels. Depth is counted from a top-level
  todo at depth 1; a subtask of a top-level todo is depth 2, and so on.
  This bound keeps the sticky-note editor simple (Constitution I) while
  supporting realistic subtask hierarchies, and makes indent/outdent
  behavior and validation objectively testable.
- **FR-072b**: The editor and note-card surfaces MUST gracefully handle
  notes containing 100 or more todo items without perceptible lag (SC-004,
  SC-006). The todo block view in the editor MUST use virtualized/lazy
  rendering so only visible todo rows are realized, and the underlying
  scroll MUST remain smooth for arbitrarily long todo lists. The note card
  (FR-020) MUST display todo completion progress as "completed/total"
  (e.g. "12/45"); when the total exceeds 99, the card MUST display "99+
  completed" to avoid width overflow while preserving the progress signal.
  Synchronization MUST handle large todo payloads without special chunking
  (the canonical note envelope already carries the full block list), but
  encryption/decryption of such payloads MUST remain off the main actor
  (Constitution XI). This makes the large-todo-list edge case objectively
  testable (CHK064) and prevents pathological notes from degrading the
  library or editor.

**Code blocks**

- **FR-080**: A multiline code block MUST provide monospaced display, preserved
  spaces/tabs/line breaks, a copy button, an optional language label, and
  readable presentation of long lines via user-toggleable wrapping (default
  on) or horizontal scrolling.
- **FR-081**: Copying a code block MUST copy only the code contents.
- **FR-082**: The initial product MUST NOT include syntax highlighting,
  language detection, execution, line numbers, or code formatting; inline code
  remains part of normal text.

**Clipboard images and screenshots**

- **FR-090**: When an image is pasted from the clipboard, the application MUST
  preserve an embedded copy and MUST allow viewing, a larger view, copy, drag
  out, save elsewhere, and removal; embedded clipboard images MUST participate
  in optional encrypted synchronization.
- **FR-090a**: Assets (original images, 256px thumbnails per FR-094a, and
  captured-application icons) MUST be synchronized as independent encrypted
  objects — never bundled inside an encrypted note envelope. Each asset
  object MUST carry a SHA-256 integrity hash (Constitution IV) used for both
  dedup and corruption detection. Each asset object MUST be independently
  retried on partial upload/download failure (Constitution VIII), and a
  failed asset upload MUST NOT block synchronization of the note metadata
  that references it. The sync state for a note referencing a not-yet-
  uploaded asset MUST be recorded as `partialAssetSyncFailure` (or
  equivalent) so that the asset is retried independently on a subsequent
  sync run without re-encrypting or re-uploading the already-succeeded note
  metadata. This makes large-asset sync resumable and the partial-failure
  recovery path objectively testable.
- **FR-090b**: The application MUST enforce explicit scale limits so
  performance and synchronization behavior have deterministic bounds
  (Constitution XI): (a) a single asset (pasted clipboard image or
  screenshot original) MUST NOT exceed 50 MB of raw bytes, and its longest
  pixel edge MUST NOT exceed 16,384 pixels after capture/paste
  normalization; (b) a single note's structured content (the canonical
  note envelope before asset payloads, per FR-031a) MUST NOT exceed 5 MB.
  When an operation would exceed an asset limit (e.g. pasting an
  oversized image), the application MUST reject that specific insertion
  with a clear localized explanation, MUST NOT write any partial asset,
  and MUST NOT affect other notes or the rest of the current note.
  When a content change would exceed the note-content limit, the
  application MUST refuse to persist it and MUST preserve the last valid
  saved state, explaining the limit to the user. The limit constants MUST
  be documented and covered by automated tests; assets within the limits
  MUST still sync as independent objects (FR-090a) and MUST NOT be decoded
  at full resolution for card-grid or widget rendering (FR-094a).
- **FR-091**: The user MUST be able to capture a screen region into a new note,
  select an application window into a new note, add a region screenshot to an
  existing note, and add a window screenshot to an existing note.
- **FR-092**: Screenshots MUST be static snapshots; the product MUST NOT
  continuously record, monitor, or automatically refresh another application's
  window.
- **FR-093**: For a captured application window, the note MAY preserve
  application name, application icon, window title, capture date and time, the
  original screenshot, a thumbnail, and an optional user caption; a note MAY
  contain multiple screenshot associations.
- **FR-094**: The user MAY select one screenshot as the note card's cover image.
- **FR-094a**: Thumbnails used for note-card covers, card-grid previews, and
  widget rendering MUST be generated with a longest edge of 256 pixels,
  preserving aspect ratio. The 256px longest-edge dimension is the single
  canonical thumbnail size for both card and widget display. Full-resolution
  screenshots and embedded images MUST NOT be decoded for card-grid or
  widget rendering (see SC-008); only the 256px thumbnail participates in
  those surfaces. Thumbnail generation MUST be lazy, off the main actor, and
  MUST produce a stable hash so identical source images dedup to a single
  stored thumbnail.
- **FR-094b**: When a screenshot block that is currently selected as the note
  card's cover (FR-094) is deleted from its note, the application MUST
  nullify `Note.coverScreenshotBlockId` within the same database transaction
  as the block deletion, so that no dangling reference is ever observable
  (Constitution IV data integrity). This MUST be enforced at the persistence
  layer via the v1 schema foreign key `ON DELETE SET NULL` behavior (the
  canonical `Note.coverScreenshotBlockId → Block.id` FK with
  `DEFERRABLE INITIALLY DEFERRED` per tasks.md T152) AND reinforced by the
  repository delete-block path. The note card MUST gracefully fall back to
  a no-cover state (no thumbnail shown in the cover slot). No additional
  user confirmation or toast is required for this case, because cover
  selection is a display attribute rather than user content, and the
  fallback is non-destructive. This makes the cover-deletion edge case
  objectively testable (CHK040) and guarantees transactional consistency.
- **FR-095**: Selecting a screenshot MUST open a large viewer supporting zoom,
  actual size, fit-to-window, copy, drag out, Save As, delete association, edit
  caption, and navigation between screenshots of the same note; the viewer MUST
  NOT automatically start, switch to, or control the original application.
- **FR-096**: Drawing, annotation, arrows, highlighting, and image markup MUST
  NOT be in scope.

**File-reference workflow**

- **FR-100**: Files dragged from Finder MUST be represented as references, not
  copied into the application and not uploaded as attachments; the card MUST
  display file name, file icon/type, approximate size when available, date
  added, availability status, and the Mac where the reference was created.
- **FR-101**: The user MUST be able to open the referenced file when available,
  reveal it in Finder, copy its path when available, drag it from the note into
  Finder or another application, relink it when the original cannot be found,
  remove the card, and explicitly move the original file to a user-selected
  location.
- **FR-102**: Ordinary drag-out MUST copy the file and MUST NOT silently move or
  delete the original; moving the original MUST require an explicit command,
  destination selection, and confirmation.
- **FR-103**: When a file is missing or unavailable, the application MUST
  preserve the card and offer relinking, and MUST NOT automatically scan the
  entire filesystem or silently delete the card.
- **FR-104**: File contents MUST NOT be synchronized; on another Mac, a
  synchronized card MAY show its generic metadata and explain that the original
  is only linked on another device, and the user MAY relink it to a local file.
- **FR-105**: Security-scoped access for long-term local file access MUST remain
  device-local; bookmark data and absolute local paths MUST NOT be synchronized.

**Widgets**

- **FR-110**: The product MUST provide multiple widget forms: a small widget for
  one user-selected note, a small widget for the most recently modified eligible
  note, a medium widget for multiple recent notes, a medium widget for todos
  from a selected note, a large widget for a broader overview, and a
  quick-create action.
- **FR-110a**: Widget content MUST be refreshed change-driven: whenever local
  data affecting a widget changes (note created, edited, deleted, trashed,
  restored, todo toggled, widget-eligibility changed, conflict copy
  created), the main application MUST proactively trigger a timeline
  refresh for the affected widget forms (WidgetKit timeline reload). The
  widget itself MUST NOT poll the database on a fixed high-frequency
  schedule — no fixed polling interval shorter than the platform's default
  timeline behavior, consistent with SC-006 (no high-frequency polling).
  Widget interactions (FR-111 todo toggles, quick-create) MUST also trigger
  a refresh of the widgets affected by the resulting change. If a change
  occurs while the main application is not running, widgets MAY show
  last-known content until the application next runs or the system
  refreshes its timeline (FR-140a's "temporarily unavailable" status
  applies on read failure).
- **FR-111**: Widgets MAY allow opening a note window, marking an individual
  todo complete or incomplete, creating a new note, and moving between eligible
  recent notes; widgets MUST NOT attempt full rich-text editing.
- **FR-112**: Each note MUST have a setting controlling whether it may appear in
  widgets; when excluded, its title, body, todo text, images, screenshots, and
  summaries MUST NOT appear in widget timelines, previews, placeholders, or
  snapshots.

**Global shortcuts**

- **FR-120**: The user SHOULD be able to configure global shortcuts for
  opening/closing the library, creating a blank note, capturing a region into a
  new note, selecting a window into a new note, creating a note from clipboard
  contents, searching all notes, and showing or hiding open note windows.
- **FR-121**: The application MUST detect shortcut conflicts and MUST NOT
  silently replace an existing system or application shortcut.

**Permissions and graceful degradation**

- **FR-130**: The application MAY use screen-recording permission for region and
  application-window capture, and accessibility permission for future advanced
  identification of the current application window.
- **FR-131**: Permissions MUST be requested only when the user invokes the
  feature requiring them; accessibility permission MUST NOT be requested merely
  because a future feature might use it.
- **FR-132**: If screen-recording permission is denied, ordinary notes MUST
  remain fully usable, screenshot features MUST clearly explain why they are
  unavailable, and the user MUST be able to open the appropriate system settings.
- **FR-133**: If accessibility permission is denied, ordinary notes and manual
  screenshot selection MUST remain usable and only advanced window-identification
  behavior MUST be unavailable.
- **FR-134**: Permission explanations MUST be clear, specific, and non-alarming.

**Local-first behavior**

- **FR-140**: All ordinary product functionality MUST work without a user
  account, an Internet connection, or a synchronization configuration (FR-143,
  FR-190).
- **FR-140a**: Database access (SQLite via GRDB, in WAL mode) MUST use a
  bounded busy timeout of 5 seconds: when a database operation cannot acquire
  a lock because another connection (app or widget) holds it, the operation
  MUST wait up to 5 seconds before reporting a "database busy" condition
  rather than blocking indefinitely or failing immediately. Widget read
  transactions MUST be short enough to complete well within this timeout. If
  a widget read cannot complete within the timeout, the widget MUST report a
  sanitized "temporarily unavailable" status (never a raw error or note
  content) and retry on its next refresh. This makes app+widget concurrent
  WAL access behavior testable and eliminates realistic deadlock risk.
- **FR-141**: The user MUST be able to create, edit, search, delete, restore,
  and view all locally available content while offline; changes MUST save
  automatically.
- **FR-141a**: Automatic saving (FR-141) MUST use a debounce of 500
  milliseconds after the last local content change, decoupled from the
  2-4 second synchronization debounce (FR-152a): once 500 ms elapse
  without further changes, the pending changes MUST be persisted to the
  local database in a single transaction. The chosen value MUST be
  deterministic for a given build. Persistence MUST additionally be
  flushed before window close, note deletion, automatic-removal decisions
  (FR-012), and application quit, so no completed user action loses
  input. Crash-loss contract: after an abnormal process exit, the user
  MUST lose at most the input entered within the last autosave debounce
  window (500 ms plus the in-flight write), and MUST never lose content
  persisted by a completed autosave. Crash recovery MUST be covered by
  automated tests that terminate the process mid-edit and verify
  restoration (Constitution XII). Autosave MUST NOT block typing
  (SC-004a) and MUST NOT require a manual Save command.
- **FR-142**: Network failures MUST NEVER block local editing.
- **FR-143**: The project MUST NOT operate its own cloud service.

**Optional synchronization**

- **FR-150**: The user MAY configure exactly one synchronization repository at a
  time: one WebDAV repository or one S3-compatible repository; S3-compatible
  synchronization MUST allow a configurable endpoint (not restricted to one
  vendor).
- **FR-151**: The user MUST be able to configure the repository, test the
  connection, enable or disable automatic synchronization, trigger manual
  synchronization, view the last successful synchronization time, view
  actionable errors, and remove local configuration without deleting local
  notes.
- **FR-152**: Synchronization SHOULD occur through a combination of a short
  delay after content changes, periodic synchronization, application startup,
  application shutdown when practical, manual synchronization, and network
  reconnection.
- **FR-152a**: The "short delay after content changes" in FR-152 MUST be
  implemented as a debounce window of 2 to 4 seconds after the last local
  change. The sync engine MUST NOT fire while local edits are still arriving
  within the window; it MUST fire once 2-4 seconds have elapsed since the
  most recent change. The exact point within the 2-4 second range is an
  implementation choice, but the chosen value MUST be deterministic for a
  given build (no random jitter that could starve sync indefinitely). This
  debounce MUST NOT block local editing (per FR-153) and MUST be cancelable
  by a manual-sync trigger, application shutdown, or network change. The
  bounded range makes the sync-trigger observable in tests without pinning a
  flaky exact-millisecond value.
- **FR-153**: Local editing MUST NOT wait for synchronization to complete.
- **FR-154**: The first release MUST support one repository at a time and MUST
  NOT mirror simultaneously to multiple repositories. Replacing an existing
  repository configuration with a new one (e.g., WebDAV→S3, or a different
  endpoint) MUST require an explicit user action with a clear warning and
  confirmation. Upon confirmed replacement, local notes MUST be preserved,
  the new vault MUST bootstrap fresh, and the application MUST NOT
  automatically delete the prior repository's remote data — server-side
  cleanup of the old vault remains a manual user responsibility.

**End-to-end synchronization privacy**

- **FR-160**: All synchronized note content and meaningful metadata MUST be
  encrypted on the user's Mac before upload.
- **FR-160a**: "Meaningful metadata" that MUST be encrypted before upload is
  positively enumerated as: (a) all user-content fields listed in FR-161;
  (b) the semantic type of each remote object (note, block, asset,
  tombstone, manifest); (c) structural metadata (block ordering, todo
  nesting and completion state, note-to-block composition, cover-screenshot
  selection, manual sort-key position); (d) note appearance and behavior
  choices (color, transparency, text size, Always-on-Top state,
  widget-eligibility setting); and (e) version-lineage fields that reveal
  editing patterns (parentVersionId, lastModifiedDeviceId, semantic
  modifiedAt distinct from upload time). Any new field added to a
  synchronized object MUST be evaluated against this enumeration; if it
  reveals user content, structure, or behavior, it MUST be encrypted.
- **FR-160b**: The following remote-observable information is an accepted,
  non-violating leakage bound and MUST NOT be treated as a privacy gap:
  random or otherwise opaque remote object identifiers, object byte sizes,
  object modification/upload times as recorded by the remote provider,
  network addresses of the connecting client, and access timing. These are
  inherent to any storage protocol and cannot be eliminated without
  abandoning remote synchronization; the encryption design MUST ensure they
  reveal no user content, structure, or behavior beyond coarse object count
  and volume.
- **FR-160c**: The Argon2id key-encryption-key derivation (per Constitution
  VII) MUST use parameters no weaker than the following production minimums:
  memory cost ≥ 19456 KiB (19 MiB), iteration count ≥ 2, and parallelism
  (lanes) ≥ 1. These values follow OWASP-recommended Argon2id guidance and
  MUST be reviewed against contemporary guidance at each release. The
  `vault-bootstrap.schema.json` minimums (memoryKiB ≥ 8, iterations ≥ 1,
  parallelism ≥ 1) exist ONLY to permit deterministic unit-test fixtures
  that exercise envelope parsing without paying the full derivation cost;
  production vault bootstrapping MUST reject parameter sets weaker than the
  production minimums above. Parameter values used at vault creation MUST be
  stored alongside the wrapped master key so future unlocks reproduce the
  derivation exactly.
- **FR-160d**: "Fail closed" (per Constitution VII and FR-160) MUST be
  triggered by each of the following inputs, which constitute the required
  fail-closed test-vector list: (a) wrong synchronization password supplied
  at unlock; (b) ciphertext modified after encryption (bit-flip, truncation,
  or extension); (c) invalid or mismatched AES-GCM authentication tag;
  (d) mismatched object identifier (ciphertext encrypted for object A
  presented as object B); (e) mismatched object type (note ciphertext
  presented as a block, asset, or tombstone, or any other type
  substitution); (f) mismatched vault identifier (ciphertext from vault X
  presented to vault Y); (g) unsupported or unexpected envelope schema
  version; (h) corrupted or truncated envelope structure that fails to
  parse. For every input in this list, the application MUST reject the
  object without writing any local data, without accepting the remote object
  as valid, and without silently overwriting a local version. Each input
  MUST be covered by a deterministic encryption test vector (per
  Constitution VII's cryptographic-test requirement). The list is
  exhaustive for the initial release: any newly introduced envelope field
  or context dimension MUST add a corresponding fail-closed input and test
  vector in the same change.
- **FR-160e**: Wrong-password unlock attempts MUST NOT be rate-limited,
  throttled, or lockout-bounded by the application. Every wrong-password
  attempt MUST fail closed (per FR-160d (a)) and MUST NOT cache the
  supplied password or derived key. Brute-force resistance MUST rely
  entirely on the Argon2id production minimums in FR-160c (memory cost
  ≥ 19456 KiB, iteration count ≥ 2, parallelism ≥ 1), which make each
  attempt computationally expensive. The application MUST NOT introduce
  account-lockout, timed backoff, or attempt-counting mechanisms, because
  such mechanisms could be used to denial-of-service a legitimate user
  in this local-first, no-account architecture, and because the Argon2id
  KDF cost itself serves as the rate limiter. This makes unlock
  failure-handling objectively testable: any number of wrong-password
  attempts yields the same fail-closed behavior with no state
  accumulation.
- **FR-161**: The remote service MUST NOT be able to read note titles, note
  bodies, todo text, code-block contents, file-reference names, application
  names, window titles, screenshot captions, device display names, or the
  semantic type of each remote object; remote object names MUST NOT reveal
  contents.
- **FR-162**: Users MUST configure synchronization on each Mac with the same
  synchronization password.
- **FR-162a**: The application MAY offer an optional "remember unlocked vault
  on this Mac" convenience. When enabled, the remembered unlock MUST persist
  across application launches until the user logs out, restarts the Mac, or
  explicitly locks the vault. The remembered key MUST be stored in Keychain
  and MUST be cleared on explicit lock. The application MUST NOT behave as a
  login-item-bound daemon that keeps the vault unlocked across system
  restarts. Forgetting the synchronization password remains unrecoverable
  regardless of this setting (per FR-163). At application launch with
  auto-synchronization enabled: (a) if "remember" is enabled AND the Mac has
  not been restarted since the remembered unlock was stored (verified by
  comparing the system boot timestamp against the timestamp recorded at
  remember-time), the application MUST silently restore the unlocked vault
  state from Keychain and trigger startup synchronization per FR-152a
  (subject to its debounce window) without prompting the user; (b) if
  "remember" is disabled, OR the Mac has been restarted since the remembered
  unlock, OR the user explicitly locked the vault, the application MUST
  prompt the user to enter the synchronization password before any
  synchronization occurs.   The boot-timestamp comparison makes the
  "restart clears remember" rule (FR-162a) objectively testable and
  eliminates reliance on login-item or daemon behavior to detect restarts.
  When the user toggles "remember unlocked vault" from enabled to disabled
  while the vault is currently unlocked: the application MUST immediately
  remove the remembered key from Keychain (so future application launches
  will not silently restore the unlock), but MUST preserve the current
  unlocked vault state in memory until the user explicitly locks the vault
  or the application exits. The application MUST NOT force a re-prompt for
  the synchronization password merely because the "remember" setting was
  toggled off — explicit lock remains a separate, intentional user action.
  This makes the toggle's effect testable: immediate Keychain clearance +
  no surprise re-authentication for the current session.
- **FR-163**: The product MUST clearly explain that forgetting the
  synchronization password may make the encrypted remote data permanently
  unrecoverable and that neither the developer nor the storage provider can
  restore it.
- **FR-164**: Changing the synchronization password SHOULD NOT require
  unnecessarily uploading all unchanged content again.
- **FR-165**: Credentials and unlocked secrets MUST NEVER appear in logs or
  ordinary exported diagnostics.

**Synchronization conflicts and deletion**

- **FR-170**: The application MUST NEVER silently overwrite one valid version of
  a note with another divergent version.
- **FR-171**: When two Macs independently modify the same note from a common
  earlier version, one version MUST remain the original note and the other MUST
  be preserved as a new conflict-copy note, clearly labeled with origin and time
  information, with text, todos, code blocks, images, screenshots, and
  file-reference metadata preserved; the user MUST be able to compare, edit, or
  delete either version.
- **FR-172**: The initial version MUST NOT attempt automatic character-level or
  block-level merging.
- **FR-173**: If one device deletes a note while another offline device
  modifies it, the modified content MUST be preserved as a recovered conflict
  copy rather than being silently lost or silently resurrecting the deleted
  original.
- **FR-174**: A deletion record MUST remain available for 30 days so an offline
  Mac cannot immediately recreate a note that another Mac deleted; after the
  retention period, deleted content MAY be cleaned up only when doing so does
  not violate synchronization safety. When a device returns online after its
  local tombstone has aged past 30 days and the remote tombstone was already
  purged by another device's cleanup, the returning device MUST NOT
  auto-delete any local content. It MUST reconcile against available remote
  deletion history: if no remote tombstone is found for a note, the device
  treats the note as "no remote deletion record found" and preserves it
  locally. Notes that the user deleted on the returning device MUST NOT be
  re-uploaded unless the user explicitly restores them. The application MUST
  inform the user that some synchronization history has aged out.
- **FR-175**: The user MUST be able to distinguish a note in local Trash, a
  permanently deleted note, a recovered conflict copy, and a normal active note.

**Accessibility and international text**

- **FR-180**: The application MUST support VoiceOver, keyboard navigation,
  meaningful accessibility labels and states, Increased Contrast, Reduce Motion,
  light and dark appearance, Chinese and English text, mixed Chinese and English
  input, font fallback, emoji, and input-method marked text and composition.
- **FR-180a**: The application's user-facing interface MUST be localized in
  Simplified Chinese (zh-Hans) and English (en) for the initial release,
  switching automatically to follow the system language preference. All
  user-visible strings (menus, buttons, tooltips, toasts, settings, Help,
  accessibility labels, and error/sync status text) MUST come from the
  localization catalogs; note content is never translated. Localization MUST
  be complete enough that the SC-011 core capture loop is operable in either
  language, and the deletion toast announced by VoiceOver (FR-009a) MUST
  respect the active locale.
- **FR-181**: All essential actions MUST be possible without relying
  exclusively on pointer hover.
- **FR-182**: A completed todo MUST be communicated by more than color alone,
  and custom colors and transparency MUST NOT make text or controls unreadable.
  "Unreadable" is quantified by the WCAG 2.2 AA thresholds in FR-042 (≥4.5:1
  normal text, ≥3:1 large text/controls); the application MUST enforce those
  thresholds by auto-adjusting foreground color when a custom color +
  transparency combination would otherwise fall below them.

**Privacy and trust**

- **FR-190**: The product MUST contain no advertising, no analytics, no
  behavioral tracking, no collection of note content, no developer-operated
  account system, and no developer-operated synchronization server.
- **FR-191**: User-facing diagnostics and exported logs MUST NOT contain note
  content, file names, file paths, window titles, credentials, passwords,
  encryption secrets, or other private user data. The user-exportable
  diagnostic bundle (the artifact a user may save and share for support)
  MUST contain only the following positively-enumerated fields: application
  version, OS version, local schema version, sync provider type (WebDAV or
  S3 — never the endpoint URL, hostname, or credentials), normalized
  provider error categories with timestamps for the last 30 days (never
  raw server responses or bodies), synchronization run counts and
  durations (never payloads or object names), aggregate counts of notes /
  blocks / assets (never titles, summaries, captions, or content), vault
  state (locked or unlocked — never the password or derived key), and
  permission statuses (screen-recording / accessibility granted-or-denied
  booleans). Any field not in this list is excluded by default.

### Key Entities *(include if feature involves data)*

- **Note**: The unit a user creates, edits, and retrieves. Carries an optional
  manual title (distinct from any generated summary), a color, transparency,
  text size, Always-on-Top state, window size and preferred position, sorting
  position under manual order, widget-eligibility setting, last-modified time,
  and a current lifecycle state (active, in Trash, permanently deleted,
  recovered conflict copy). It contains blocks of content.
- **Block**: A piece of content within a note. Categories: rich text, todo,
  code, file reference, embedded image, screenshot. Blocks are ordered and
  individually identifiable.
- **Todo Item**: A block with stable identity independent of its text,
  supporting complete/incomplete state, nesting as a subtask, and reordering.
  Identity is shared across the main app, widgets, synchronization, and
  conflict handling.
- **Code Block**: A block preserving exact whitespace and line breaks with an
  optional language label, copyable as code contents only.
- **File Reference**: A block pointing to a local file by reference (not a
  copy), carrying device-local access state plus generic synchronizable
  metadata (display name, content type, approximate size, origin device, added
  date). File contents are not synchronized.
- **Embedded Image**: A block holding an embedded copy of a pasted clipboard
  image; participates in encrypted synchronization.
- **Screenshot Association**: A block holding a static screenshot plus optional
  origin metadata (application name, icon, window title, capture time), a
  thumbnail, an optional caption, and cover-selection state. A note may have
  several; one may be the card cover.
- **Trash Entry / Tombstone**: A record representing a deleted note, retained
  for 30 days to enable restoration locally and safe deletion propagation
  between devices.
- **Conflict Copy**: A note created to preserve a divergent or
  delete-versus-edit version, labeled with origin and time, distinguishable from
  an active note.
- **Synchronization Repository**: The configuration for exactly one WebDAV or
  S3-compatible endpoint, with connection state, last-successful-synchronization
  time, and actionable error status; one at a time.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The menu-bar library opens within 150 milliseconds of clicking the
  icon when the application is already running (warm).
- **SC-002**: Initial note-card content is visible within 300 milliseconds of
  the library opening.
- **SC-003**: A new independent note window is presented within 200 milliseconds
  of the create action.
- **SC-004**: Typing into a note shows no visible lag during normal editing,
  including with Chinese input-method composition active.
- **SC-004a**: "No visible lag" in SC-004 means keystroke-to-glyph latency
  MUST be below 16 milliseconds (one frame at 60 Hz) during normal editing,
  including with Chinese input-method composition active. This is measurable
  via Instruments or signposts.
- **SC-005**: Search across 10,000 primarily textual notes returns matching
  results within 200 milliseconds as the query changes.
- **SC-006**: While the application is idle with no user action, it shows no
  sustained processor use and no high-frequency polling when synchronization is
  inactive.
- **SC-007**: During a network outage, the user can create, edit, search,
  delete, and restore notes with no degradation relative to online use.
- **SC-008**: Opening a note containing large screenshots does not freeze the
  interface; full-resolution images are not decoded for the card grid, which
  uses thumbnails.
- **SC-009**: 100% of acceptance scenarios for each P1 user story are
  independently demonstrable without any P2 or P3 feature configured.
- **SC-010**: No exported diagnostic or log contains note content, file names or
  paths, window titles, credentials, passwords, or encryption secrets.
- **SC-011**: A user can complete the core capture loop — open library, create
  note, type, close, reopen, find via search — in under 30 seconds without
  consulting help documentation.

## Assumptions

- The product targets macOS 26 and later; features unavailable below that
  version are out of scope.
- "macOS Sticky Notes" is a working title only and will be replaced before any
  public release; no brand, trademark, or final name decisions are made in this
  specification.
- Each user uses the product on one or more of their own personal Macs;
  synchronization is between a single user's devices, not across users.
- The user is responsible for obtaining and configuring their own WebDAV or
  S3-compatible repository; the project provides no hosted service (FR-143,
  FR-190).
- Users understand that forgetting the synchronization password makes remote
  encrypted data unrecoverable; the product communicates this clearly rather
  than assuming it (FR-163).
- The system widget platform supports the widget forms described; where a form
  is unavailable on a given OS configuration, the product provides the closest
  available form and degrades gracefully.
- Global shortcuts and Dock behavior follow standard macOS capabilities and
  permissions; where the system restricts an action, the product explains the
  restriction rather than working around it insecurely.
- OCR is not part of the initial release (see Non-goals); until then,
  screenshot text is not searchable.
- External dependencies include the macOS platform and (optionally) a
  user-supplied WebDAV or S3-compatible endpoint over HTTPS; there is no
  dependency on any developer-operated service (FR-143, FR-190).
