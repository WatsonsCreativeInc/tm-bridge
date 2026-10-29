# chrome_cdp_watchdog.ps1 (2026-10-29) -- minute-checked, launch-only-once
# semantics: if chrome is NOT running at all and 9222 is down, launch
# debug-enabled chrome ONCE per invocation, then rely on logon task next boot.
# NEVER kills or relaunches a browser the user started without the flag.
$ErrorActionPreference = 'SilentlyContinue'
$log = 'C:\Users\shawn\tm-bridge\chrome-debug.log'
$stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
$chrome = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
if (-not (Get-NetTCPConnection -LocalPort 9222 -State Listen -ErrorAction SilentlyContinue) -and
    -not (Get-Process chrome -ErrorAction SilentlyContinue)) {
  Add-Content $log "$stamp DOWN - no chrome, launching with debug port"
  Start-Process $chrome -ArgumentList '--remote-debugging-port=9222'
  Start-Sleep 4
  if ([bool](Get-NetTCPConnection -LocalPort 9222 -State Listen -ErrorAction SilentlyContinue)) {
    Add-Content $log "$stamp UP (debug-enabled)"
  } else { Add-Content $log "$stamp FAILED" }
}
