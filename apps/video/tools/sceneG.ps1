# Scene G: sugar by amount (Rs 50), then choose a customer with F4.
$Dir = $PSScriptRoot; $Click = "$Dir\click.ps1"
function TypeIt($text) { & "$Dir\keys.ps1" -text $text -delay 140 }
function Press($keys) { & "$Dir\keys.ps1" -raw $keys }
& "$Dir\win.ps1"; Start-Sleep 1
& $Click 92 123; Start-Sleep 2.5       # Dashboard
& $Click 1093 89; Start-Sleep 2
& $Click 750 133; Start-Sleep 0.6      # focus the search box
TypeIt "sugar"; Start-Sleep 1.4; Press "{ENTER}"; Start-Sleep 2
& $Click 915 432; Press "{END}{BS 8}"; Start-Sleep 0.4; TypeIt "50"; Start-Sleep 3
Press "{ENTER}"; Start-Sleep 2.5
Press "{F4}"; Start-Sleep 3.5
