# keys.ps1 -text "sugar" [-delay 120] [-raw]  — types into the Dukania window.
# Without -raw each character is typed one by one (looks human); with -raw the
# string is SendKeys syntax, e.g. "{ENTER}", "{F12}", "{END}{BS 10}".
param([string]$text, [int]$delay = 120, [switch]$raw)
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System; using System.Runtime.InteropServices;
public class KF { [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h); }
"@
$p = Get-Process softraxa_inventory | Select-Object -First 1
[KF]::SetForegroundWindow($p.MainWindowHandle) | Out-Null
Start-Sleep -Milliseconds 120
if ($raw) { [System.Windows.Forms.SendKeys]::SendWait($text); exit }
foreach ($c in $text.ToCharArray()) {
  $s = [string]$c
  if ('+^%~(){}[]'.Contains($s)) { $s = '{' + $s + '}' }
  [System.Windows.Forms.SendKeys]::SendWait($s)
  Start-Sleep -Milliseconds $delay
}
