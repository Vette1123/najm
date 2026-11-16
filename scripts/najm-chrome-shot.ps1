# Captures the window chrome from the najm.exe a CI run just built: the tab
# strip with two tabs, the close prompt's card over the terminal, its Close
# button hovered, and the window after Esc. Evidence a unit test cannot give:
# what the window really draws. Runs on a GitHub Windows runner
# (.github/workflows/najm-ci.yml), never on a developer's machine: it moves the
# mouse and types into whatever window is in front.
param(
    [Parameter(Mandatory)][string]$Exe,
    [Parameter(Mandatory)][string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class ChromeWin {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr h, EnumProc f, IntPtr l);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  // The first visible child whose text is `text`, or zero.
  public static IntPtr FindChild(IntPtr parent, string text) {
    IntPtr found = IntPtr.Zero;
    EnumChildWindows(parent, (h, l) => {
      var s = new StringBuilder(256);
      GetWindowText(h, s, 256);
      if (s.ToString() == text && IsWindowVisible(h)) { found = h; return false; }
      return true;
    }, IntPtr.Zero);
    return found;
  }
}
'@

function Save-Shot([IntPtr]$window, [string]$name) {
    $rect = New-Object ChromeWin+RECT
    [void][ChromeWin]::GetWindowRect($window, [ref]$rect)
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

$directory = Split-Path $Exe
New-Item -ItemType File -Force (Join-Path $directory 'najm.portable') | Out-Null
# `always`: the prompt shows even though shell integration reports an idle
# prompt. `cmd.exe` keeps PowerShell history out of the run.
@"
command = cmd.exe /k echo Najm close-prompt capture
confirm-close-surface = always
cursor-style-blink = false
font-size = 14
window-save-state = never
window-width = 140
window-height = 30
auto-update = off
keybind = ctrl+shift+t=new_tab
"@ | Set-Content (Join-Path $directory 'config.ghostty')

$process = Start-Process $Exe -PassThru
for ($i = 0; $i -lt 60 -and $process.Refresh() -eq $null -and $process.MainWindowHandle -eq 0; $i++) {
    Start-Sleep -Milliseconds 500
}
$window = $process.MainWindowHandle
if ($window -eq 0) { throw 'Najm never opened a window' }
[void][ChromeWin]::SetForegroundWindow($window)
Start-Sleep -Seconds 5

[System.Windows.Forms.SendKeys]::SendWait('^+t')
Start-Sleep -Seconds 3
Save-Shot $window 'chrome-tabs'

# WM_CLOSE asks "Close this window?" for both tabs.
[void][ChromeWin]::PostMessage($window, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Seconds 2
Save-Shot $window 'chrome-close-card'

$close = [ChromeWin]::FindChild($window, 'Close')
if ($close -ne [IntPtr]::Zero) {
    $rect = New-Object ChromeWin+RECT
    [void][ChromeWin]::GetWindowRect($close, [ref]$rect)
    [void][ChromeWin]::SetCursorPos([int](($rect.L + $rect.R) / 2), [int](($rect.T + $rect.B) / 2))
    Start-Sleep -Seconds 1
    Save-Shot $window 'chrome-close-hover'
    [void][ChromeWin]::SetCursorPos($rect.L - 400, $rect.B + 300)
} else {
    Write-Host 'No visible child named Close: the hover shot is skipped.'
}

[System.Windows.Forms.SendKeys]::SendWait('{ESC}')
Start-Sleep -Seconds 2
Save-Shot $window 'chrome-after-esc'

Stop-Process $process -Force
