' run_runner_watchdog_hidden.vbs (2026-10-29) — hidden wrapper for the
' runner watchdog PowerShell script (no console flash).
CreateObject("Wscript.Shell").Run _
  "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""C:\Users\shawn\tm-bridge\runner_watchdog.ps1""", 0, False
