# 2026-10-27: Najm fork, first releases, first perf pass

## What

Forked Noctty into Najm: renamed what users and Windows see (exe, data dir, AUMID, IPC pipe,
toast CLSID, Inno AppId, Explorer menu, update feed, asset names, signer pin) and kept internal
names. Added najm-ci, najm-release, najm-sync, najm-identity-check and a self-signed signing key.
Shipped v1.0.0 and v1.0.1, then installed Najm and removed the portable Noctty copy.

Perf pass, measured on the owner's PC: cold start went 578 to 375 ms with a `font-codepoint-map`
and 610 to 453 ms with a `font-family`, from a per-file font index cache. Memory per pane
(12.9 MB) and key-to-pixel latency (9.8 ms) were already within budget.

## Mistakes

- **Pushed 290 MB of history in one go over a 2 Mbps uplink.** It saturated the owner's
  connection and failed. Chunked pushes of first-parent checkpoints also flooded the link, until a
  local CONNECT proxy capped the upload at 100 KB/s.
- **A mechanical `sed` over `src/` renamed strings inside tests and scripts.** CI failed 15 tests,
  then 1 more. The `sed` also changed a shell-integration script whose SHA-256 is pinned, and the
  bench evidence schema id.
- **`git grep -l | xargs sed` hit non-Zig files**, including `integration.ps1`.
- **The first upstream tag push would have triggered Najm releases.** Upstream `v*` tags now live
  under `upstream/*`.
- **The first `v1.0.0` release failed its signature check.** A self-signed key needs
  `WINDOWS_CODESIGN_TRUST_SELF_SIGNED=true`, so the packager checks the thumbprint, not the root.
- **The temporary upload branch became the repo's default branch**, so deleting it failed until
  the default was moved to `main`.
- **The 1 MB ConPTY pipe idea was wrong.** The profile showed full 64 KiB reads, so it was dropped
  before any code was written.

## What worked

- Measuring before changing anything: four interleaved config variants, 9 launches each, with
  Najm's own render trace.
- Keeping the change Najm-owned: the cache lives in a new file with a small hook, so merges stay
  cheap.
- Reading the CI log's expected/found blocks, instead of guessing which rename broke a test.

## Rules

- Never push a large history over the owner's link without an upload cap. Use the throttle proxy.
- Renames stay explicit: list each file, never `xargs sed` across a tree. Then run
  `scripts/najm-identity-check.ps1`.
- Push only `main` and one tag. Never `--tags`.
- Benchmark the claim before writing the fix: the pipe-size theory died on its first profile.
