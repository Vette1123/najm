# Tag and push a Najm release. The "Najm release" workflow builds, signs and
# publishes it; installed copies see it within a day (or on Check for updates).
#
#   ./scripts/najm-release.ps1 -Version 1.0.1
#
# Pushes only main and the one new tag, never --tags: Noctty's own tags are
# kept locally as upstream/* and must never reach Najm as v* tags.
param(
    [Parameter(Mandatory)][string]$Version
)
$ErrorActionPreference = "Stop"
Set-Location (Resolve-Path (Join-Path $PSScriptRoot ".."))

function Invoke-Git {
    & git @args
    if ($LASTEXITCODE -ne 0) { throw "git $($args -join ' ') failed with exit code $LASTEXITCODE." }
}

if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "Version '$Version' is not MAJOR.MINOR.PATCH." }
if (git status --porcelain) { throw "The working tree has changes. Commit them first." }
$branch = (git rev-parse --abbrev-ref HEAD).Trim()
if ($branch -ne "main") { throw "Release from main, not '$branch'." }

Invoke-Git fetch origin --tags
$behind = [int](git rev-list --count "HEAD..origin/main")
if ($behind -gt 0) { throw "main is $behind commit(s) behind origin/main. Pull first." }
if (git tag -l "v$Version") { throw "Tag v$Version already exists." }

$latest = (git tag -l "v*" --sort=-v:refname | Select-Object -First 1)
if ($latest -and ([version]$Version -le [version]($latest.TrimStart('v')))) {
    throw "Version $Version is not newer than the latest Najm release $latest; the updater would ignore it."
}

# The release's changelog, which the workflow publishes as its notes.
$notes = Join-Path "release-notes" "$Version.md"
if (-not (Test-Path $notes)) { throw "Missing $notes. Write the changelog (what changed since $latest) and commit it first." }
$notesBytes = (Get-Item $notes).Length
if ($notesBytes -lt 200) { throw "$notes is $notesBytes bytes; a changelog under 200 bytes is a stub, not release notes." }
if (-not (git ls-files $notes)) { throw "$notes is not committed." }
Write-Host "Changelog: $notes ($notesBytes bytes)"

& (Join-Path $PSScriptRoot "najm-identity-check.ps1")

Invoke-Git tag -a "v$Version" -m "Najm $Version"
Invoke-Git push origin main
Invoke-Git push origin "refs/tags/v$Version"
Write-Host "Pushed v$Version (previous: $(if ($latest) { $latest } else { 'none' }))."
Write-Host "Watch it: gh run watch --repo Vette1123/najm `$(gh run list --repo Vette1123/najm --workflow najm-release.yml --limit 1 --json databaseId --jq '.[0].databaseId')"
