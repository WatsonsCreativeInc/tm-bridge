# start_chrome_debug.ps1 (2026-10-29) -- ensure Chrome runs with CDP.
# Logic:
#   9222 listening            -> nothing to do (already debug-enabled)
#   chrome running, no 9222   -> log only (cannot inject flag into running
#                                process; do NOT kill the user's browser)
#   chrome not running        -> launch with --remote-debugging-port=9222
# Used by: scheduled task TM-Chrome-Debug (at logon) and as a manual check.
$ErrorActionPreference = 'SilentlyContinue'
$log = 'C:\Users\shawn\tm-bridge\chrome-debug.log'
$stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
$chrome = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
$flag = [bool](Get-NetTCPConnection -LocalPort 9222 -State Listen -ErrorAction SilentlyContinue)
$running = [bool](Get-Process chrome -ErrorAction SilentlyContinue)

if ($flag) {
  Add-Content $log "$stamp OK - 9222 listening"
} elseif ($running) {
  Add-Content $log "$stamp NOTE - chrome running WITHOUT debug port (manual relaunch needed for CDP)"
} else {
  Start-Process $chrome -ArgumentList '--remote-debugging-port=9222'
  Start-Sleep -Seconds 4
  if ([bool](Get-NetTCPConnection -LocalPort 9222 -State Listen -ErrorAction SilentlyContinue)) {
    Add-Content $log "$stamp LAUNCHED chrome with debug port (pid $((Get-Process chrome | Select-Object -First 1).Id))"
  } else {
    Add-Content $log "$stamp FAILED - chrome launched but 9222 not listening"
  }
}
