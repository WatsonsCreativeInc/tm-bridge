# RUNBOOK — Shawn's MCP / TypingMind Infrastructure Estate

> Last verified: 2026-10-29. Any future session (or Shawn) should be able to
> audit, diagnose, or repair the entire automation estate from this one file.
> Memory-graph context: search for `INFRASTATE` in the knowledge graph.

---

## 1. Architecture Overview

```
TypingMind (browser)
   │
   ├─ @typingmind/mcp runner  ← hidden, port 50880, watchdog-protected
   │     └─ spawns ~13 stdio MCP servers (filesystem, github, woo, qbo,
   │        desktop-commander, exa, gsc, win-cli, playwright, memory, ...)
   │
   └─ tm-bridge (REST)        ← hidden, port 8787, watchdog-protected
         └─ 19 tools: shell, files, GitHub, Exa, Woo, QBO, Render,
            GSC, memory-graph, Chrome-control
```

**Design principle:** no interactive console windows, no manual babysitting.
Everything self-heals within ~60 seconds (runner/bridge: <1s–60s).

## 2. Inventory

### Scheduled Tasks (Task Scheduler)
| Task | What it does | Trigger |
|---|---|---|
| `TM-Bridge` | Launches bridge hidden via wscript | At startup |
| `TM-Bridge-Watchdog` | Checks port 8787 every minute; revives via TM-Bridge task | Every 60s |
| `TM-Runner-Watchdog` | Checks port 50880 every minute; revives runner direct-node | Every 60s |

### Files in `C:\Users\shawn\tm-bridge\`
| File | Purpose |
|---|---|
| `tm-bridge.js` | The bridge itself (19 tools, localhost-only, x-tm-key gated) |
| `run_bridge_hidden.vbs` | Hidden wscript launcher for bridge |
| `run_watchdog_hidden.vbs` | Hidden wrapper for watchdog.ps1 |
| `watchdog.ps1` | Bridge watchdog (port 8787 check) |
| `run_runner_hidden.vbs` | Hidden launcher for @typingmind/mcp runner (direct node, dynamic npx-cache path) |
| `run_runner_watchdog_hidden.vbs` | Hidden wrapper for runner watchdog |
| `runner_watchdog.ps1` | Runner watchdog (port 50880 check) |
| `migrate-to-vault.ps1`, `credman.ps1`, `vault-test.js` | Vault tooling (used once) |
| `watchdog.log`, `~\.tm-bridge\runner_watchdog.log` | Recovery audit logs |
| `*.bak-*` | Backups (do not delete casually) |

### AutoHotkey v2 (installed 2026-10-29)
- Interpreter: `C:\Users\shawn\AppData\Local\Programs\AutoHotkey\v2\AutoHotkey64.exe` (per-user install, winget `AutoHotkey.AutoHotkey` v2.0.31, smoke-tested)
- Purpose: desktop-level automation (arbitrary app clicks/keys) beyond browser automation
- No hotkey scripts deployed yet — add as `.ahk` files; run with the exe path above
- Note: per-user install means a new Windows account needs its own install

### Config & Secrets
| Path | Contents |
|---|---|
| `C:\Users\shawn\.tm-bridge\config.json` | **NO plaintext secrets** — all 6 values are `vault:<name>` references |
| Windows Credential Manager | `TMB:tmKey`, `TMB:githubPat`, `TMB:exaApiKey`, `TMB:renderToken`, `TMB:wooKey`, `TMB:wooSecret` |

`tm-bridge.js` resolves `vault:` refs via Credential Manager (P/Invoke CredReadW,
EncodedCommand, synchronous before listen). A failed vault read logs
`[tm-bridge] vault read failed...` and the tool returns a "Missing X" error
rather than crashing.

### TypingMind MCP servers (browser-side config)
- All stdio servers except `quickbooks` launch via `npx`.
- **Pinned:** `chrome-devtools-mcp@1.12.0` (+ `--allow-unrestricted-paths`),
  `mcp-gsc@0.4.1`. Others float but re-resolve from npx cache.
- `quickbooks` runs direct node: `C:\Users\shawn\qbo-mcp\dist\index.js`.
- GSC OAuth app is **published to Production** → refresh token no longer
  expires every 7 days (that was the recurring-death root cause).

## 3. Standard Health Check (60-second audit)

```powershell
# Ports
(Get-NetTCPConnection -LocalPort 8787 -State Listen).OwningProcess
(Get-NetTCPConnection -LocalPort 50880 -State Listen).OwningProcess

# Bridge health
Invoke-RestMethod http://127.0.0.1:8787/health

# Recovery logs (recent DOWN/UP pairs = self-healed incidents)
Get-Content ~\.tm-bridge\runner_watchdog.log -Tail 5
Get-Content C:\Users\shawn\tm-bridge\watchdog.log -Tail 5

# Scheduled tasks alive?
Get-ScheduledTask -TaskName 'TM-*'
```

## 4. Failure Modes & Fixes

| Symptom | Likely cause | Fix |
|---|---|---|
| "Plugin Error ... (chrome-devtools)" in TypingMind | Transient during runner recovery | Wait ~60s; refresh page. Self-heals. |
| Bridge 401 on /call | Missing `x-tm-key` header, or vault read failed | Check `TMB:tmKey` in Credential Manager; check bridge startup log |
| GSC `invalid_grant` | (Historical) Testing-mode OAuth | Permanently fixed — Production publish. Only re-auth if token revoked manually |
| Runner won't start | Token file missing/empty | `~\.tm-bridge\runner_token.txt` must hold current TypingMind session token (rotate per browser session) |
| MCP server "Not connected" | Runner killed but TypingMind not reconnected | Toggle that plugin off/on in TypingMind |
| Task XML errors on edit | `-ExecutionTimeLimit 0` bug | Re-register with `New-TimeSpan -Days 3650` |
| Task won't run on battery | Default settings | Re-register with `-AllowStartIfOnBatteries -DontStopIfGoingOnBatteries` |
| min restart interval < 1 min | PT30S unsupported | Use 1 minute minimum |

