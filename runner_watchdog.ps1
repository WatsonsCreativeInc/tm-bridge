# runner_watchdog.ps1 (2026-10-29) — every minute, checks the
# @typingmind/mcp runner on port 50880. If dead, relaunches it hidden
# using the persisted token in runner_token.txt.
# Runs via Scheduled Task "TM-Runner-Watchdog" (wscript hidden wrapper).
$ErrorActionPreference = 'SilentlyContinue'
$log = 'C:\Users\shawn\.tm-bridge\runner_watchdog.log'
$stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
$listener = Get-NetTCPConnection -LocalPort 50880 -State Listen -ErrorAction SilentlyContinue
if (-not $listener) {
    Add-Content -Path $log -Value "$stamp DOWN - relaunching runner"
    & 'C:\Users\shawn\tm-bridge\run_runner_hidden.vbs' | Out-Null
    Start-Sleep -Seconds 8
    $check = Get-NetTCPConnection -LocalPort 50880 -State Listen -ErrorAction SilentlyContinue
    if ($check) { Add-Content -Path $log -Value "$stamp UP (pid $($check[0].OwningProcess))" }
    else { Add-Content -Path $log -Value "$stamp FAILED to start" }
}
