# 2026-10-27: menus and palette redesign

## What

Every popup menu (right-click, tab, profile dropdown, Settings row) now goes through one module,
`src/apprt/win32/fancy_menu.zig`. It keeps a real Win32 menu and owner-draws the rows: a theme
card with DWM rounded corners and border, an accent top edge, Fluent icons, a rounded highlight,
and keycap shortcuts. The palette list uses the same card, highlight and keycaps. Before this, a
dark Najm opened light, classic Windows menus.

## Mistakes

- **The first capture script sent keys with `keybd_event`.** Those go to whatever window has
  focus, and when the test window had lost foreground, the Menu key, arrows and Escape went to
  the owner's own terminal. Keys now go by `PostMessage` to the test window's focused child.
- **The first capture launch forwarded into the owner's running Najm** through single-instance
  IPC, and no test window appeared. The capture config sets `single-instance = false`.
- **Screen-grabbed the palette** and got whatever was on top. `PrintWindow` captures the test
  window itself.
- **Fixed the menu text at 14 px,** which would have shrunk text for anyone with Windows "Text
  size" raised. Native menus honour that setting. Sizes now come from the system menu font at the
  window's DPI, with 14 px as the floor (`metricsFor`, tested at 225%).
- **`@max` on a comptime-known value narrowed to `u4`** and overflowed in a default field
  initialiser. Annotate the result type.
- **Long key names** ("backslash") overflowed the palette's shortcut column and fell back to
  plain text. They now map to the printed symbol.

## What worked

- Keeping the native menu and drawing only the rows. Keyboard navigation, submenus, outside-click
  dismissal, the system animation and MSAA names (via `MSAAMENUINFO` in the item data) all came
  for free. A custom popup window would have had to rebuild each of them.
- One shared module from the start. The palette took the keycaps and highlight from it, so the
  two surfaces match by construction.
- Before and after captures in both themes, from a throwaway portable copy.

## Rules

- A new popup menu calls `fancy_menu.track`, never `TrackPopupMenu` directly.
- Never send synthetic input through the global queue on the owner's machine. Post to one window.
- Sizes on chrome text follow the system font and its scaling, with a floor, not a fixed px.
