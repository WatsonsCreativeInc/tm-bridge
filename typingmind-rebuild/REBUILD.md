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
3. `git clone https://github.com/WatsonsCreativeInc/tm-bridge.git`
4. Copy `tm-bridge.js` + launchers to `C:\Users\shawn\tm-bridge\`,
   build qbo-mcp (npm install + tsc in `C:\Users\shawn\qbo-mcp\`).
5. Re-register 3 scheduled tasks (commands in RUNBOOK.md section 2).
6. Re-enter 6 secrets into Credential Manager (RUNBOOK section 6).
7. Then follow Scenario A from step 1.

## Capture discipline (prevents the NEXT loss)

After any config/plugin/source change in TypingMind:
- Update `mcp-servers.json` / `plugin-inventory.md` / drop source copies into
  `sources\`
- Then push: `git -C C:\Users\shawn\tm-bridge\.git-backup add -A && git -C ... commit && git -C ... push`
- Or just tell the AI: "snapshot the config" — it reads the live config via
  the bridge and commits it.
