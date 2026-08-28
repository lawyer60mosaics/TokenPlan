$ErrorActionPreference = 'Stop'
$exePath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../src-tauri/target/debug/volcengine-token-plan.exe'))
$instances = @(Get-Process -Name 'volcengine-token-plan' -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exePath })
if ($instances.Count -ne 1) { throw 'Exactly one application must be running.' }
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class WidgetCapture {
    [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out Rect r);
    [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr context);
}
'@
[void][WidgetCapture]::SetProcessDpiAwarenessContext([IntPtr](-4))
$rect = New-Object WidgetCapture+Rect
if (-not [WidgetCapture]::GetWindowRect($instances[0].MainWindowHandle, [ref]$rect)) { throw 'Window not available.' }
$bitmap = New-Object Drawing.Bitmap ($rect.Right - $rect.Left), ($rect.Bottom - $rect.Top)
$graphics = [Drawing.Graphics]::FromImage($bitmap)
try {
    $graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bitmap.Size)
    $destination = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../tests/widget-live.png'))
    $bitmap.Save($destination, [Drawing.Imaging.ImageFormat]::Png)
    Write-Output $destination
} finally { $graphics.Dispose(); $bitmap.Dispose() }
