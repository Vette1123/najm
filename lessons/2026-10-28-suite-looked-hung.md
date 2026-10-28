# 2026-10-28: the test suite looked hung

## What

The full Zig suite kept stopping at a different test each run, past ten minutes, on main as
well as on the accent branch. A stack sampler (`scripts/zig-test-stacks.ps1`, needing no debugger)
showed it was slow, not stuck. The `PageList` test helper `growRows` ran a full-page integrity
check on every added row, so one 150,000-row test alone took two minutes. `growRows` now checks
once at the end. That test takes 219 ms, and the full suite passes in about five minutes.

The accent work was also checked on screen. Captures from a private desktop of the palette,
Settings and the right-click menu showed the chosen accent, measured to the pixel (default
`#749CE0`, teal `#00B7C3`, gold on light darkened to `#B28100`, `#FF6F61`).

## Mistakes

- **Called it a pre-existing hang and moved on.** The main control was right that main hung
  too, but "hang" was the wrong word. A process that burns a whole CPU core is working, so sample
  it before naming it.
- **Guessed the allocator.** `Page.assertIntegrity` maps a fresh `DebugAllocator` on every call,
  which looked expensive on Windows. Switching it measured no change (still two minutes), so it
  was reverted. The cost was the scan itself.
- **Read each hang as a different bug.** Every hang was simply whichever test was running when
  the run was stopped.
- **The capture agent's first launches passed a null `lpDesktop`.** For a few seconds, test
  windows reached the owner's real desktop. Every process on a private desktop needs
  `WinSta0\<desktop>`, as AGENTS.md says.
- **The per-test timing run used a PowerShell scriptblock as a .NET event handler.** It ran on a
  thread-pool thread and crashed pwsh. A rerun was then stopped by the harness for low system
  memory, so there is no per-test timing table.

## What worked

- StackWalk64 over the test binary's PDB, sampled three times. The same frames each time named
  the loop.
- Pausing integrity checks in the bulk helper and verifying once at the end. The tests still see
  a fully checked list.
- Posting `VK_APPS` to the terminal child to open the context menu, then `PrintWindow` on the
  `#32768` menu window.

## Rules

- Sample a "hung" test with `scripts/zig-test-stacks.ps1` before guessing.
- Measure a performance guess before keeping it.
- Bulk test helpers pause per-step integrity checks and verify once.
