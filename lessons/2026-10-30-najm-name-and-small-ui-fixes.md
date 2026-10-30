# The najm command everywhere, and four small UI fixes

## What

- Help, docs, harnesses and every user-visible string name the product
  Najm and the command `najm`; identifiers keep `noctty`
  (docs-and-site.md, 2026-10-30).
- The bash, zsh, fish, elvish and nushell ssh-terminfo hooks look for
  `najm`; they looked for a `noctty` binary no install has.
- Settings: Page Up/Down and Home/End page the form; the Advanced intro
  fits its box; the window title says Najm.
- Ctrl+Backspace deletes the previous word in the search bar, the
  palette and Settings (`win32/edit_keys.zig`).

## Mistakes

- The first rename regex treated `$noctty +` in a PowerShell harness as a
  command and renamed the variable; caught in the per-file review of the
  diff, not by any check.
- The rename looked like help text and docs. Following it turned up a real
  bug (five shell hooks calling a binary that is not shipped) and about a
  hundred more strings, most of which a quick read would have renamed
  wrongly: schema ids, registry names, ProgIDs, fixtures.
- A new file-level `DLGC_WANTARROWS` would have shadowed a test's local copy
  of it: the same compile error as the last round's `paint`, caught by
  grepping the new names before pushing.
- Dropped, not done: a wider scrollbar grab. The bar sits over the last
  column, so a wider strip takes clicks that start a selection; the
  proposal had no measurement behind it.

## What worked

- One reviewer classifying the long tail (rename, keep, rename with a
  test) with file:line, then applying exact phrases with a count each, so
  a phrase that matched nothing failed loudly.
- Asking the control what it does with keys (`WM_GETDLGCODE`) instead of
  keeping a list of classes.

## Rules

- A rename sweep classes each hit by whether an existing install wrote or
  matches it; only display text moves.
- Where a key is taken decides whether its translated character still
  arrives: after `TranslateMessage`, swallow it too.
