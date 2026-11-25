# background-blur shows acrylic

## What

`background-blur` writes `DWMSBT_TRANSIENTWINDOW` on Windows 11 22H2+ where a
window's background alone is translucent (all panes OpenGL, opacity < 1).
Pure decision `window_start.backdropType`; written each opacity apply.
Settings' blur checkbox is enabled; docs and the config doc say where it works.

## Mistakes

- CI went red on the first push, twice. `applyBackgroundOpacity` began reading
  `App.shownConfig()`, and `placementTestApp` leaves `settings_preview`
  undefined, so a placement test crashed. And the Settings reset test still
  expected blur to be the one kind it could not reset. Before an apply path
  reads a new App field, grep the `App = undefined` fixtures that reach it.

- I first planned to add `DwmExtendFrameIntoClientArea`, because the 2026-09-14
  log entry's positive control used it. The code's own comment already said
  blur-behind with an empty region (#640) is enough for the material.
- Settings' `windows_notes` turns a note into a compile-time promise that the
  control is disabled; keeping blur's note while enabling the checkbox would
  not have compiled. Found by reading the comptime block before pushing.
- Branching blur from the sync branch put it on the same test lines as the
  link-preview change; restacked it on `feat/resize-label`.

## What worked

- Writing the backdrop in the opacity apply, which already runs after every
  theme write, instead of threading blur into the theme path.

## Rules

- The backdrop belongs to `applyBackgroundOpacity`, never the theme apply.
- A visual effect with no on-screen measurement ships with that gap written in
  the docs and the log, not claimed as seen.
