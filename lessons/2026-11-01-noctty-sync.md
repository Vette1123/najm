# Noctty sync to da8983d20 (release 1.0.8)

## What

Merged Noctty `main` at `da8983d20` into Najm as a real two-parent merge
(PR #18) and resolved conflicts in `win32_settings.zig`, the updater and
the agent logs. Najm's names stayed; `UPSTREAM_BASE` moved.

## Mistakes

- Conflict markers were treated as the whole merge. Git auto-merged two
  semantic clashes it could not see: Najm's `WM_DRAWITEM_MENU` and Noctty's
  `WM_DRAWITEM` are the same message (a duplicate switch value), and Najm's
  `growRows` kept `.data.` while Noctty moved pages behind `.page()`.
- CI was spent one error at a time: three runs for three compile errors
  (a duplicate `DLGC_WANTARROWS`, then these two). The name scan after the
  first failure looked for equal names, so it could not find equal values.

- Two more clean auto-merges failed at run time. Noctty's new updater tests
  built ZIPs under `noctty/`, which Najm's validator refuses. A settings count
  read 76 on both parents, so git kept it, yet each side had added 4 to 72.

## What worked

- After the third failure, scanning all of Najm's delta against the upstream
  parent for the same two patterns (stale `.data.` access, `WM_` constants
  with equal values) proved no sibling was left.

## Rules

- After a sync, diff Najm against the upstream parent, not the conflict list:
  grep the added lines for any API the upstream side renamed or moved.
- Scan for equal VALUES as well as equal names before the first push.
- New upstream tests carry upstream names: rename their fixtures in the merge.
- A count equal on both parents is not safe. Compare both with the merge base.
- A sync merges with a merge commit. Never squash or rebase it.
