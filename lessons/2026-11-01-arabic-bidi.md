# Right-to-left Arabic and Hebrew

## What

Display-only bidi: the screen stays in logical order, the renderer draws each row in visual order,
and the cursor, selection, search, links and mouse map through the same layout. On by default,
`bidi = false` turns it off. Released in 1.0.9.

## Mistakes

- We shipped "Arabic reads right to left" in the README and the site long before the renderer did,
  then took it back on 2026-10-31.
- I wrote "a ligature starts at its leftmost cell" from one reading of the shaper. Its test passed
  and it was wrong: lam-alef is one advance in two cells, so the blank cell landed on the side where
  lam joins.
- I took the broken lam-alef for Cascadia's design until a capture of the same words through
  Windows' own text engine showed a proper form. Shaping the font directly took minutes and named
  the cause; it should have come first.
- Two test failures were my expectations: 13 columns for 12 cells, and digits after Latin, which
  UAX#9 W7 keeps forward.
- `git push` from a worktree branch with a different remote name silently pushed nothing.

## What worked

- An oracle in the capture: same font, same words, a different engine. It separates a font's design
  from our bug.
- Capturing on the CI runner from the build the PR just made, since no local builds are allowed.
- Shaping with HarfBuzz outside the build to read real advances and clusters.

## Rules

- A shaping fix is checked against real glyph data from at least two fonts.
- Zero advance means "same pen as the next glyph": never give such a glyph its own cell.
- A rendering claim needs a capture before it goes in the README or on the site.
