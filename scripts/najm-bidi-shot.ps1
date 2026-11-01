# Captures right-to-left text from the najm.exe a CI run just built, as evidence
# a unit test cannot give: what the window really draws. Runs on a GitHub Windows
# runner (.github/workflows/najm-ci.yml), never on a developer's machine: it
# types into whatever window is in front and installs a font.
param(
    [Parameter(Mandatory)][string]$Exe,
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
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint x, uint y, uint d, IntPtr e);
}
'@

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

# The Windows copy of Cascadia Code has no Arabic; the release does.
$fonts = Join-Path $env:RUNNER_TEMP 'cascadia'
gh release download --repo microsoft/cascadia-code --pattern 'CascadiaCode-*.zip' --dir $fonts
Expand-Archive (Get-ChildItem $fonts -Filter '*.zip' | Select-Object -First 1).FullName $fonts
$userFonts = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
New-Item -ItemType Directory -Force $userFonts | Out-Null
$font = Get-ChildItem $fonts -Recurse -Filter 'CascadiaMonoNF-Regular.ttf' | Select-Object -First 1
if (-not $font) { $font = Get-ChildItem $fonts -Recurse -Filter 'CascadiaMonoNF.ttf' | Select-Object -First 1 }
if (-not $font) { throw 'The Cascadia release has no CascadiaMonoNF font' }
Copy-Item $font.FullName $userFonts
reg add 'HKCU\Software\Microsoft\Windows NT\CurrentVersion\Fonts' /v 'Cascadia Mono NF (TrueType)' /t REG_SZ /d (Join-Path $userFonts $font.Name) /f | Out-Null

$demo = Join-Path $env:RUNNER_TEMP 'bidi-demo.ps1'
@'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Clear-Host
'مرحبا بالعالم'
'هل تعمل العربية الآن؟'
'النسخة 1.0.9 من Najm تعمل على Windows (جديد)'
'لا إله، الألف واللام معا'
'C:\dev> مرحبا'
'- عنصر في قائمة'
'│ داخل صندوق │'
'plain English stays exactly as it was'
'שלום עולם'
''
'@ | Set-Content $demo -Encoding utf8

$directory = Split-Path $Exe
New-Item -ItemType File -Force (Join-Path $directory 'najm.portable') | Out-Null
@"
font-family = Cascadia Mono NF
font-size = 20
cursor-style-blink = false
command = pwsh -NoLogo -NoProfile -NoExit -File $demo
window-save-state = never
window-width = 60
window-height = 14
auto-update = off
"@ | Set-Content (Join-Path $directory 'config.ghostty')

$process = Start-Process $Exe -PassThru
for ($i = 0; $i -lt 60 -and $process.Refresh() -eq $null -and $process.MainWindowHandle -eq 0; $i++) {
    Start-Sleep -Milliseconds 500
}
$window = $process.MainWindowHandle
if ($window -eq 0) { throw 'Najm never opened a window' }
[void][Win]::SetForegroundWindow($window)
Start-Sleep -Seconds 8
Save-Shot $window 'bidi-text'

# Arabic typed at a prompt: the cursor has to stay on the cell being typed.
[System.Windows.Forms.SendKeys]::SendWait('سلام')
Start-Sleep -Seconds 2
Save-Shot $window 'bidi-typed'
[System.Windows.Forms.SendKeys]::SendWait('{LEFT}{LEFT}')
Start-Sleep -Seconds 1
Save-Shot $window 'bidi-cursor-moved'

# Double-click on the rightmost letters of the first line: the word under the
# mouse, the first word written, is what must highlight.
$rect = New-Object Win+RECT
[void][Win]::GetWindowRect($window, [ref]$rect)
[void][Win]::SetCursorPos($rect.R - 40, $rect.T + 62)
Start-Sleep -Milliseconds 300
foreach ($click in 1, 2) {
    [Win]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
    [Win]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 80
}
Start-Sleep -Seconds 1
Save-Shot $window 'bidi-selected'

Stop-Process $process -Force

# A full-screen program that reverses its own Arabic, as Claude Code does on
# Windows. These lines must match the reference below: right order, joined.
$fullscreen = Join-Path $env:RUNNER_TEMP 'bidi-fullscreen.ps1'
@'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
function Reversed($text) { $chars = $text.ToCharArray(); [Array]::Reverse($chars); -join $chars }
[Console]::Write("$([char]27)[?1049h$([char]27)[H")
foreach ($line in 'سلام', 'الآن', 'لا إله، الألف واللام معا', 'مرحبا بالعالم') {
    [Console]::WriteLine((Reversed $line))
}
[Console]::WriteLine('Najm ' + (Reversed 'يدعم العربية') + ' English')
'@ | Set-Content $fullscreen -Encoding utf8
$process = Start-Process $Exe -PassThru -ArgumentList "--command=`"pwsh -NoLogo -NoProfile -NoExit -File $fullscreen`""
for ($i = 0; $i -lt 60 -and $process.Refresh() -eq $null -and $process.MainWindowHandle -eq 0; $i++) {
    Start-Sleep -Milliseconds 500
}
$window = $process.MainWindowHandle
if ($window -eq 0) { throw 'Najm never opened a second window' }
[void][Win]::SetForegroundWindow($window)
Start-Sleep -Seconds 8
Save-Shot $window 'bidi-fullscreen'
Stop-Process $process -Force

# The oracle: the same words and font drawn by Windows' own text engine, to
# tell a font's design from a shaping bug.
$collection = New-Object System.Drawing.Text.PrivateFontCollection
$collection.AddFontFile((Join-Path $userFonts $font.Name))
$reference = New-Object System.Drawing.Bitmap 900, 240
$canvas = [System.Drawing.Graphics]::FromImage($reference)
$canvas.Clear([System.Drawing.Color]::FromArgb(40, 44, 52))
$canvas.TextRenderingHint = 'AntiAliasGridFit'
$face = New-Object System.Drawing.Font $collection.Families[0], 20
$format = New-Object System.Drawing.StringFormat ([System.Drawing.StringFormatFlags]::DirectionRightToLeft)
$lines = 'سلام', 'الآن', 'لا إله، الألف واللام معا', 'مرحبا بالعالم'
foreach ($i in 0..($lines.Count - 1)) {
    $area = New-Object System.Drawing.RectangleF 0, (8 + 56 * $i), 880, 56
    $canvas.DrawString($lines[$i], $face, [System.Drawing.Brushes]::White, $area, $format)
}
$reference.Save((Join-Path $OutputDirectory 'bidi-reference.png'), [System.Drawing.Imaging.ImageFormat]::Png)
