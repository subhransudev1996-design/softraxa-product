# Scene C: open the newest bill, Share PDF (opens in the browser), capture
# ONLY the PDF page (cropped, so no tabs or other windows are recorded),
# close the tab, return to the app and capture the dashboard.
$Dir = $PSScriptRoot; $Click = "$Dir\click.ps1"; $Raw = "$Dir\..\public\raw"
Add-Type -AssemblyName System.Windows.Forms
& "$Dir\win.ps1"; Start-Sleep 1.5
& $Click 93 278; Start-Sleep 3          # All invoices
& $Click 333 258; Start-Sleep 3.5       # newest bill
& $Click 591 606; Start-Sleep 8         # Share PDF -> opens in the browser
# crop to the PDF page only: 990 x 600 at (643,183)
ffmpeg -hide_banner -loglevel error -y -f gdigrab -offset_x 0 -offset_y 0 -video_size 1920x1080 -i desktop -frames:v 1 -vf "crop=990:600:643:183" "$Raw\pdf.png"
[System.Windows.Forms.SendKeys]::SendWait("^w"); Start-Sleep 1.5   # close the PDF tab
& "$Dir\win.ps1"; Start-Sleep 1.5
& $Click 92 123; Start-Sleep 4          # Dashboard
ffmpeg -hide_banner -loglevel error -y -f gdigrab -offset_x 0 -offset_y 0 -video_size 1920x1028 -i desktop -frames:v 1 "$Raw\dashboard.png"
