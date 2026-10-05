# click.ps1 X Y — left-click at X,Y in LOGICAL pixels (this PC runs at 120% scaling).
param([int]$x,[int]$y)
Add-Type @"
using System; using System.Runtime.InteropServices;
public class M { [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y); [DllImport("user32.dll")] public static extern void mouse_event(int f,int x,int y,int d,int e); }
"@
[M]::SetProcessDPIAware() | Out-Null
$px=[int]($x*1.2); $py=[int]($y*1.2)
[M]::SetCursorPos($px,$py); Start-Sleep -Milliseconds 150; [M]::mouse_event(2,0,0,0,0); [M]::mouse_event(4,0,0,0,0)
