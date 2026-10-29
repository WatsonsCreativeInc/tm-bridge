# REBUILD — Crash Recovery Playbook

> If TypingMind (or the whole machine) is lost, follow these steps in order.
> Total time: ~10 minutes for a browser crash, ~25 for a fresh machine.

## Scenario A: Browser crash (TypingMind config lost, machine intact)

1. **Wait 60s.** Watchdogs auto-revive bridge + runner.
   - Check: run `restore-typingmind.cmd` — every row should say OK.
2. **Import MCP JSON.** TypingMind > Plugins > import:
   `C:\Users\shawn\tm-bridge\typingmind-rebuild\mcp-servers.json`
3. **Add the bridge OpenAPI plugin** (bootstrap):
   URL `http://127.0.0.1:8787/openapi.json`, header `x-tm-key`,
   key from `TMB:tmKey` (see plugin-inventory.md).
4. **Re-add native plugins** per `plugin-inventory.md`.
5. **Re-upload sources** from `sources\`.
6. **Toggle each connector once** so servers respawn.

## Scenario B: Fresh machine (everything gone)

1. Install Node.js (winget `OpenJS.NodeJS.LTS`).
2. Install AutoHotkey v2 (winget `AutoHotkey.AutoHotkey`).
3. Set execution policy: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force`
4. `git clone https://github.com/WatsonsCreativeInc/tm-bridge.git`
5. Copy `tm-bridge.js` + all launcher/watchdog scripts to `C:\Users\shawn\tm-bridge\`,
   build qbo-mcp (npm install + tsc in `C:\Users\shawn\qbo-mcp\`).
6. Re-register 5 scheduled tasks (TM-Bridge, TM-Bridge-Watchdog, TM-Runner-Watchdog,
   TM-Chrome-Debug, TM-Kit-Sync) - commands in RUNBOOK section 2, always with
   `-AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Days 3650)`.
7. Re-enter 6 secrets into Credential Manager (RUNBOOK section 6), using
   `credman.ps1 -Set -Name <name>` (value via stdin, not command line).
8. Then follow Scenario A from step 1.

## Chrome Debug Port (CDP)

- Task `TM-Chrome-Debug` (logon) launches Chrome with `--remote-debugging-port=9222`
  if Chrome isn't running; `chrome_cdp_watchdog.ps1` is available for minute-level
  coverage if ever registered.
- If Chrome is running WITHOUT the flag, neither script kills it - relaunch
  Chrome manually (or just close all Chrome windows and run
  `start_chrome_debug.ps1`) to get CDP back.
- Why CDP matters: it enables live reading/writing of TypingMind browser
  storage (config capture, restore verification) without closing the browser.

## Capture discipline (prevents the NEXT loss)

After any config/plugin/source change in TypingMind:
- Update `mcp-servers.json` / `plugin-inventory.md` / drop source copies into
  `sources\`
- Then push: `git -C C:\Users\shawn\tm-bridge\.git-backup add -A && git -C ... commit && git -C ... push`
- Or just tell the AI: "snapshot the config" — it reads the live config via
  the bridge and commits it.
