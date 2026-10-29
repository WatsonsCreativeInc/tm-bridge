# migrate-to-vault.ps1 (2026-10-29) - one-shot migration of tm-bridge secrets
# from plaintext config.json to Windows Credential Manager.
# Secrets NEVER appear in process command lines: values are read from
# config.json inside this process and written via CredWrite directly.
# Verifies each write with a CredRead roundtrip before touching config.json;
# only rewrites config.json to vault: refs if ALL six verify.
# The vault itself is the backup: no new plaintext backup is created here.
$ErrorActionPreference = "Stop"
Set-ExecutionPolicy Bypass -Scope Process -Force

$cfgPath = "C:\Users\shawn\.tm-bridge\config.json"
$prefix  = "TMB:"

$src = @"
using System;
using System.Runtime.InteropServices;
public static class CredManM {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public struct CREDENTIAL {
    public int Flags; public int Type; public string TargetName; public string Comment;
    public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
    public int CredentialBlobSize; public IntPtr CredentialBlob; public int Persist;
    public int AttributeCount; public IntPtr Attributes; public string TargetAlias; public string UserName;
  }
  [DllImport("advapi32.dll", CharSet = CharSet.Unicode, EntryPoint = "CredWriteW")]
  public static extern bool CredWrite(ref CREDENTIAL c, int flags);
  [DllImport("advapi32.dll", CharSet = CharSet.Unicode, EntryPoint = "CredReadW")]
  public static extern bool CredRead(string target, int type, int f, out IntPtr p);
  [DllImport("advapi32.dll")] public static extern void CredFree(IntPtr c);
}
"@
Add-Type -TypeDefinition $src

function Write-Vault([string]$name, [string]$value) {
  $bytes = [System.Text.Encoding]::Unicode.GetBytes($value)
  $blob = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($bytes.Length)
  try {
    [System.Runtime.InteropServices.Marshal]::Copy($bytes, 0, $blob, $bytes.Length)
    $cred = New-Object "CredManM+CREDENTIAL"
    $cred.Type = 1; $cred.TargetName = $prefix + $name
    $cred.Comment = "tm-bridge managed secret (migrated 2026-10-29)"
    $cred.CredentialBlobSize = $bytes.Length; $cred.CredentialBlob = $blob
    $cred.Persist = 2; $cred.UserName = "tm-bridge"
    if (-not [CredManM]::CredWrite([ref]$cred, 0)) { throw "CredWrite failed: $name" }
  } finally { [System.Runtime.InteropServices.Marshal]::FreeHGlobal($blob) }
}
function Read-Vault([string]$name) {
  $p = [IntPtr]::Zero
  if (-not [CredManM]::CredRead($prefix + $name, 1, 0, [ref]$p)) { throw "CredRead failed: $name" }
  try {
    $cred = [System.Runtime.InteropServices.Marshal]::PtrToStructure($p, [type][CredManM+CREDENTIAL])
    $bytes = New-Object byte[] $cred.CredentialBlobSize
    [System.Runtime.InteropServices.Marshal]::Copy($cred.CredentialBlob, $bytes, 0, $cred.CredentialBlobSize)
    [System.Text.Encoding]::Unicode.GetString($bytes)
  } finally { [CredManM]::CredFree($p) }
}

$cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
$items = @(
  @{ name = "tmKey";       value = $cfg.tmKey },
  @{ name = "githubPat";   value = $cfg.githubPat },
  @{ name = "exaApiKey";   value = $cfg.exaApiKey },
  @{ name = "renderToken"; value = $cfg.renderToken },
  @{ name = "wooKey";      value = $cfg.woo.key },
  @{ name = "wooSecret";   value = $cfg.woo.secret }
)

$results = @()
foreach ($it in $items) {
  if (-not $it.value) { throw "config value missing for $($it.name) - aborting, config.json untouched" }
  Write-Vault $it.name $it.value
  $back = Read-Vault $it.name
  $ok = ($back -ceq $it.value)
  $results += [pscustomobject]@{ name = $it.name; roundtrip = $ok }
}
$allOk = ($results | Where-Object roundtrip -eq $false).Count -eq 0
if (-not $allOk) { throw "roundtrip verification failed - config.json left untouched"; }

# All six verified: now point config.json at the vault.
$cfg.tmKey = "vault:tmKey"; $cfg.githubPat = "vault:githubPat"
$cfg.exaApiKey = "vault:exaApiKey"; $cfg.renderToken = "vault:renderToken"
$cfg.woo.key = "vault:wooKey"; $cfg.woo.secret = "vault:wooSecret"
Set-Content -Path $cfgPath -Value ($cfg | ConvertTo-Json -Depth 5) -Encoding UTF8

"=== migration complete ==="
$results | ForEach-Object { "$($_.name): roundtrip=$($_.roundtrip)" }
"config.json now uses vault: refs"
"secret values verified present in config.json? no (replaced by vault refs)"
$check = Get-Content $cfgPath -Raw
"leftover plaintext secrets in config.json: $(($check -match 'ck_cffa|cs_a76|bf9e6e01|rnd_jW7|github_pat|tmk_7f'))"
