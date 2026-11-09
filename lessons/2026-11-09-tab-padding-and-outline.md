# Tab padding and outline

## What

- The close X keeps 8 DIP (`win32_tab_visual.close_edge`) off the tab's right edge. The
  shared `host_tab_close_zone_width` grows by that amount, so hit testing, UIA bounds, the
  label reserve and paint all move together. `closeChipRect` centres the chip in the zone
  minus that edge.
- The icon starts 14 DIP in (`tab_content_left`, was 10).
- The active tab has a 1 px outline in the dividers' colour. It follows the rounded corners
  and the flares and stays open at the join (`Silhouette.inset`).
- Checked Noctty for tab changes to copy: upstream has 2 commits since 31796f5d0 (release
  docs, dropping `ghostty-vt.dll`). Neither touches tabs, so there was nothing to port.

## Mistakes

- The 2026-11-07 silhouette moved the tab's body 4 DIP inside the button, but the content
  (close chip, label) was still laid out from the button's outer rect. So the X landed on
  the body's edge. The pixel test pinned the shape but never checked where the X sat
  relative to it.

## What worked

- Sampling the screenshot's columns showed the X's ink ending exactly where the body met the
  band. That pointed straight at the zone-versus-body mismatch.
- `host_tab_close_zone_width` was already the single source of truth for five readers, so
  one constant moved all of them together.

## Rules

- When a shape insets its body, test content against the body, not the button
  (`closeChipRect keeps the X off the active tab's side`).
