# The working ring spins, and a cut tab title fades out

## What

- A tab whose program works with no percentage now shows a spinning arc (0.3 of the
  circle, one turn a second, linear) over a muted track, not a still, full ring. One
  33 ms timer per window (`Host.syncTabSpin`) runs only while such a tab shows and motion
  is allowed. Each frame repaints the icon slot only. Reduced motion and High Contrast
  keep the still ring.
- A title the tab is too narrow for no longer ends in "...". It is drawn whole, clipped,
  and its last 22 DIP fade into the tab in 12 colour steps. High Contrast keeps the dots.
- Checked origin before starting: local main matched origin/main (fc123e00d).

## Mistakes

- The 2026-11-09 lesson and log entry left the `working` outline plain "since its ring
  already moves". It never moved: `.ring = null` drew a full, still circle, and nothing
  repainted it on a timer. Nobody checked the claim against `drawStatusBadge`. The
  user's screenshot of a hollow ring showed it.
- My first trigger edit anchored on AGENTS.md text across a line wrap and matched
  nothing. The asserting script caught it before anything half-applied.
- Two new `pub fn`s in `tab_label.zig` (`titleCut`, `wholeTitle`) broke
  `facade_budget`'s pinned pub count (13) after a 19-minute CI run. A new `pub` in a
  `src/apprt/win32/` leaf means grepping `facade_budget.zig` for its file before pushing.

## What worked

- One Sonnet agent mapped every tab animation and the paint path before any edit. It
  found that the ring was static, that there was no buffered DC, and no GradientFill.
  That ruled out a gradient overlay. Text redrawn in clipped strips needs no alpha and
  fills nothing.
- Reusing the tooltip's own gate (`titleCut`) to decide whether the label was cut,
  instead of guessing from trailing dots.

## Rules

- A claim that something animates needs a timer or tween that repaints it. Grep for
  one before writing "already moves".
- Continuous motion asks again on every tick whether it is still wanted, so every way it
  can end stops it without a hook of its own.
