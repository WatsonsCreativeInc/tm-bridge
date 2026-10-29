' run_kit_sync_hidden.vbs (2026-10-29) -- hidden wrapper for the weekly
' kit sync (push-kit.ps1). No console flash.
CreateObject("Wscript.Shell").Run _
  "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""C:\Users\shawn\tm-bridge\push-kit.ps1"" ""scheduled weekly kit sync""", 0, False
