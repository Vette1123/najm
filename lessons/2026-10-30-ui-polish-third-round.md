# UI polish, third round: tab close, paste prompt, name, search fit, Settings search

## What

Three read-only reviews (Settings; tab row, search and scrollbar; overlays
and dialogs) found 19 items. The top five are fixed:

- A tap on an idle tab's hidden close X activated the tab, not closed it
  (`Host.tabCloseAlpha`, `tabCloseDownLeft`).
- The paste prompt says why it stopped the paste
  (`win32_paste_protection.promptBody`).
- Prompts, banners, the startup dialog and the in-terminal launch error say
  Najm, and point at `najm +...`, the command the package ships.
- A narrow search bar keeps its results chip and any toggle that is on
  (`searchBarFit` with `SearchBarWants`).
- Ending a Settings search keeps the row it found in view
  (`runSearch(keep_in_view)`).

## Mistakes

- Two of the five were rules the log already stated (the tab close hit
  scales with the X's alpha; the paste confirm shows the verdict's reason)
  that the code no longer kept. Nothing failed: the helper that did it was
  kept alive by a test-keep line, and the reason went to a log line.
- "Rename noctty to Najm" first looked like a string sweep. The CLI help's
  `Usage: noctty` is asserted by packaging and live harnesses, so the CLI
  and docs rename is its own unit, not a tail of this one.
- The first draft of the Settings fix read the row to keep after the query
  was replaced, when the search is already inactive and the helper returns
  null; caught on re-read, before CI.

## What worked

- Checking each reviewer's top claim in the code before ranking: all three
  held, and one (`+validate-config` naming a command the package does not
  ship) was worse than reported.
- Doing the Settings scroll inside the suspended-redraw block, so the page
  paints once where it ends up.

## Rules

- A log rule that names a helper ("X hit-tests with `closeHitRect`") is
  checked by grepping the helper's production callers, not its tests.
- User-visible text names the product and the command it ships; internal
  identifiers (class names, the IPC schema, cache folders) keep theirs.
