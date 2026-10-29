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

## Mistakes

- The recorder shipped with its own mutex and was taken as ordered. A lock
  that orders the file is not the lock that orders the terminal: the two
  threads met at `renderer_state.mutex`, after both had already written.
- A tool built to catch a race was itself slow on the reader (one WriteFile
  per 4 KiB line), which shifts the timing of the race it hunts.
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
- Deferred, not done: an accent-only change still runs the whole
  `reconfigureTheme` (fonts rebuilt, `RDW_ERASE | RDW_ALLCHILDREN`) once per
  new row; the installed-themes list is read from disk on every palette and
  dropdown open; the Terminal theme chevron has no hover state or UIA
  ExpandCollapse. Each needs a visible run to verify.
