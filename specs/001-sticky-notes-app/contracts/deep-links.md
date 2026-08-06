# Deep Link Routing Contract

**Status**: Versioned | **Date**: 2026-08-06 | **Plan**: [../plan.md](../plan.md)

Defines the URL routing contract for opening notes and triggering actions from
widgets, global shortcuts, and external invocations. The scheme name is a
**placeholder** until the project chooses a final bundle identifier. No final
brand name is invented here.

## URL scheme

```
stickynotes://<action>/<parameters>
```

`stickynotes` is a placeholder scheme. The real scheme is derived from the final
bundle identifier at build configuration time. Replace all occurrences when the
final identifier is chosen.

## Routes

| Route | Purpose | Parameters | Behavior |
|-------|---------|------------|----------|
| `stickynotes://note/<note-uuid>` | Open or focus one independent window for a note | `<note-uuid>` = stable note UUID | If the note exists and is active/recoverable, focus its existing window or open exactly one window (FR-005). If already open, focus; never duplicate. If trashed/permanently deleted, open Trash focused on that note (or a localized "not available" notice). |
| `stickynotes://new` | Create a blank note | none | Create a note and open its window. Empty notes auto-discard on close if never meaningful (FR-012). |
| `stickynotes://new?source=clipboard` | Create a note from clipboard contents | optional `source=clipboard` | Create a note and, if the clipboard holds an image, embed it; if it holds text, insert it as rich text. |
| `stickynotes://new?source=region` | Capture a screen region into a new note | optional `source=region` | Invoke region capture; on completion create a note with the screenshot. On cancellation, no note/asset is created. |
| `stickynotes://new?source=window` | Select an application window into a new note | optional `source=window` | Invoke the system content-sharing picker; on selection create a note with the static screenshot. |
| `stickynotes://search` | Open the menu-bar library focused on search | none | Open/focus the menu-bar library with the search field focused (per FR-009 re-click semantics). |
| `stickynotes://todo/<todo-uuid>/toggle` | Toggle a todo item by stable UUID | `<todo-uuid>` = stable todo identity | Toggle the todo's complete/incomplete state by UUID (never by text). Used by widgets. Must find the owning note; if the note is widget-ineligible or missing, no-op with a sanitized diagnostic. |
| `stickynotes://trash` | Open the menu-bar Trash view | none | Open the library's Trash. |

## Routing rules

- **Invalid UUID**: a route with a malformed or unknown UUID MUST NOT crash; it
  routes to a localized "not available" state and is logged only with a
  sanitized code (no note content).
- **Window uniqueness**: `note/<uuid>` MUST respect the one-window-per-note
  invariant (FR-005). A widget deep link opening a note MUST NOT temporarily
  flip the Dock activation policy to `regular` (FR-008).
- **Widget privacy**: routes MUST NOT surface content of widget-ineligible notes
  in widget previews/placeholders (Principle VI). Deep links target the app,
  not widget snapshots.
- **Scope**: deep links route into the app process only; they do not initialize
  the synchronization engine.
- **Offline**: all routes work fully offline (Principle III).
