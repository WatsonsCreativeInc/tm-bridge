# tm-bridge watchdog (2026-10-29)
# Runs every minute via Scheduled Task "TM-Bridge-Watchdog".
# If nothing is listening on 127.0.0.1:8787, starts the TM-Bridge task.
# Complements (not duplicates) TM-Bridge: catches force-kills, silent
# exits, and boot scenarios that RestartOnFailure semantics miss.
$log = "C:\Users\shawn\tm-bridge\watchdog.log"
$stamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
try {
    $listener = Get-NetTCPConnection -LocalPort 8787 -State Listen -ErrorAction SilentlyContinue
    if (-not $listener) {
        Add-Content -Path $log -Value "$stamp DOWN - starting bridge"
        Start-ScheduledTask -TaskName "TM-Bridge"
        Start-Sleep -Seconds 5
        $check = Get-NetTCPConnection -LocalPort 8787 -State Listen -ErrorAction SilentlyContinue
        if ($check) { Add-Content -Path $log -Value "$stamp UP (pid $($check[0].OwningProcess))" }
        else { Add-Content -Path $log -Value "$stamp FAILED to start" }
    }
} catch {
    Add-Content -Path $log -Value "$stamp ERROR $_"
}
