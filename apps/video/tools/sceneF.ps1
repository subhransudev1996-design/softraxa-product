# Scene F: Stock + low stock, Excel import page, then three reports.
$Dir = $PSScriptRoot; $Click = "$Dir\click.ps1"
& "$Dir\win.ps1"; Start-Sleep 1
& $Click 92 473; Start-Sleep 3.5       # Stock
& $Click 922 188; Start-Sleep 4        # Low stock
& $Click 108 627; Start-Sleep 5        # Import products
& $Click 80 201; Start-Sleep 3         # Reports
& $Click 800 150; Start-Sleep 5        # Sales report
& $Click 275 73; Start-Sleep 2
& $Click 800 283; Start-Sleep 5        # Profit report
& $Click 275 73; Start-Sleep 2
& $Click 800 750; Start-Sleep 5        # GST report
