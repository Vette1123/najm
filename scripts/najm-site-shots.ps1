# Captures the website's screenshots from a real Najm release. Runs on a GitHub
# Windows runner (.github/workflows/najm-shots.yml), never on a developer's
# machine: it types into whatever window is in front.
param(
    [Parameter(Mandatory)][string]$Version,
    [Parameter(Mandatory)][string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class Win {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
}
'@

function Send-Keys([string]$keys, [int]$wait = 700) {
    [System.Windows.Forms.SendKeys]::SendWait($keys)
    Start-Sleep -Milliseconds $wait
}

function Save-Shot([IntPtr]$window, [string]$name) {
    $rect = New-Object Win+RECT
    [void][Win]::GetWindowRect($window, [ref]$rect)
    $width = $rect.R - $rect.L
    $height = $rect.B - $rect.T
    if ($width -lt 600) { throw "Window is only $width px wide" }
    $bitmap = New-Object System.Drawing.Bitmap $width, $height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($rect.L, $rect.T, 0, 0, $bitmap.Size)
    $path = Join-Path $OutputDirectory "$name.png"
    $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Host "Saved $path at ${width}x$height"
}

New-Item -ItemType Directory -Force $OutputDirectory | Out-Null

# Staged content: no runner paths, usernames or machine details in the shots.
$demo = 'C:\dev\aurora'
New-Item -ItemType Directory -Force "$demo\src" | Out-Null
Set-Location $demo
git init -q -b main
git config user.name 'Najm Demo'
git config user.email 'demo@example.com'
'node_modules' | Set-Content .gitignore
'{ "name": "aurora" }' | Set-Content package.json
foreach ($message in 'initial commit', 'bump deps', 'rename session store', 'fix off-by-one in pager', 'parse config from env', 'add health check endpoint') {
    Add-Content README.md $message
    git add -A
    git commit -q -m $message
}

$zip = "$env:RUNNER_TEMP\najm.zip"
$app = "$env:RUNNER_TEMP\najm"
gh release download "v$Version" --repo Vette1123/najm --pattern "najm-$Version-windows-x64-portable.zip" --output $zip
Expand-Archive $zip $app
$exe = Get-ChildItem $app -Recurse -Filter najm.exe | Select-Object -First 1
New-Item -ItemType File (Join-Path $exe.DirectoryName 'najm.portable') | Out-Null
$config = Join-Path $exe.DirectoryName 'config.ghostty'
@"
working-directory = $demo
command = cmd.exe
window-save-state = never
window-width = 130
window-height = 30
auto-update = off
"@ | Set-Content $config

$process = Start-Process $exe.FullName -WorkingDirectory $demo -PassThru
for ($i = 0; $i -lt 40 -and $process.Refresh() -eq $null -and $process.MainWindowHandle -eq 0; $i++) {
    Start-Sleep -Milliseconds 500
}
$window = $process.MainWindowHandle
if ($window -eq 0) { throw 'Najm never opened a window' }
[void][Win]::SetForegroundWindow($window)
Start-Sleep -Seconds 5

Send-Keys 'git log --oneline -n 6{ENTER}'
Send-Keys 'git status{ENTER}' 1200
Send-Keys '^+e' 2000              # Split down
Send-Keys 'dir /b{ENTER}' 1200
Save-Shot $window 'shot-splits-dark'

Send-Keys '^+p' 1500              # Command palette
Send-Keys 'split' 1500
Save-Shot $window 'shot-palette-dark'
Send-Keys '{ESC}'

Stop-Process $process -Force
