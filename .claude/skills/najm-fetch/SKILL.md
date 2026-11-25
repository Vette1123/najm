---
name: najm-fetch
description: In the najm repo, "fetch and pull", "pull latest", "take latest changes", "sync noctty" or "get upstream" means BOTH remotes - Najm's origin and Noctty's upstream - and merging Noctty's main into Najm end to end. Runs scripts/najm-fetch.ps1, resolves conflicts, lands the sync PR on green CI.
---

# Fetch and pull, Najm and Noctty

"Fetch and pull" in najm never means origin alone. Noctty (`upstream`,
amanthanvi/noctty) moves every day; Najm merges its `main`.

## Steps

1. From the main checkout (`C:\HighSpeed\Personal\najm`), run:
   `pwsh -NoProfile -File scripts/najm-fetch.ps1`
   It fetches both remotes, fast-forwards `main`, reports how far Najm trails
   Noctty's latest release and `main`, disables any upstream workflow that
   registered on Najm, and, if Noctty is ahead, opens a sync PR from
   `sync/noctty-<sha>` in `.claude/worktrees/sync-noctty-<sha>`.
   Report only: add `-NoSync`.
2. **Conflicts** (exit 1, files listed): resolve in that worktree with the
   rules in `SYNCING.md`: keep Najm's names (`najm.exe`, `najm +action`,
   `%LOCALAPPDATA%\najm`, the AUMID), take upstream's logic. Files Najm deleted
   on purpose (`.github/dependabot.yml`) stay deleted (`git rm`). In
   `AGENTS.md`, take upstream's text and keep Najm-only pointers. Then
   `scripts/najm-identity-check.ps1` must print OK, write
   `UPSTREAM_BASE` (`main <sha9>`), commit `chore(sync): merge Noctty main <sha9>`,
   push, and open the PR as the script would have.
3. Watch Najm CI on the PR (`gh run list --repo Vette1123/najm --branch <branch>`;
   cap the watch at 30 min). Red: fix from the log on the branch, never locally
   build (no `zig build` on this PC).
4. Green: `gh pr merge <n> --merge --repo Vette1123/najm`. A sync is the one
   PR that merges with a merge commit; rebase rewrites Noctty's commits.
5. Rerun `scripts/najm-fetch.ps1 -NoSync`: it pulls the merge into `main`,
   disables the new upstream workflows now registered, and must say
   "Nothing to sync". Remove the worktree (`git worktree remove`) and the
   branch once `git cherry origin/main <branch>` shows no `+`.

## Report

One line each: main pulled N, Noctty release in Najm or missing N, Noctty main
merged (PR link) or nothing to sync, workflows disabled.
