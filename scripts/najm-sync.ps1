# Merge upstream Noctty into Najm's main.
#
#   ./scripts/najm-sync.ps1                  # latest Noctty release tag
#   ./scripts/najm-sync.ps1 -Ref upstream/main   # Noctty's tip, unreleased work included
#
# It merges (never rebases or force-pushes), so Najm's history keeps every
# upstream commit and every Najm fix. After a clean merge it runs the identity
# check, records the base in UPSTREAM_BASE and commits. It never pushes:
# push main yourself once you have looked (CI runs on the push).
param(
    [string]$Ref = ""
)
$ErrorActionPreference = "Stop"
Set-Location (Resolve-Path (Join-Path $PSScriptRoot ".."))

function Invoke-Git {
    & git @args
    if ($LASTEXITCODE -ne 0) { throw "git $($args -join ' ') failed with exit code $LASTEXITCODE." }
}

if (git status --porcelain) { throw "The working tree has changes. Commit or stash them before syncing." }
$branch = (git rev-parse --abbrev-ref HEAD).Trim()
if ($branch -ne "main") { throw "Sync from main, not '$branch'." }

# Upstream tags live under upstream/* so they can never be pushed to Najm as
# Najm release tags (the release workflow fires on v*).
git config remote.upstream.tagOpt --no-tags
if (-not ((git config --get-all remote.upstream.fetch) -match 'refs/tags/upstream/')) {
    git config --add remote.upstream.fetch "+refs/tags/*:refs/tags/upstream/*"
}
# README.md is Najm's own; .gitattributes marks it merge=ours, which needs this driver.
git config merge.ours.driver true
Invoke-Git fetch upstream
Invoke-Git fetch origin

$behindOrigin = [int](git rev-list --count "HEAD..origin/main")
if ($behindOrigin -gt 0) { throw "main is $behindOrigin commit(s) behind origin/main. Pull first." }

if (-not $Ref) {
    $Ref = (git tag -l "upstream/v*" --sort=-v:refname | Select-Object -First 1)
    if (-not $Ref) { throw "No upstream/v* tags found after fetching." }
    Write-Host "No -Ref given: using the latest Noctty release, $Ref."
}
$refSha = (git rev-parse --verify "$Ref^{commit}").Trim()
$ahead = [int](git rev-list --count "HEAD..$refSha")
if ($ahead -eq 0) {
    Write-Host "Najm already contains $Ref ($($refSha.Substring(0,9))). Nothing to merge."
    exit 0
}
Write-Host "Merging $ahead upstream commit(s) from $Ref ($($refSha.Substring(0,9)))."

$label = $Ref -replace '^upstream/', ''
git merge --no-ff --no-commit $refSha
if ($LASTEXITCODE -ne 0) {
    $conflicts = @(git diff --name-only --diff-filter=U)
    Write-Host ""
    Write-Host "$($conflicts.Count) file(s) conflict:" -ForegroundColor Yellow
    $conflicts | ForEach-Object { Write-Host "  $_" }
    Write-Host ""
    Write-Host "Resolve them keeping Najm's names (SYNCING.md lists them), then:"
    Write-Host "  ./scripts/najm-identity-check.ps1"
    Write-Host "  git add -A; git commit -m 'chore(sync): merge Noctty $label'"
    Write-Host "Or give up with: git merge --abort"
    exit 1
}

& (Join-Path $PSScriptRoot "najm-identity-check.ps1")
Set-Content -LiteralPath UPSTREAM_BASE -Value "$label $($refSha.Substring(0,9))"
Invoke-Git add UPSTREAM_BASE
Invoke-Git commit -q -m "chore(sync): merge Noctty $label"
Write-Host ""
Write-Host "Merged Noctty $label. Next: git push origin main (CI runs), then ./scripts/najm-release.ps1 -Version <x.y.z>."
