# Pane label: resize overlay and link preview

## What

`resize-overlay*` and `link-previews` now work on Windows. One top-level popup
per window (`Host.showPaneLabel`) shows "C × R" while a pane's grid changes,
and the hovered link's URL at the pane's bottom left. Pure rules live in
`src/apprt/win32/pane_label.zig`. Settings enables the Link preview dropdown.

## Mistakes

- I told the owner keyboard and UIA reach needed caption-button and palette
  providers. Both had already shipped; the investigators' reading of the code
  corrected it. Read the code before listing gaps.
- I first planned a dwell timer through the dormant `HoverTracker`. Upstream
  shows the URL at once, and the core already debounces the hover, so the
  tracker stays unused.
- A large inline Python edit was refused by the worktree guard; the Edit tool
  per hunk worked.

## What worked

- Reusing the tab tooltip's window class and paint gave a themed, rounded,
  ellipsized card with zero new paint code.
- One shared `isUnsafeLinkCodepoint` for the opener and the preview.

## Rules

- A feature marked "no effect" may only lack its apprt half: grep the core's
  action first (`mouse_over_link` was sent all along).
- Pane-anchored popups go through `showPaneLabel`; never a child window over
  the terminal.
