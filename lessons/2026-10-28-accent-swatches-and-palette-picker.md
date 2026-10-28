# 2026-10-28: accent swatches and the palette accent picker

## What

The Settings Accent color dropdown shows a round swatch beside each colour. Its closed field
looks like the themed dropdowns next to it. In the command palette, typing `accent` (or the
`#` prefix) lists every accent with its swatch. Selecting a row recolours the open windows
straight away, Enter saves the choice, and Escape puts the old one back. Themes and accents now
share one preview install (`installPalettePreview`) and one commit (`commitPalettePick` with a
`PalettePick` that carries its own wording).

## Mistakes

- **Owner-drawing the combo dropped its visual style.** `CBS_OWNERDRAWFIXED` gives the closed
  field the classic look: a darker field and a split drop button. The capture showed it. The fix
  paints the field with the `Combobox` theme's `CP_READONLY` and drop-button parts.
- **Painted the field only on `WM_PAINT`.** The combo also redraws its closed field through
  `WM_DRAWITEM` (`ODS_COMBOBOXEDIT`) when its selection changes, outside `WM_PAINT`. That path
  painted the classic look again, and four Settings stale-pixel tests failed. The field draw now
  invalidates the combo instead.
- **Left the themed field's rounded corners unpainted.** The corner pixels kept whatever was
  there before (12 stale pixels). `DrawThemeParentBackground` now paints them first.
- **Ran the full suite locally.** The owner runs it only on CI after a push. That rule is now
  saved as a memory.

## What worked

- Capture first, then fix. Each of the three paint bugs was obvious in a capture or in the
  stale-pixel tests, and none showed in a unit test.
- Reusing the theme preview's config-ownership machinery instead of writing a second copy. An
  accent preview is just a clone of the config from before the preview, with one field changed.
- Carrying the accent's tag name in the palette payload, as `setting` does. The palette core
  stays free of Win32 and config types for the microbench.

## Rules

- An owner-drawn stock control paints its themed frame itself (theme parts, parent background
  first), and handles the redraws the control makes outside `WM_PAINT`.
- A new palette preview reuses `installPalettePreview` and `commitPalettePick`.