## 5. Known Quirks

- `@typingmind/mcp` does **not** auto-respawn dead stdio children — you must
  toggle the plugin in TypingMind after killing a server process.
- `read_ssh_connections` (win-cli) always errors with a malformed Zod schema
  message — cosmetic; SSH is disabled in config. Ignore it.
- npx cache hash dirs (`_npx\<hash>`) change when packages update — the runner
  launcher resolves the newest `@typingmind/mcp` dynamically for this reason.
- `~\.tm-bridge\` also holds `kg.json` (bridge memory-graph) and GSC token file
  in `~\.mcp\`.
- The Documents `TypingMind JSON Config.txt` is a **stale export copy** — all
  secrets are `[REDACTED]` placeholders. Live config lives in TypingMind's
  browser storage. Do not treat the txt as authoritative.

## 6. Secret Rotation Procedure

1. Rotate at provider (GitHub → Settings → Developer settings, etc.)
2. Update the value in Credential Manager:
   ```powershell
   cmdkey /generic:TMB:githubPat /user:shawn /pass:<NEW_SECRET>
   ```
3. Restart bridge: `Stop-Process -Id ((Get-NetTCPConnection -LocalPort 8787 -State Listen).OwningProcess) -Force; Start-ScheduledTask TM-Bridge`
4. Verify end-to-end through the bridge, reading the key FROM the vault (see §7)
5. Never paste the new secret into config.json or chat

## 7. End-to-End Vault Verification (canonical test)

Read `TMB:tmKey` from Credential Manager via P/Invoke (never from config),
then call the bridge with it:

```powershell
$ps = @'
$s=@" 
using System;using System.Runtime.InteropServices;public static class CM{[StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)]public struct C{public int Flags;public int Type;public string TargetName;public string Comment;public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;public int CredentialBlobSize;public IntPtr CredentialBlob;public int Persist;public int AttributeCount;public IntPtr Attributes;public string TargetAlias;public string UserName;}[DllImport("advapi32.dll",CharSet=CharSet.Unicode,EntryPoint="CredReadW")]public static extern bool R(string t,int ty,int f,out IntPtr p);[DllImport("advapi32.dll",EntryPoint="CredFree")]public static extern void F(IntPtr c);}
"@;Add-Type -TypeDefinition $s;$p=[IntPtr]::Zero;if(-not [CM]::R('TMB:tmKey',1,0,[ref]$p)){exit 1};try{$c=[Runtime.InteropServices.Marshal]::PtrToStructure($p,[type][CM+C]);$b=New-Object byte[] $c.CredentialBlobSize;[Runtime.InteropServices.Marshal]::Copy($c.CredentialBlob,$b,0,$c.CredentialBlobSize);[Console]::Out.Write([Text.Encoding]::Unicode.GetString($b))}finally{[CM]::F($p)}
'@
$enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($ps))
$key = (powershell.exe -NoProfile -EncodedCommand $enc).Trim()
Invoke-RestMethod http://127.0.0.1:8787/call -Method Post `
  -Body '{"tool":"github_api","args":{"endpoint":"/user"}}' `
  -Headers @{ 'x-tm-key' = $key; 'Content-Type'='application/json' }
```
Expected: `status: 200`, login `WatsonsCreativeInc`.

## 8. Open Items / Future Work

- [x] ~~Estate backup to GitHub~~ (2026-10-29: core scripts pushed to WatsonsCreativeInc/tm-bridge)
- [ ] Email/SMS notification channel (SMTP app-password or Resend key) — deprioritized: Shawn is the on-machine watchdog until dedicated-server move
- [ ] Optional: pin `@playwright/mcp` (currently floats)
- [ ] Optional: QBO vault entries (`qbo` block not yet in config)
- [ ] When moving to a dedicated server: re-add watchdog→ntfy alerting (ntfy.sh topic `tt-radar` pattern already proven in Camp Radar's notifier.py)

## 9. Estate Backup (added 2026-10-29)

Core scripts are version-controlled in the public repo
`https://github.com/WatsonsCreativeInc/tm-bridge`:

| In repo | Purpose |
|---|---|
| `tm-bridge.js` | Bridge (vault-aware, host/origin gated) |
| `RUNBOOK.md` | This file |
| `run_bridge_hidden.vbs`, `run_watchdog_hidden.vbs`, `watchdog.ps1` | Bridge launch + watchdog |
| `run_runner_hidden.vbs`, `run_runner_watchdog_hidden.vbs`, `runner_watchdog.ps1` | Runner launch + watchdog |
| `credman.ps1`, `migrate-to-vault.ps1`, `vault-test.js` | Vault tooling |

**Never committed:** logs, `*.bak-*`, `runner_token.txt`, `config.json`
(secrets are in Credential Manager — vault is the only secret store, and the
vault is machine-local by design; see §6 for the rotation+restore procedure).
Local staging dir for pushes: `C:\Users\shawn\tm-bridge\.git-backup\`
(a git repo whose remote points at the GitHub repo). Update flow: copy
changed files into the staging dir → commit → push using the PAT read from
the vault (see §7 pattern; `Authorization: Bearer` header or git credential
manager — never plaintext in commands).

---

*Written 2026-10-29 during the INFRASTATE hardening session. Keep this file
updated when adding scheduled tasks, tools, or changing auth.*
