' run_chrome_debug_hidden.vbs (2026-10-29) -- hidden wrapper for
' start_chrome_debug.ps1 (no console flash). Used by TM-Chrome-Debug task.
CreateObject("Wscript.Shell").Run _
  "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""C:\Users\shawn\tm-bridge\start_chrome_debug.ps1""", 0, False
