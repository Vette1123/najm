# The confirm card without its stray red strip

## What

- The close prompt's floating card lost the 2 px accent strip across its top. On the card,
  the strip stopped short of the rounded corners with square ends and read as a stray
  line. The red Close button already marks a prompt that closes something.
- `HostScene.paintConfirmCard` paints only the rounded panel and its border and no longer
  takes the Host. A host test paints it on a DIB in both themes and pins the top rows to
  the panel colour.
- Checked origin first: main was at 336b40b3a (the 1.0.16 merge), with nothing newer.

## Mistakes

- The 2026-11-16 card kept the band's accent edge as it was, a straight bar inset from the
  sides. It was built for a square band and was never re-checked against round corners. The
  CI capture showed it, but I shipped 1.0.15 and 1.0.16 before reading those pixels as a
  defect rather than a style.

## What worked

- Sampling the capture's rows (`#B23038` at rows 47 and 48 under the `#CACACA` border)
  told an edge from a stray bar without guessing.
- Dropping the strip also dropped the card paint's only use of the Host, which made it
  testable on a memory DC with the existing `BannerTestCanvas`.

## Rules

- When a shape changes (band to card, square to round), re-check every decoration it
  inherited against the new outline.
