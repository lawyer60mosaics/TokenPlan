param(
    [ValidateSet('text', 'progress', 'blank', 'settings')]
    [string]$Region = 'text',
    [switch]$ExpectStationary,
    [int]$ProcessId = 0
)
$ErrorActionPreference = 'Stop'
$exePath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../src-tauri/target/debug/volcengine-token-plan.exe'))
$instances = @(Get-Process -Name 'volcengine-token-plan' -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exePath })
if ($ProcessId) { $instances = @($instances | Where-Object { $_.Id -eq $ProcessId }) }
if ($instances.Count -ne 1) { throw 'Exactly one matching application must be running.' }
$appProcess = $instances[0]
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class DragProbe {
    [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct Point { public int X, Y; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out Rect r);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out Point p);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(Point p);
    [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint flags);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
    [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
}
'@
[void][DragProbe]::SetProcessDpiAwarenessContext([IntPtr](-4))
[void][DragProbe]::SetThreadDpiAwarenessContext([IntPtr](-4))
$handle = $appProcess.MainWindowHandle
if ($handle -eq [IntPtr]::Zero) { throw 'Main window not available.' }
$before = New-Object DragProbe+Rect
$after = New-Object DragProbe+Rect
$cursor = New-Object DragProbe+Point
[void][DragProbe]::GetWindowRect($handle, [ref]$before)
[void][DragProbe]::GetCursorPos([ref]$cursor)
[void][DragProbe]::SetForegroundWindow($handle)
$scale = ($before.Right - $before.Left) / 480.0
$offset = switch ($Region) { 'text' { @(68, 112) }; 'progress' { @(90, 385) }; 'blank' { @(10, 535) }; 'settings' { @(290, 105) } }
$x = $before.Left + [int]($offset[0] * $scale)
$y = $before.Top + [int]($offset[1] * $scale)
$hitPoint = New-Object DragProbe+Point
$hitPoint.X = $x
$hitPoint.Y = $y
if ([DragProbe]::GetAncestor([DragProbe]::WindowFromPoint($hitPoint), 2) -ne $handle) { throw 'Test point is obscured by another window; refusing to click.' }
try {
    [void][DragProbe]::SetCursorPos($x, $y)
    [DragProbe]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 750
    for ($i = 1; $i -le 12; $i++) {
        [void][DragProbe]::SetCursorPos(($x + $i * 5), ($y + $i * 3))
        Start-Sleep -Milliseconds 80
    }
} finally {
    [DragProbe]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 300
    [void][DragProbe]::SetCursorPos($cursor.X, $cursor.Y)
}
Start-Sleep -Milliseconds 200
[void][DragProbe]::GetWindowRect($handle, [ref]$after)
$dx = $after.Left - $before.Left
$dy = $after.Top - $before.Top
$passed = if ($ExpectStationary) { $dx -eq 0 -and $dy -eq 0 } else { [Math]::Abs($dx - 60) -le 5 -and [Math]::Abs($dy - 36) -le 5 }
[pscustomobject]@{ Region = $Region; Before = "$($before.Left),$($before.Top)"; After = "$($after.Left),$($after.Top)"; Delta = "$dx,$dy"; Expected = $(if ($ExpectStationary) { '0,0' } else { '60,36' }); Passed = $passed } | ConvertTo-Json -Compress
if (-not $passed) { exit 1 }
