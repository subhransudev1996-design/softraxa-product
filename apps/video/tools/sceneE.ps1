# Scene E: New purchase from a supplier, on credit.
$Dir = $PSScriptRoot; $Click = "$Dir\click.ps1"
function TypeIt($text) { & "$Dir\keys.ps1" -text $text -delay 110 }
function Press($keys) { & "$Dir\keys.ps1" -raw $keys }
& "$Dir\win.ps1"; Start-Sleep 1
Press "{ESC}"; Start-Sleep 0.5
& $Click 92 123; Start-Sleep 2.5       # Dashboard
& $Click 907 90; Start-Sleep 3         # New purchase
& $Click 900 148; Start-Sleep 1.8; & $Click 667 821; Start-Sleep 1.5   # supplier
& $Click 920 293; Start-Sleep 1.5; TypeIt "Amul Butter"; Start-Sleep 1.5; & $Click 700 308; Start-Sleep 1.5
& $Click 735 408; Press "{END}{BS 8}"; TypeIt "24"; & $Click 862 410; Press "{END}{BS 8}"; TypeIt "52"; Start-Sleep 0.8; & $Click 878 528; Start-Sleep 1.5
& $Click 920 357; Start-Sleep 1.5; TypeIt "Amul Paneer"; Start-Sleep 1.5; & $Click 700 308; Start-Sleep 1.5
& $Click 735 408; Press "{END}{BS 8}"; TypeIt "12"; & $Click 862 410; Press "{END}{BS 8}"; TypeIt "58"; Start-Sleep 0.8; & $Click 878 528; Start-Sleep 1.5
& $Click 536 642; Start-Sleep 2           # Credit
Start-Sleep 1
& $Click 900 744; Press "{TAB}{TAB}"; Start-Sleep 2.5   # scroll to the total
& $Click 920 833; Start-Sleep 4        # Save purchase
