# push-kit.ps1 v2 -- estate backup: update BOTH sources on every run
#   1. staging repo  (C:\Users\shawn\tm-bridge\.git-backup)  -> commits local estate
#   2. GitHub        (WatsonsCreativeInc/tm-bridge)          -> push from staging
#   3. Desktop clone (C:\Users\shawn\Desktop\tm-bridge-kit)  -> pull, verify match
# PAT read from vault (credman.ps1); never on disk/log; stripped from remote URL after.
# Usage: push-kit.ps1 [optional commit message as $args[0]]
$ErrorActionPreference = 'Stop'
$stage  = 'C:\Users\shawn\tm-bridge\.git-backup'
$desk   = 'C:\Users\shawn\Desktop\tm-bridge-kit'
$msg    = if ($args.Count -gt 0) { $args[0] } else { "estate sync $(Get-Date -Format 'yyyy-MM-dd HH:mm')" }

# ---- sync estate -> staging ----
$src = 'C:\Users\shawn\tm-bridge'
$files = 'tm-bridge.js','RUNBOOK.md','restore-typingmind.ps1','restore-typingmind.cmd',
         'emit-keys-for-paste.ps1','emit-keys-for-paste.cmd','push-kit.ps1',
         'run_bridge_hidden.vbs','run_watchdog_hidden.vbs','watchdog.ps1',
         'run_runner_hidden.vbs','run_runner_watchdog_hidden.vbs','runner_watchdog.ps1',
         'credman.ps1','migrate-to-vault.ps1','vault-test.js','extract-mcp-config.ps1'
foreach ($f in $files) { if (Test-Path "$src\$f") { Copy-Item "$src\$f" "$stage\$f" -Force } }
foreach ($d in 'typingmind-rebuild') {
  if (Test-Path "$src\$d") {
    New-Item -ItemType Directory -Path "$stage\$d" -Force | Out-Null
    Get-ChildItem "$src\$d" -File -ErrorAction SilentlyContinue | ForEach-Object { Copy-Item $_.FullName "$stage\$d\$($_.Name)" -Force }
  }
}

# ---- secret scan before anything leaves the machine ----
$patterns = 'ghp_[A-Za-z0-9]{20,}','github_pat_[A-Za-z0-9_]{20,}','tmk_[A-Za-z0-9]{10,}',
            'ck_[a-f0-9]{30,}','cs_[a-f0-9]{30,}','rnd_[A-Za-z0-9]{10,}',
            '[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}'
$fail = @()
foreach ($f in (Get-ChildItem $stage -Recurse -File | Where-Object { $_.FullName -notmatch '\\\.git\\' })) {
  $txt = Get-Content $f.FullName -Raw
  foreach ($p in $patterns) { if ($txt -match $p) { $fail += "$($f.Name) -> $p" } }
}
if ($fail.Count -gt 0) { Write-Output "SECRET SCAN FAIL - push aborted:"; $fail; exit 1 }
Write-Output "secret scan: clean"

# ---- commit + push (PAT from vault) ----
Set-Location $stage
$pat = & 'C:\Users\shawn\tm-bridge\credman.ps1' -Get -Name githubPat
if (-not $pat -or $pat.Length -lt 20) { Write-Output 'VAULT READ FAILED'; exit 1 }
git remote set-url origin "https://WatsonsCreativeInc:$pat@github.com/WatsonsCreativeInc/tm-bridge.git"
git add -A
$commitOut = git commit -m $msg 2>&1 | Out-String
Write-Output ($commitOut.Trim() -split "`n" | Select-Object -Last 2)
git push origin main 2>&1 | Out-String | ForEach-Object { ($_ -split "`n" | Where-Object { $_ -match 'main|rejected|error' }) -join '; ' }
$pushExit = $LASTEXITCODE
git remote set-url origin "https://WatsonsCreativeInc@github.com/WatsonsCreativeInc/tm-bridge.git"
if ($pushExit -ne 0) { Write-Output "PUSH FAILED (exit $pushExit)"; exit 1 }

# ---- desktop clone: pull to match ----
Set-Location $desk
git pull origin main 2>&1 | Out-String | ForEach-Object { ($_ -split "`n" | Select-Object -Last 1) }

# ---- verify both ends match ----
$stageHash = (git -C $stage rev-parse HEAD).Trim()
$deskHash  = (git -C $desk rev-parse HEAD).Trim()
$gh = git -C $stage ls-remote origin main 2>$null
if ($gh) { $ghHash = ($gh -split '\s+')[0] } else { $ghHash = 'unknown' }
Write-Output ""
Write-Output "=== SYNC STATUS ==="
Write-Output "staging  HEAD: $stageHash"
Write-Output "desktop  HEAD: $deskHash"
Write-Output "GitHub   HEAD: $ghHash"
if ($stageHash -eq $deskHash -and $stageHash -eq $ghHash) {
  Write-Output "VERDICT: ALL THREE IN SYNC ($stageHash)"
} else {
  Write-Output "VERDICT: MISMATCH - investigate before trusting backups"
  exit 1
}
