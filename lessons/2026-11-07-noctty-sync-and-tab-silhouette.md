# Noctty sync to 31796f5d0 and the active tab's silhouette

## What

- Merged Noctty main 31796f5d0 (v1.3.136+1) with a real merge commit. Upstream split
  `labels.zig` and `win32_search_bar.zig` into `tab_label.zig`, `confirm_text.zig`,
  `overlay_view.zig`, `docked_search.zig` and `notifications.zig`. Najm's changes in those
  areas moved with the code:
  - the paste prompt body;
  - the narrow search bar's filter relayout;
  - tab label parts and the always-reserved icon slot;
  - four tab-strip actions;
  - palette accent picks.
- The active tab now has rounded upper corners (6 DIP), an accent cap whose ends follow
  those corners, and bottom flares (4 DIP) that curve the tab's sides into the separator row.
  Edge pixels are blended by coverage. The geometry is a pure helper,
  `win32_tab_visual.silhouette`, pinned by three tests, and the host pixel test pins the
  painted shape.

## Mistakes

- Upstream's `tab_label.key` charged the icon slot only while a status badge showed. Najm
  reserves the slot on every tab. Taking "theirs" would have silently widened every label
  past its icon. Hunks where theirs is a rewrite need the behaviour diffed, not just the
  text.
- Upstream re-introduced about 20 "noctty" display strings in moved code: the confirm
  prompts, the tab label fallback, the AUMID and the config-reload toast.
  `najm-identity-check.ps1` passed on all of them because its 6 patterns don't cover moved
  prose. A grep for display shapes found them.
- First draft clipped the sliding cap to every tab's silhouette. That would have broken the
  moving bar into pieces at each tab edge. Only a silhouetted tab clips its cap.

## What worked

- Sampling the user's screenshot pixel by pixel. It showed exactly what was wrong: the join
  colour matched, but there were square corners, a cap 4 px short with square ends, and a
  right angle into the separator. Without it I'd have been guessing.
- One `cornerInset` formula serves both the rounded top and the concave flare (row 0 is the
  row farthest from the curve's centre).

## Rules

- After a sync, grep moved code for display-string shapes (`orelse "noctty"`, `Quit noctty`,
  `Tab 1 (noctty)`, the AUMID). Don't trust the identity check alone.
- When a sync resolves a rewritten function to theirs, diff its behaviour against Najm's
  rule (here: the icon-slot charge) before accepting it.
