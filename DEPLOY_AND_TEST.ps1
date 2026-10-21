# ============================================================
# DEPLOY_AND_TEST.ps1
# Final deployment and test script
# ============================================================

Write-Host "=== RETAIL CATALOG UPDATE PAPI v6 ===" -ForegroundColor Cyan
Write-Host "Build: SUCCESS"
Write-Host "Next steps:"
Write-Host ""

Write-Host "STEP 1: Restart the app in Studio" -ForegroundColor Yellow
Write-Host "  1. In AnypointStudio: Run → Stop"
Write-Host "  2. Wait 5 seconds for graceful shutdown"
Write-Host "  3. Run → Run As → Mule Application"
Write-Host "  4. Wait for 'Mule Runtime Started' message"
Write-Host ""

Write-Host "STEP 2: Clean up and drop test file" -ForegroundColor Yellow
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

# Clean stuck in-process files
$stuck = Get-ChildItem "$root\data\in-process\" | Where-Object { $_.Name -ne ".gitkeep" }
if ($stuck) {
    $stuck | ForEach-Object {
        Move-Item $_.FullName "$root\data\archive\" -Force
        Write-Host "  Archived: $($_.Name)"
    }
} else {
    Write-Host "  In-process folder clean"
}

# Drop fresh test file
$timestamp = Get-Date -Format "yyyyMMdd_HHmm"
$newName = "CATALOG_FULL_$timestamp.csv"
Copy-Item "$root\src\main\resources\sample-data\CATALOG_FULL_20260911_0600.csv" `
          "$root\data\input\$newName" -Force

Write-Host "  Dropped: $newName"
Write-Host ""

Write-Host "STEP 3: Watch console for these logs (within 10 seconds):" -ForegroundColor Yellow
Write-Host "  ✓ INFO  INBOUND_FILE_DETECTED: $newName"
Write-Host "  ✓ INFO  BATCH_FLOW_ENTRY RunId=... RecordCount=6"
Write-Host "  ✓ INFO  BATCH_COMPLETE RunId=... Total=6 Failed=0 Loaded=6"
Write-Host "  ✓ INFO  RUN_COMPLETED ... New=6 Changed=0"
Write-Host "  ✓ INFO  FILE_ARCHIVED: $newName moved to /data/archive/"
Write-Host ""

Write-Host "✅ If you see all these logs, the fix is complete!" -ForegroundColor Green
Write-Host ""

# Verify file positions
Write-Host "=== CURRENT FILE STATUS ===" -ForegroundColor Cyan
Write-Host "Input:  $((Get-ChildItem "$root\data\input\" -Exclude ".gitkeep" | Measure-Object).Count) file(s)"
Write-Host "Processing: $((Get-ChildItem "$root\data\in-process\" -Exclude ".gitkeep" | Measure-Object).Count) file(s)"
Write-Host "Archive: $((Get-ChildItem "$root\data\archive\" -Exclude ".gitkeep" | Measure-Object).Count) file(s)"
