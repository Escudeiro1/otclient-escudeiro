# dev_uiinspector — live UI inspector/editor

Inspect and edit the **running** client UI in place. Unlike `dev_otui` (which
loads a `.otui` into a blank stage), this points at whatever is already on
screen — game panels, the options window, HUD widgets.

Open the panel with the top-right **UI Inspector** button. Toggle edit mode with
**Ctrl+Alt+I** (or the *Edit mode* checkbox).

## Use

1. Turn on edit mode.
2. **Ctrl+Alt+click** a widget on screen. A green box marks it; moving the mouse
   with Ctrl+Alt held shows a yellow hover box. Normal clicks are untouched.
3. The property panel lists the widget's properties. Each row shows the editable
   value and, dimmed, the widget's current live value (`now: …`).
4. Change a value, press Enter or **Apply (live)** → the change is pushed onto
   the running widget with `mergeStyle`. **Instant, no reload.**
5. **Save to file** writes the change back into the widget's source `.otui`
   (`.bak` written first, then the file is read back and compared). Save does
   **not** reload anything — the live view already shows the change; the file
   just takes effect the next time that screen loads.

## When Save is disabled

Save needs the widget to map cleanly to a node in an `.otui` file. It can't when
the widget was created by Lua, is a list/table row, a tab body, a child that
comes from a style *class* rather than the instance file, or an HTML widget.
Those show a red banner and are **live-edit only** — Apply still works, Save
doesn't. The mapping is validated level by level (widget style name vs file tag);
any disagreement disables Save rather than risk writing to the wrong node.

## Source file resolution

The owning `.otui` of a window is found by, in order: a registry populated by
wrapping `g_ui.loadUI`/`g_ui.displayUI` (windows opened after this module
loads); a guess from the window's style/id (windows that already existed); a
remembered manual mapping; or the **Set source** field where you type the path
yourself (remembered per window in `g_settings`).

## Not in this version

Drag-to-move, resize handles, anchor editing, guides, a widget tree. `anchors.*`
and `@…` rows are read-only. `mergeStyle` can't clear a property, so a removed
row only takes effect on Save. `@onClick` and friends can't be rebound live.

## Notes

- `otml.lua` here is a vendored copy of `modules/dev_otui/otml.lua` (global
  renamed `UiInspectorOtml`), so the two tools never share state.
- The module is `reloadable: false` so the file watcher can't tear down its
  capture layer / `g_ui` wrappers mid-session. Editing this module's own files
  needs `g_modules.getModule('dev_uiinspector'):reload()` or a client restart.
