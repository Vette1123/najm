# Noctty sync and the Settings preview in open terminals

## What

- Merged Noctty main 40eec4205 (20 commits: CI gates and shards, the
  ghostty-vt placeholder DLL, tab tear-off, Dependabot). Najm names kept in
  the updater payload lists (`najm.com`, `najm.exe`, `najm.portable`) and the
  placeholder DLL's version resource.
- Settings now previews terminal looks (font size, font family, theme, text
  colour, cursor style, padding) in every open pane while the draft is
  unsaved. Save keeps it, Discard or closing the window reverts it. The
  status line says so: "Previewing now. Save to keep it, or Discard changes
  to undo it."

## Mistakes

- First plan was to give those fields a `PreviewEffect` and write them onto
  the chrome's preview clone. A clone with typed fields set cannot show a
  theme change (the old theme's colours stay) or what `finalize` derives, so
  the pane preview had to be the config Save would load, built from lines.
- The first `reshowPanePreview` cleared the sent mark before re-running, so
  a reload that made the draft equal the saved value left the App holding a
  stale preview copy. It now keeps an empty mark so the end still fires.
- The App test called the thunks unqualified from a top-level test; they
  are `App.` methods. `zig ast-check` caught it without a build.
- CI caught two things `ast-check` cannot: a comptime scan of every Config
  field ran out of the default 1000-branch quota (`fieldOf` needs
  `@setEvalBranchQuota`), and `Config.loadReader` panics on a name with no
  directory (`dirname(...).?`): "Settings preview" became
  "Settings preview/draft".
- Upstream re-introduced "noctty" in payload names and one Settings status
  string; the identity script did not catch the status string.

## What worked

- One writer for config lines (`settings_pane_preview.writeEntry`) shared by
  Save and the preview, so the preview cannot drift from what is saved.
- Pushing through `updatePaneCoreConfig` inside `app_wide_config_change`, the
  path the palette theme preview already uses, instead of a new pane API.

## Rules

- A terminal-look preview loads config text, it never mutates a clone.
- Every place that ends or replaces what panes show must end or re-send the
  pane preview (save, Discard, close, terminate, reload).
- After an upstream merge, grep the diff for user-visible "noctty" strings,
  not only file names.
