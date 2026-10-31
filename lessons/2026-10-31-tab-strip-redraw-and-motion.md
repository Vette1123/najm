# Tab strip redraw and motion

## What

The tab strip was redrawn and given motion. Resting tabs lost their boxes and
lie on the band with hairline dividers. Tabs read icon, muted number, title,
left-aligned; the icon is the status badge, the title's own symbol enlarged,
or a prompt. The close X is the Fluent glyph with its own fading chip. The
active tab has real rounded corners and an accent cap that slides between
tabs with a stretching leading edge while the two surfaces crossfade. Hover
fades the surface in and grows a line from the tab's centre.

## Mistakes

- The tabs looked square for a long time because `RoundRect` takes a corner
  diameter and the code passed a radius. Every earlier polish pass worked
  around the look without reading the call.
- A first draft inserted a function above an existing doc comment with a
  scripted edit, which moved the comment onto the wrong function. Caught on
  re-read, before CI.
- The first design left animation to the existing hover fade only; the owner
  asked for much more motion partway through, so the sliding cap came second.

## What worked

- Reusing the hover fade for the surface, label and hover line: no new timer
  and no new state for three effects.
- One bar in client coordinates, with each child window painting its own
  slice, gives a slide across windows that cannot paint over each other.

## Rules

- A GDI call with a geometric argument is read in its documentation before
  it is tuned by eye.
- Tab motion runs on the tween heartbeat and stops when settled. Nothing in
  the strip may keep a timer alive at rest.
