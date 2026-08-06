# Feature Specification: macOS Sticky Notes

**Feature Branch**: `001-sticky-notes-app`

**Created**: 2026-08-06

**Status**: Draft

**Input**: User description: "Build a minimalist, native sticky-notes application for macOS 26 and later. Use 'macOS Sticky Notes' only as a working title; do not invent a final product or brand name."

> "macOS Sticky Notes" is a working title only. It is not a final product or
> brand name. Throughout this specification it is used as a placeholder label
> for the product.

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

- A user clicks the menu-bar icon while the library window is already open; if
  the library is the focused window it is dismissed, otherwise it is focused,
  and a second instance is never opened (see FR-009).
- The user disconnects the only display attached to a Mac running a note window
  that was positioned on it; the window must reappear on the main display and
  remember its disconnected-display position for return.
- The user pastes rich text containing unsupported formatting from another
  application; only supported formatting capabilities may persist (unsupported
  or private attributed-string properties must not silently enter the durable
  format).
- A todo item is toggled complete from a widget on one Mac while the note is
  open and being edited on another; todo identity must remain stable and the
  change must reconcile without losing either side.
- The user changes the synchronization password; this should not require
  uploading all unchanged content again.
- The user captures a screenshot of an application window whose title or icon is
  unavailable; the note preserves whatever metadata is available and still
  stores the static screenshot.
- The user drags out a file reference whose original has since been moved;
  ordinary drag-out must copy when possible and must never silently move or
  delete the original.
- The system is in increased-contrast mode with a custom note color and high
  transparency; text and controls must remain readable.
- A newly created note with only whitespace is closed; it may be auto-removed,
  but a note that previously had content and is later emptied must not be
  auto-deleted.
- Two todo items have byte-identical text; each must remain independently
  identifiable and toggleable.

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
- **FR-008**: The Dock icon MUST be enabled by default and MAY be disabled by
  the user in Settings; when disabled, Settings, Help, About, synchronization
  status, and Quit MUST remain reachable from the menu-bar interface.
- **FR-009**: Clicking the menu-bar icon while the library window is already
  open MUST focus the library if it is not already the focused window, and MUST
  dismiss the library if it is already the focused window; a second library
  window MUST NEVER be opened.

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
- **FR-014**: Deleted notes MUST remain recoverable in Trash for 30 days unless
  permanently deleted earlier.

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
- **FR-023**: Search MUST match manual titles, normal text, todo text,
  code-block text, file display names, and screenshot captions, and MUST match
  text recognized from screenshots if OCR is introduced later.
- **FR-024**: Search results MUST update promptly as the query changes.

**Independent note windows**

- **FR-030**: Each note window SHOULD look like a lightweight sheet of note
  paper while retaining normal macOS window behavior.
- **FR-031**: Most window controls SHOULD remain hidden until the pointer enters
  the upper area; that area MUST allow editing an optional title, changing note
  color, changing transparency, changing text size, toggling Always on Top,
  adding a screenshot, adding a file reference, opening additional actions, and
  closing the window.
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
- **FR-041**: Notes MUST support adjustable background transparency while
  keeping text and controls readable.
- **FR-042**: The interface MUST adapt to light mode, dark mode,
  increased-contrast preferences, and custom note colors.
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
- **FR-051**: The user MUST be able to Undo and Redo normal editing operations
  and automatic formatting transformations.
- **FR-052**: Formatting tools SHOULD remain unobtrusive and MAY appear through
  selection controls, contextual menus, keyboard shortcuts, or pointer-hover
  controls rather than a permanent complex toolbar.
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

**Code blocks**

- **FR-080**: A multiline code block MUST provide monospaced display, preserved
  spaces/tabs/line breaks, a copy button, an optional language label, and
  readable presentation of long lines via wrapping or horizontal scrolling.
- **FR-081**: Copying a code block MUST copy only the code contents.
- **FR-082**: The initial product MUST NOT include syntax highlighting,
  language detection, execution, line numbers, or code formatting; inline code
  remains part of normal text.

**Clipboard images and screenshots**

- **FR-090**: When an image is pasted from the clipboard, the application MUST
  preserve an embedded copy and MUST allow viewing, a larger view, copy, drag
  out, save elsewhere, and removal; embedded clipboard images MUST participate
  in optional encrypted synchronization.
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
  account, an Internet connection, a synchronization configuration, or access to
  any developer-operated service.
- **FR-141**: The user MUST be able to create, edit, search, delete, restore,
  and view all locally available content while offline; changes MUST save
  automatically.
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
- **FR-153**: Local editing MUST NOT wait for synchronization to complete.
- **FR-154**: The first release MUST support one repository at a time and MUST
  NOT mirror simultaneously to multiple repositories.

**End-to-end synchronization privacy**

- **FR-160**: All synchronized note content and meaningful metadata MUST be
  encrypted on the user's Mac before upload.
- **FR-161**: The remote service MUST NOT be able to read note titles, note
  bodies, todo text, code-block contents, file-reference names, application
  names, window titles, screenshot captions, device display names, or the
  semantic type of each remote object; remote object names MUST NOT reveal
  contents.
- **FR-162**: Users MUST configure synchronization on each Mac with the same
  synchronization password.
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
  not violate synchronization safety.
- **FR-175**: The user MUST be able to distinguish a note in local Trash, a
  permanently deleted note, a recovered conflict copy, and a normal active note.

**Accessibility and international text**

- **FR-180**: The application MUST support VoiceOver, keyboard navigation,
  meaningful accessibility labels and states, Increased Contrast, Reduce Motion,
  light and dark appearance, Chinese and English text, mixed Chinese and English
  input, font fallback, emoji, and input-method marked text and composition.
- **FR-181**: All essential actions MUST be possible without relying
  exclusively on pointer hover.
- **FR-182**: A completed todo MUST be communicated by more than color alone,
  and custom colors and transparency MUST NOT make text or controls unreadable.

**Privacy and trust**

- **FR-190**: The product MUST contain no advertising, no analytics, no
  behavioral tracking, no collection of note content, no developer-operated
  account system, and no developer-operated synchronization server.
- **FR-191**: User-facing diagnostics and exported logs MUST NOT contain note
  content, file names, file paths, window titles, credentials, passwords,
  encryption secrets, or other private user data.

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
  S3-compatible repository; the project provides no hosted service.
- Users understand that forgetting the synchronization password makes remote
  encrypted data unrecoverable, and the product must communicate this clearly
  rather than assume it.
- The system widget platform supports the widget forms described; where a form
  is unavailable on a given OS configuration, the product provides the closest
  available form and degrades gracefully.
- Global shortcuts and Dock behavior follow standard macOS capabilities and
  permissions; where the system restricts an action, the product explains the
  restriction rather than working around it insecurely.
- OCR is not part of the initial release but may be introduced later solely to
  expand search; until then, screenshot text is not searchable.
- External dependencies include the macOS platform and (optionally) a
  user-supplied WebDAV or S3-compatible endpoint over HTTPS. There is no
  dependency on any developer-operated service.
