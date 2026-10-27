# Fails when Noctty's identity is back in a place Najm renamed: a merge from
# upstream can add a new "noctty.exe" literal or a new AUMID copy, and that
# would ship a Najm that launches, updates or registers as Noctty.
#
#   ./scripts/najm-identity-check.ps1               # the working tree
#   ./scripts/najm-identity-check.ps1 -Ref upstream/main   # any commit (seen red there)
#
# Limits: it checks the identity strings below, not prose. Comments and docs
# that say "noctty" are fine and are not reported.
param(
    [string]$Ref = ""
)
$ErrorActionPreference = "Stop"

$paths = @(
    "src/*.zig",
    "dist/windows/noctty.iss",
    "dist/windows/noctty.rc",
    "scripts/package-windows.ps1",
    "scripts/build-package-windows.ps1",
    "scripts/common.ps1",
    "scripts/windows-architecture.ps1"
)
$patterns = [ordered]@{
    "Noctty AUMID"           = "io\.github\.amanthanvi\.noctty"
    "Noctty Inno AppId"      = "io\.github\.amanthanvi\.winghostty"
    "Noctty update feed"     = "repos/amanthanvi/noctty"
    "noctty.exe / .com name" = "noctty\.(exe|com)\b"
    "noctty-<ver> asset"     = "noctty-(\{s\}|\`$Version|[0-9]+\.[0-9]+\.[0-9]+-windows)"
    "Noctty toast CLSID"     = "3E21F05E-C82D-4E45-AA7D-2EC361AD6C3E"
}

$target = if ($Ref) { $Ref } else { "working tree" }
Write-Host "Najm identity check on $target ($($patterns.Count) patterns, $($paths.Count) path groups)"
$total = 0
foreach ($name in $patterns.Keys) {
    $args = @("grep", "-n", "-I", "-E", $patterns[$name])
    if ($Ref) { $args += $Ref }
    $args += "--"
    $args += $paths
    $hits = @(& git @args 2>$null)
    if ($hits.Count -gt 0) {
        $total += $hits.Count
        Write-Host ""
        Write-Host "$name - $($hits.Count) hit(s):" -ForegroundColor Red
        $hits | Select-Object -First 15 | ForEach-Object { Write-Host "  $_" }
        if ($hits.Count -gt 15) { Write-Host "  ... and $($hits.Count - 15) more" }
    }
}

if ($total -gt 0) {
    Write-Host ""
    throw "Najm identity check failed: $total Noctty identity string(s) on $target. Rename them to Najm (see SYNCING.md)."
}
Write-Host "OK: no Noctty identity strings on $target."
