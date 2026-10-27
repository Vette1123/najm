# Keeping Najm in step with Noctty

Najm is a fork of [Noctty](https://github.com/amanthanvi/noctty). We merge Noctty when we want
its work, and ship our own fixes on our own schedule.

## The three commands

| When | Run |
|---|---|
| Pull in Noctty's latest release | `./scripts/najm-sync.ps1` |
| Pull in Noctty's unreleased `main` | `./scripts/najm-sync.ps1 -Ref upstream/main` |
| Check nothing reverted to Noctty's names | `./scripts/najm-identity-check.ps1` |
| Ship a Najm release | `./scripts/najm-release.ps1 -Version 1.0.1` |

`najm-sync` merges and never rebases or force-pushes. It never pushes, either: push `main` yourself.
CI runs on every push, and `najm-release` tags the release. **Najm release** builds, signs and
publishes it, and installed copies pick it up through the in-app updater.

## What Najm renames, and where

Only names a person or Windows sees are renamed. Internal identifiers (`noctty_iss`,
`main_noctty_command.zig`, `noctty.ico`, `noctty-terminal-handoff-proxy.dll`, Zig symbols) keep
Noctty's names so merges stay small. When a merge conflicts, keep Najm's side for these:

| What | Najm | Noctty | Where |
|---|---|---|---|
| Program | `najm.exe`, `najm.com` | `noctty.exe`, `noctty.com` | `src/build/GhosttyExe.zig`, every `"…exe"` literal in `src/` |
| Config and state folder | `%LOCALAPPDATA%\najm` | `%LOCALAPPDATA%\noctty` | `src/build_config.zig`, `src/os/xdg.zig` |
| App ID (taskbar, toasts, jump list) | `io.github.vette1123.najm` | `io.github.amanthanvi.noctty` | `src/apprt/win32_aumid.zig`, `ipc_server.zig`, `dist/windows/noctty.iss` |
| Single-instance pipe | `\\.\pipe\najm.` | `\\.\pipe\noctty.` | `src/apprt/win32/ipc_server.zig` |
| Toast activator CLSID | `8CA0641E-…` | `3E21F05E-…` | `src/apprt/win32_toast_activator.zig`, `noctty.iss` |
| Installer identity | AppId `io.github.vette1123.najm` | `io.github.amanthanvi.winghostty` | `noctty.iss`, `src/os/windows.zig` |
| Explorer menu | `Open Najm here` (`shell\najm`) | `Open noctty here` | `src/apprt/win32_shell_menu.zig`, `noctty.iss` |
| Update feed | `Vette1123/najm` releases | `amanthanvi/noctty` | `src/update/github_releases.zig` |
| Release assets | `najm-<ver>-windows-x64-…` | `noctty-<ver>-…` | updater, `scripts/windows-architecture.ps1`, `scripts/common.ps1` |
| Update signer pin | `CN=Najm Code Signing` | Noctty's key | `src/update/github_releases.zig` |
| Icon | the Najm star | Noctty's | `dist/windows/noctty.ico` (same file name) |

`najm-identity-check` fails on any of Noctty's identity strings in those files: it reports 241
on Noctty's own `main`, and 0 on Najm.

## Things that are shared on purpose

- Terminal handoff CLSIDs (default-terminal registration). Najm and Noctty installed together
  would fight over "default terminal". Install one or the other.
- `config.ghostty` as the config file name, and Ghostty's config options.

## Releases and signing

Najm signs with its own self-signed certificate, `CN=Najm Code Signing` (thumbprint
`26D9DB30682A45008C05E08729B7CC9016D492FB`, valid until 2036-10-27). The PFX lives in the repo
secrets `NAJM_CODESIGN_PFX_BASE64` and `NAJM_CODESIGN_PFX_PASSWORD`, plus an offline copy held by
the maintainer. The updater installs only what that key signed. A new key means a new pin in
`src/update/github_releases.zig`, shipped *before* the first release signed with it.

Windows SmartScreen warns about the self-signed installer the first time it runs: choose
**More info → Run anyway**.

Najm versions are its own (`1.0.0`, `1.0.1`, …). `UPSTREAM_BASE` records the Noctty commit each
build is based on, and the release notes repeat it.
