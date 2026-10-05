# win.ps1 — brings the Dukania window to the front, maximized.
Add-Type @"
using System; using System.Runtime.InteropServices;
public class WW { [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
 [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h,int c);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h); }
"@
[WW]::SetProcessDPIAware() | Out-Null
$p = Get-Process softraxa_inventory | Select-Object -First 1
[WW]::ShowWindow($p.MainWindowHandle, 3) | Out-Null
[WW]::SetForegroundWindow($p.MainWindowHandle) | Out-Null
