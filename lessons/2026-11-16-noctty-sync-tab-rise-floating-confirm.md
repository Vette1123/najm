# Noctty sync, the active tab's rise, and the floating confirm card

## What

- Merged Noctty main 263eacfa0 (v1.3.138+1, 7 commits: Kitty numpad keys, MSVC 14.52 STL
  build, a11y echo, hotkey probes in the a11y harness). Two log conflicts, both entries kept
  in date order.
- The active tab rises 3 DIP into place over the 240 ms cap slide and sinks 1 DIP while
  pressed (`win32_tab_visual.activeTabDrop`). Only its top moves, so the join to the
  terminal never opens. Reduced motion and High Contrast snap the slide, so they don't move.
- The confirm prompt ("Close this window?" and every `.confirm`) floats over the terminal's
  top rows instead of taking 58 px from it. The terminal no longer jumps, and ConPTY and
  the shell no longer redraw for a prompt. Its band is painted by its own STATIC
  (`Host.overlay_panel_hwnd`).
- The prompt is now a card at most 760 DIP wide, centred 6 DIP under the tab strip, with
  rounded corners the terminal shows past. A prompt that closes something has a red Close
  button.

## Mistakes

- The first heredoc carrying the host edit script broke on quoting and ran nothing. Only
  `git diff --stat` showed that one file of two had changed. Edit scripts go in a file.
- I clamped the banner below the floating prompt before reading that the banner is
  already hidden while any overlay is open (`Host.bannerShown`). It was dead code, so I
  removed it. Read the log entry about the neighbour before guarding against it.
- I first painted the card by filling its whole client and then the round rect over it.
  A STATIC has `CS_PARENTDC`, which ignores the window region, so the corners would have
  come out square over the terminal. The Settings log had measured that trap (2026-10-11
  EXT-06); grepping the log for `SetWindowRgn` before pushing caught it.
- The script that applied the card used a `shiftRectX` that did not exist and a chained
  `if/else if` expression. I caught both by grepping each new name before pushing.
- A press colour on the active tab would open a seam at its join to the terminal. Motion
  (sinking) gives the press feedback without that seam.

## What worked

- One Sonnet agent mapping the band's readers before editing. It found that host GDI paint
  sits under a pane child, which ruled out "just stop reserving rows".
- Reusing BANNER-01's own reasoning (#328) and the tab insert marker's owner-draw STATIC
  pattern instead of a new window class.

## Rules

- Anything that should not resize the terminal floats in its own child, raised once when
  it appears, never on every layout.
- A rounded child window paints only inside its shape, and that shape matches its region
  pixel for pixel.
- Press feedback on a tab joined to its terminal moves the tab. It never recolours it.
