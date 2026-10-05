# Scene A: sugar by the kg, a tray of eggs and 6 loose eggs, Maggi, checkout,
# bill created. The recorder runs separately. Starts on the Dashboard.
# NB: PowerShell variables are case-insensitive: never name one $T next to a $t parameter.
$Dir = $PSScriptRoot; $Click = "$Dir\click.ps1"
function TypeIt($text) { & "$Dir\keys.ps1" -text $text -delay 170 }
function Press($keys) { & "$Dir\keys.ps1" -raw $keys }
& "$Dir\win.ps1"; Start-Sleep 1.5
& $Click 92 123; Start-Sleep 2.5       # Dashboard
& $Click 1093 89; Start-Sleep 2        # New Bill
& $Click 750 133; Start-Sleep 0.6      # focus the search box
TypeIt "sugar"; Start-Sleep 1.4; Press "{ENTER}"; Start-Sleep 1.6
TypeIt "2"; Start-Sleep 0.8; Press "{ENTER}"; Start-Sleep 1.8
TypeIt "eggs"; Start-Sleep 1.4; Press "{ENTER}"; Start-Sleep 1.8
& $Click 912 402; Start-Sleep 1.6      # Tray
& $Click 800 557; Start-Sleep 1.8      # Add 1 Tray
TypeIt "eggs"; Start-Sleep 1.4; Press "{ENTER}"; Start-Sleep 1.6
TypeIt "6"; Start-Sleep 0.8; Press "{ENTER}"; Start-Sleep 1.8
TypeIt "maggi"; Start-Sleep 1.4; Press "{ENTER}"; Start-Sleep 1.6
TypeIt "4"; Start-Sleep 0.8; Press "{ENTER}"; Start-Sleep 2.5
Press "{F12}"; Start-Sleep 3.5
Press "{F12}"; Start-Sleep 4.5
