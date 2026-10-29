' run_bridge_hidden.vbs (2026-10-29) — launch tm-bridge with NO console window.
' Used by Scheduled Task "TM-Bridge". wscript is a windowless host, so
' node never gets a visible console on the desktop.
CreateObject("Wscript.Shell").Run _
  """C:\Program Files\nodejs\node.exe"" ""C:\Users\shawn\tm-bridge\tm-bridge.js""", 0, False
