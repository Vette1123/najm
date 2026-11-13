# Clickable links: plain hover, plain click, a stronger mark

## What

URLs, paths and OSC 8 hyperlinks in terminal output are now marked on plain
hover with an underline and the theme's link blue, plus the hand pointer. A
plain left click opens them. Ctrl+click opens them every time. Before this,
both the mark and the click needed Ctrl, and the click was often dropped.

## Mistakes

- The cause of "Ctrl+click rarely works" was not in the opener or the
  scheme prompt, where a reader would look first. It was in the release.
  `handleMouseButton` runs `cursorPosCallback` with the release's modifiers
  before `mouseButtonCallback`. That call resets `over_link` and looks
  again for a link. If Ctrl came up a moment before the button, the
  `hover_mods` link was not found and the click went nowhere.
- Opening a link on any plain release would also have opened a URL the user
  meant to drag-select and copy. The release check (`linkOpensOnRelease`)
  only appeared when I read the click path through to the drag case. It was
  not in the first design.
- Not fixed: the first click of a double-click on a URL still opens the
  link. Telling a single click from a double click needs a
  `mouse-interval` delay before every open. That costs every click to save
  one rare gesture, so it is written down and not built.

## What worked

- The fix is two config values, `.hover_mods` → `.hover`, plus one
  predicate. The hover and click machinery stayed as it was.
- The colour has a contrast floor: palette 12, then 4, 14 and 6, each
  needing 3:1 against the cell, and otherwise the cell's own colour. A
  theme whose blue matches its background keeps readable links.

## Rules

- When an input works "sometimes", look at what is read at release time
  rather than at press time. Modifiers and position are sampled again on
  release.
- Making a gesture easier (no modifier needed) means checking every
  gesture that shares its button: drag-select, double-click, triple-click,
  Shift-extend.
