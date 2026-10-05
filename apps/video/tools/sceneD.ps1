# Scene D: Add product with a Box price (not saved).
$Dir = $PSScriptRoot; $Click = "$Dir\click.ps1"
function TypeIt($text) { & "$Dir\keys.ps1" -text $text -delay 130 }
& "$Dir\win.ps1"; Start-Sleep 1
& $Click 92 123; Start-Sleep 2.5       # Dashboard
& $Click 792 90; Start-Sleep 3         # Add product
& $Click 800 142; TypeIt "Gold Flake"; Start-Sleep 0.8
& $Click 700 283; Start-Sleep 1.2; & $Click 333 634; Start-Sleep 1   # Unit: Piece
& $Click 583 337; TypeIt "Box"; Start-Sleep 0.6
& $Click 1250 337; TypeIt "10"; Start-Sleep 1.5
& $Click 475 737; TypeIt "8"; Start-Sleep 0.5
& $Click 917 737; TypeIt "10"; Start-Sleep 1.2
& $Click 800 412; TypeIt "95"; Start-Sleep 3.5   # Selling price of 1 Box
