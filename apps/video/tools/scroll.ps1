# scroll.ps1 X Y NOTCHES — mouse wheel at logical X,Y (negative = scroll down).
param([int]$x,[int]$y,[int]$n)
Add-Type @"
using System; using System.Runtime.InteropServices;
public class SW { [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y); [DllImport("user32.dll")] public static extern void mouse_event(int f,int x,int y,int d,int e); }
"@
[SW]::SetProcessDPIAware() | Out-Null
[SW]::SetCursorPos([int]($x*1.2),[int]($y*1.2)); Start-Sleep -Milliseconds 100
for ($i=0; $i -lt [math]::Abs($n); $i++) { [SW]::mouse_event(0x0800,0,0,[math]::Sign($n)*120,0); Start-Sleep -Milliseconds 60 }
