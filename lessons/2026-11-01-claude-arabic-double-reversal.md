# Claude Code's Arabic read backwards

## What

Arabic in Claude Code read backwards in Najm from 1.0.9. Claude Code writes its Arabic already
reversed on Windows, and Najm reversed it again. Full-screen rows now keep their columns, and their
letters are marked right to left so they still join.

## Mistakes

- 1.0.9 shipped with "the alternate screen stays left to right" in the README, the log and the
  config text, and it was false. `.ltr` set the paragraph level only, and every Arabic run still
  reversed. The capture only ever tested `pwsh` output on the primary screen.
- The feature was never tried in the app the owner spends the day in.
- My first two searches of the PTY recordings found nothing, and neither result meant anything:
  the recordings are an escaped replay script. Zero escape sequences in a terminal stream was the
  tell that the search was wrong.
- The cost is real: vim's Arabic now reads backwards. Two kinds of program can't be told apart on
  the same screen, and the one the owner uses wins.

## What worked

- `NAJM_PTY_RECORD_DIR` was already on, so the bytes settled the cause: 7,756 reversed words to 4.
- Sending the owner Arabic to look at first gave a live test of the failing path.
- The shaper's `rtl` option already meant "cells in display order", so no new shaping was needed.

## Rules

- A rendering feature is captured in the programs people run, not only in a demo script.
- A setting that claims a mode is off is tested with a row in that mode.
- When a terminal shows text wrong, read the recorded bytes before reading the renderer.
