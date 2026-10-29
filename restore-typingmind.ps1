# restore-typingmind.ps1 (2026-10-29) -- ONE-COMMAND FULL RESTORAL
# Double-click restore-typingmind.cmd to run it.
# Modes:
#   (default)  verify + repair the machine-side stack, then print the exact
#              browser-side steps (with the MCP JSON ready to paste).
#   -CaptureExport <path>  parse a TypingMind data-export JSON and extract the
#              MCP/plugin config into the canonical kit (typingmind-rebuild\).
#   -Verify    check-only: no repairs, no writes beyond the kit folder.
param(
  [string]$CaptureExport = "",
  [switch]$Verify
)
$ErrorActionPreference = 'SilentlyContinue'
$home2 = 'C:\Users\shawn\tm-bridge'
$dot   = 'C:\Users\shawn\.tm-bridge'
$kit   = Join-Path $home2 'typingmind-rebuild'
$log   = @()
function Log($s) { $log += $s; Write-Host $s }

Log "=== TM RESTORAL - $(Get-Date -Format s) ==="

# ---------- 1. Kit scaffold ----------
foreach ($d in $kit, (Join-Path $kit 'sources'), (Join-Path $kit 'prompts')) {
  if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

# ---------- 2. Machine-side status ----------
$tasks = @('TM-Bridge','TM-Bridge-Watchdog','TM-Runner-Watchdog')
$taskState = @{}
foreach ($t in $tasks) {
  $taskState[$t] = [bool](Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue)
}
$port8787 = [bool](Get-NetTCPConnection -LocalPort 8787 -State Listen -ErrorAction SilentlyContinue)
$port50880 = [bool](Get-NetTCPConnection -LocalPort 50880 -State Listen -ErrorAction SilentlyContinue)
$bridgeHealth = $false
try { $bridgeHealth = [bool](Invoke-RestMethod http://127.0.0.1:8787/health -TimeoutSec 3).ok } catch {}
$node = Test-Path 'C:\Program Files\nodejs\node.exe'
$qbo  = Test-Path 'C:\Users\shawn\qbo-mcp\dist\index.js'
$ahk  = Test-Path 'C:\Users\shawn\AppData\Local\Programs\AutoHotkey\v2\AutoHotkey64.exe'

# Vault entries (6 required)
$credCount = 0
foreach ($n in 'tmKey','githubPat','exaApiKey','renderToken','wooKey','wooSecret') {
  $found = cmdkey /list 2>$null | Select-String -SimpleMatch "TMB:$n"
  if ($found) { $credCount++ }
}

# ---------- 3. Repairs (skipped in -Verify) ----------
if (-not $Verify) {
  if (-not $port8787) { Log "bridge down -> starting TM-Bridge task"; Start-ScheduledTask -TaskName 'TM-Bridge'; Start-Sleep 5 }
  if (-not $port50880) { Log "runner down -> starting TM-Runner-Watchdog"; Start-ScheduledTask -TaskName 'TM-Runner-Watchdog'; Start-Sleep 8 }
  if ($credCount -lt 6) { Log "VAULT INCOMPLETE: $credCount/6 entries - re-enter secrets per RUNBOOK section 6" }
} else {
  Log "(verify mode: no repairs attempted)"
}

# ---------- 4. Runner token refresh hint ----------
$tokenFile = Join-Path $dot 'runner_token.txt'
if (Test-Path $tokenFile) {
  $tok = (Get-Content $tokenFile -Raw).Trim()
  if ($tok) { Log "runner token file: present ($($tok.Length) chars)" }
  else { Log "runner token file: EMPTY - paste token from TypingMind connect screen" }
} else { Log "runner token file: MISSING - recreate from TypingMind connect screen" }

# ---------- 5. Capture mode: TypingMind export -> kit ----------
if ($CaptureExport -ne "") {
  if (-not (Test-Path $CaptureExport)) { Log "EXPORT NOT FOUND: $CaptureExport" }
  else {
    try {
      $exp = Get-Content $CaptureExport -Raw | ConvertFrom-Json
      $out = Join-Path $kit 'mcp-servers.json'
      $found = $null
      if ($exp.mcpServers) { $found = $exp.mcpServers }
      elseif ($exp.servers) { $found = $exp.servers }
      elseif ($exp.plugins) { $found = $exp.plugins }
      if ($found) {
        $found | ConvertTo-Json -Depth 10 | Set-Content $out -Encoding UTF8
        Log "CAPTURED: MCP config -> $out ($($found.PSObject.Properties.Name.Count) servers)"
      } else {
        Log "export parsed but no mcpServers/servers/plugins block found - inspect keys: $($exp.PSObject.Properties.Name -join ', ')"
      }
    } catch { Log "export parse failed: $_" }
  }
}

# ---------- 6. Canonical MCP JSON presence ----------
$mcpJson = Join-Path $kit 'mcp-servers.json'
if (-not (Test-Path $mcpJson)) {
  $placeholder = @"
{
  "_NOTE": "Canonical TypingMind MCP config. Known pins: chrome-devtools-mcp@1.12.0 (+ --allow-unrestricted-paths), mcp-gsc@0.4.1; quickbooks runs direct node C:\\Users\\shawn\\qbo-mcp\\dist\\index.js; the rest launch via npx. PASTE the full config from TypingMind (Settings > Plugins > export) or run: restore-typingmind.ps1 -CaptureExport <path-to-TypingMind-export.json>",
  "mcpServers": {}
}
"@
  Set-Content $mcpJson $placeholder -Encoding UTF8
  Log "created mcp-servers.json placeholder - NEEDS capture from live TypingMind"
} else {
  Log "mcp-servers.json: present in kit"
}

# ---------- 7. Status table ----------
Log ""
Log "=== MACHINE-SIDE STATUS ==="
Log ("node.exe installed:        " + $(if ($node) {'OK'} else {'MISSING'}))
Log ("qbo-mcp built:             " + $(if ($qbo) {'OK'} else {'MISSING'}))
Log ("AutoHotkey v2:             " + $(if ($ahk) {'OK'} else {'MISSING'}))
Log ("task TM-Bridge:            " + $(if ($taskState['TM-Bridge']) {'OK'} else {'MISSING'}))
Log ("task TM-Bridge-Watchdog:   " + $(if ($taskState['TM-Bridge-Watchdog']) {'OK'} else {'MISSING'}))
Log ("task TM-Runner-Watchdog:   " + $(if ($taskState['TM-Runner-Watchdog']) {'OK'} else {'MISSING'}))
Log ("port 8787 (bridge):        " + $(if ($port8787) {'OK'} else {'DOWN'}))
Log ("bridge /health ok:         " + $(if ($bridgeHealth) {'OK (19 tools)'} else {'DOWN'}))
Log ("port 50880 (runner):       " + $(if ($port50880) {'OK'} else {'DOWN'}))
Log ("vault entries:             $credCount/6")
Log ("kit mcp-servers.json:      " + $(if ((Test-Path $mcpJson) -and ((Get-Content $mcpJson -Raw) -notmatch 'mcpServers":\s*\{\s*\}')) {'CAPTURED'} else {'PLACEHOLDER - capture needed'}))

# ---------- 8. Browser-side checklist ----------
Log ""
Log "=== BROWSER-SIDE (manual, ~5 min) ==="
Log "1. Open TypingMind > Plugins/Connectors > import MCP JSON from: $mcpJson"
Log "2. Re-add bridge OpenAPI plugin: http://127.0.0.1:8787/openapi.json (key from vault TMB:tmKey)"
Log "3. Re-add native plugins per plugin-inventory.md (keys in Credential Manager)"
Log "4. Re-upload sources from: $kit\sources"
Log "5. Toggle each connector once so servers respawn; token refresh if needed"
Log ""
Log "Full log: $kit\restoral-$(Get-Date -Format yyyyMMdd-HHmm).log"
$logFile = Join-Path $kit "restoral-$(Get-Date -Format yyyyMMdd-HHmm).log"
$log -join "`r`n" | Set-Content $logFile -Encoding UTF8
