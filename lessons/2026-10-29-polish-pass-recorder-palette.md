# Polish pass: pty recorder, palette accent, context menu

## What

An audit of the last ~25 commits (chrome and Settings UI, terminal rendering,
paint performance), fixed on `worktree-polish-pass`:

- The pty recorder (`src/termio/pty_record.zig`) records inside the renderer
  lock, records the pre-thread resize, writes once per read, refuses a share
  or device directory, and stops instead of truncating when a rotation rename
  fails.
- Reselecting the accent already previewed in the palette applies nothing
  (typing reselected it every key and rebuilt every window's fonts).
- The Settings Accent dropdown reads the system accent only for Match Windows.
- An accent row's subtitle stops before its swatch in a narrow palette.
- The terminal right-click menu re-finds its host after the menu loop.
- Moving between accent rows keeps the chrome fonts and the terminals'
  config (`Host.PaletteSwap.accent`, `App.reconfigureThemeWith`).
- The terminal, tab and new-tab menus have Windows access keys, unique per
  menu (`fancy_menu.duplicateMnemonic`).
- The Terminal theme field's chevron lights under the pointer.
- A popup menu row clamps to 220-560 logical px (`fancy_menu.rowWidth`).

## Mistakes

- The recorder shipped with its own mutex and was taken as ordered. A lock
  that orders the file is not the lock that orders the terminal: the two
  threads met at `renderer_state.mutex`, after both had already written.
- A tool built to catch a race was itself slow on the reader (one WriteFile
  per 4 KiB line), which shifts the timing of the race it hunts.
- First pass deferred three items as "needs a visible run"; the owner wanted
  end to end. Each was then done by finding the seam a test reaches (a
  marker font handle, a pure paint helper, a pure width clamp) instead of
  waiting for a screen.
- One audit finding (the palette list reading the registry every paint) was
  already a deliberate once-per-paint read; it was checked against the code
  and dropped, not "fixed".

## What worked

- Three narrow read-only audits, then every finding re-read in the code
  before an edit. One of 17 findings did not hold up; the rest were fixed
  or deferred below.
- Reusing the guard `showTabContextMenu` already had instead of designing a
  new one for `showContextMenu`.

## Rules

- A recorder of terminal input records under the lock that changes the
  terminal (conpty.md, 2026-10-29).
- A visual fix without a local screen still gets a test at the closest
  seam: the paint decision as a pure function, the handle identity, the
  clamp.
- Not done, by choice: the installed-themes list is still read from disk on
  each palette and theme-dropdown open (a few ms warm, under a frame); a
  shared cache needs invalidation on a dropped-in theme file and changes who
  frees the palette's list. Measure first. The theme chevron still has no
  UIA ExpandCollapse; Alt+Down and F4 open it.
