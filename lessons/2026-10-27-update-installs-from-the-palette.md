# 2026-10-27: the update notice did nothing; Check for Updates now installs

## What

The owner clicked "Update available: Najm 1.0.1" and nothing happened. Two changes followed. An
unset `auto-update` now means `download`. A manual "Check for Updates" (from the Ctrl+Shift+P
palette) always downloads, then runs the notice's Install path, which still asks before it closes
sessions. Shipped in 1.0.2.

## Mistakes

- **Read the notice as "Install" when it was "Open Release".** Upstream's unset `auto-update`
  only checks, so nothing was staged and the click recorded `dismissed_version` instead. The
  state file (`%LOCALAPPDATA%\najm\update-state.json`) told the story in one read and should
  have been read first.
- **Set `auto-update = download` in the config and expected the running window to use it.** The
  window predated the edit. Clearing `dismissed_version` only worked after that process was gone.
- **Waited on the owner to close Najm**, and the waiter timed out after 10 minutes. Once the owner
  said to close it, the update staged within seconds.

## What worked

- Reading `update-state.json` before the code: `staged_version: null` plus a dismissal explained
  the dead click with no debugger.
- Routing the manual install through `openUpdateNotice`, the path the banner button already uses,
  so the confirm prompt, the portable case and the Settings hold all come along for free.

## Rules

- For an updater complaint, read `update-state.json` first.
- A manual check is an explicit request: it downloads and installs whatever `auto-update` says.
