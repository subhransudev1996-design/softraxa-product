# Scene B: Customers -> Sunita Devi -> receive Rs 200 of her Rs 265 due.
$Dir = $PSScriptRoot; $Click = "$Dir\click.ps1"
function TypeIt($text) { & "$Dir\keys.ps1" -text $text -delay 170 }
function Press($keys) { & "$Dir\keys.ps1" -raw $keys }
& "$Dir\win.ps1"; Start-Sleep 1.5
& $Click 92 356; Start-Sleep 3.5       # Customers
& $Click 1213 252; Start-Sleep 3.5     # Sunita Devi
& $Click 922 313; Start-Sleep 2.5      # Receive payment
& $Click 800 302; Start-Sleep 0.5      # amount field
Press "{END}{BS 10}"; Start-Sleep 0.5
TypeIt "200"; Start-Sleep 2.5
& $Click 972 626; Start-Sleep 5        # Receive
