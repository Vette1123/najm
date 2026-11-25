# Fetch and pull everything Najm tracks: Najm's origin and Noctty's upstream.
#
#   ./scripts/najm-fetch.ps1            # fetch both, pull main, sync Noctty main through a PR
#   ./scripts/najm-fetch.ps1 -NoSync    # fetch both, pull main, report only
#   ./scripts/najm-fetch.ps1 -Ref upstream/v1.3.140   # sync a release tag instead of Noctty's main
#
# Run it from the main checkout (C:\HighSpeed\Personal\najm). It:
#   1. fetches origin (pruned) and upstream (tags land under upstream/*);
#   2. fast-forwards local main when it is checked out and clean, else says why not;
#   3. reports how far Najm trails Noctty's latest release and Noctty's main;
#   4. disables any upstream workflow GitHub registered on Najm (only najm-* run here);
#   5. when Noctty is ahead and -NoSync is absent: cuts sync/noctty-<sha> from
#      origin/main in its own worktree, runs najm-sync.ps1 there, pushes and opens the PR.
# A sync PR merges with a merge commit (gh pr merge --merge), never rebase: rebasing
# would rewrite Noctty's commits and the next sync would see them all again.
# Limits: it never merges the PR and never resolves conflicts; on a conflict it stops
# with the worktree path and the conflicting files.
param(
    [string]$Ref = "upstream/main",
    [switch]$NoSync
)
$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $root
$repo = "Vette1123/najm"

function Invoke-Git {
    & git @args
    if ($LASTEXITCODE -ne 0) { throw "git $($args -join ' ') failed with exit code $LASTEXITCODE." }
}
function Get-Count([string]$range) { [int](git rev-list --count $range) }

# Same remote setup najm-sync.ps1 makes: upstream tags never land as Najm v* tags.
git config remote.upstream.tagOpt --no-tags
if (-not ((git config --get-all remote.upstream.fetch) -match 'refs/tags/upstream/')) {
    git config --add remote.upstream.fetch "+refs/tags/*:refs/tags/upstream/*"
}
Invoke-Git fetch origin --prune --quiet
Invoke-Git fetch upstream --quiet
Write-Host "Fetched origin ($repo) and upstream (amanthanvi/noctty)."

# 2. Pull main.
$branch = (git rev-parse --abbrev-ref HEAD).Trim()
$dirty = [bool](git status --porcelain --untracked-files=no)
$behindMain = Get-Count "main..origin/main"
$aheadMain = Get-Count "origin/main..main"
if ($behindMain -eq 0) {
    Write-Host "main: up to date with origin/main ($aheadMain local commit(s) ahead)."
} elseif ($branch -ne "main") {
    Write-Host "main: $behindMain behind origin/main, not pulled: '$branch' is checked out here." -ForegroundColor Yellow
} elseif ($dirty) {
    Write-Host "main: $behindMain behind origin/main, not pulled: tracked files have changes." -ForegroundColor Yellow
} else {
    Invoke-Git pull --ff-only --quiet
    Write-Host "main: pulled $behindMain commit(s), now at $((git rev-parse --short HEAD).Trim())."
}

# 3. Where Najm stands against Noctty.
$release = git tag -l "upstream/v*" --sort=-v:refname | Select-Object -First 1
if (-not $release) { throw "No upstream/v* tags after fetching upstream." }
$releaseMissing = Get-Count "origin/main..$release"
$mainMissing = Get-Count "origin/main..upstream/main"
$releaseState = if ($releaseMissing -eq 0) { "in Najm" } else { "$releaseMissing commit(s) missing" }
Write-Host "Noctty latest release $($release -replace '^upstream/',''): $releaseState."
Write-Host "Noctty main $((git rev-parse --short upstream/main).Trim()): Najm trails it by $mainMissing commit(s)."
if ($mainMissing -gt 0) {
    git log --oneline --no-decorate -15 "origin/main..upstream/main" | ForEach-Object { Write-Host "  $_" }
    if ($mainMissing -gt 15) { Write-Host "  ... and $($mainMissing - 15) more" }
}

# 4. Only najm-* workflows run on Najm. A sync that adds an upstream workflow
# registers it active once it reaches main; turn it off. Limit: GitHub kept
# running gui-hidden.yml on pull_request after it was disabled (2026-11-25),
# so a new upstream workflow with a pull_request trigger also gets an
# `if: github.repository == 'amanthanvi/noctty'` guard on its jobs.
$workflows = gh workflow list --repo $repo --all --json name,state,path | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw "gh workflow list failed ($LASTEXITCODE)." }
$stray = @($workflows | Where-Object {
    $_.state -eq "active" -and $_.path -like ".github/workflows/*" -and
    (Split-Path $_.path -Leaf) -notlike "najm-*"
})
foreach ($w in $stray) {
    gh workflow disable $w.path --repo $repo
    if ($LASTEXITCODE -ne 0) { throw "Could not disable $($w.path) ($LASTEXITCODE)." }
    Write-Host "Disabled upstream workflow $($w.path) on Najm."
}
if ($stray.Count -eq 0) { Write-Host "Workflows: only najm-* are active." }

# 5. Sync.
$refSha = (git rev-parse --verify "$Ref^{commit}").Trim()
$missing = Get-Count "origin/main..$refSha"
if ($missing -eq 0) { Write-Host "Nothing to sync: Najm already holds $Ref."; exit 0 }
if ($NoSync) { Write-Host "-NoSync: $missing commit(s) of $Ref not merged."; exit 0 }

$short = $refSha.Substring(0, 9)
$syncBranch = "sync/noctty-$short"
$open = gh pr list --repo $repo --head $syncBranch --state open --json number,url | ConvertFrom-Json
if ($open) { Write-Host "A sync PR is already open: $($open[0].url)"; exit 0 }

$tree = Join-Path $root ".claude/worktrees/sync-noctty-$short"
if (Test-Path $tree) { throw "Worktree $tree already exists. Finish or remove it (git worktree remove) first." }
Invoke-Git worktree add --quiet -b $syncBranch $tree origin/main
Write-Host "Syncing $missing commit(s) of $Ref on $syncBranch in $tree."
Push-Location $tree
try {
    & (Join-Path $tree "scripts/najm-sync.ps1") -Ref $Ref
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Sync stopped on conflicts in $tree. Resolve there, commit, then rerun this script." -ForegroundColor Yellow
        exit 1
    }
    Invoke-Git push --quiet -u origin $syncBranch
    $label = $Ref -replace '^upstream/', ''
    $body = "Merges $missing Noctty commit(s) from $label ($short). Merge with a merge commit, not rebase."
    $url = gh pr create --repo $repo --base main --head $syncBranch --title "chore(sync): merge Noctty $label $short" --body $body
    if ($LASTEXITCODE -ne 0) { throw "gh pr create failed ($LASTEXITCODE)." }
    Write-Host "Opened $url. When Najm CI is green: gh pr merge --merge --repo $repo, then rerun this script."
} finally {
    Pop-Location
}
