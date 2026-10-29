' run_watchdog_hidden.vbs (2026-10-29) — run watchdog.ps1 with NO console
' flash. PowerShell -WindowStyle Hidden still flashes a frame; wrapping in
' wscript Run(...,0) means no console host is created at all.
CreateObject("Wscript.Shell").Run _
  "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""C:\Users\shawn\tm-bridge\watchdog.ps1""", 0, False
