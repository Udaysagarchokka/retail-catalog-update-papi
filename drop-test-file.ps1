# ============================================================
# drop-test-file.ps1
# Run this EVERY TIME after restarting the app in Studio.
# It clears stuck in-process files and drops a fresh CSV.
# Usage: Right-click -> Run with PowerShell
# ============================================================

$root = Split-Path -Parent $MyInvocation.MyCommand.Path

# Clean stuck in-process files
$stuck = Get-ChildItem "$root\data\in-process\" | Where-Object { $_.Name -ne ".gitkeep" }
if ($stuck) {
    $stuck | ForEach-Object {
        Move-Item $_.FullName "$root\data\archive\" -Force
        Write-Host "Archived: $($_.Name)"
    }
} else {
    Write-Host "In-process folder already clean."
}

# Drop fresh file with current timestamp
$timestamp = Get-Date -Format "yyyyMMdd_HHmm"
$newName   = "CATALOG_FULL_$timestamp.csv"
$source    = "$root\src\main\resources\sample-data\CATALOG_FULL_20260911_0600.csv"
Copy-Item $source "$root\data\input\$newName" -Force

Write-Host "`nDropped: $newName"
Write-Host "Now watch Studio console for: 'Inbound file detected: $newName'"
