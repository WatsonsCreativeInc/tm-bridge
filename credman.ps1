# credman.ps1 (tm-bridge) - Windows Credential Manager store/retrieve for tm-bridge secrets.
# Stores generic credentials under target names "TMB:<name>" (LocalMachine persist).
#
# Usage:
#   credman.ps1 -Set  -Name githubPat -Value <secret>   (or pipe the secret via stdin)
#   credman.ps1 -Get  -Name githubPat                   (prints the secret)
#   credman.ps1 -List                                   (prints stored names, never secrets)
#   credman.ps1 -Test -Name githubPat                   (prints OK or FAIL, never the secret)
param(
  [switch]$Set,
  [switch]$Get,
  [switch]$List,
  [switch]$Test,
  [string]$Name,
  [string]$Value,
  [string]$TargetPrefix = "TMB:"
)
$ErrorActionPreference = "Stop"

$src = @"
using System;
using System.Runtime.InteropServices;
public static class CredMan {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public struct CREDENTIAL {
    public int Flags;
    public int Type;
    public string TargetName;
    public string Comment;
    public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
    public int CredentialBlobSize;
    public IntPtr CredentialBlob;
    public int Persist;
    public int AttributeCount;
    public IntPtr Attributes;
    public string TargetAlias;
    public string UserName;
  }
  [DllImport("advapi32.dll", CharSet = CharSet.Unicode, EntryPoint = "CredWriteW", SetLastError = true)]
  public static extern bool CredWrite(ref CREDENTIAL credential, int flags);
  [DllImport("advapi32.dll", CharSet = CharSet.Unicode, EntryPoint = "CredReadW", SetLastError = true)]
  public static extern bool CredRead(string target, int type, int reservedFlag, out IntPtr credentialPtr);
  [DllImport("advapi32.dll", CharSet = CharSet.Unicode, EntryPoint = "CredDeleteW", SetLastError = true)]
  public static extern bool CredDelete(string target, int type, int flags);
  [DllImport("advapi32.dll", CharSet = CharSet.Unicode, EntryPoint = "CredEnumerateW", SetLastError = true)]
  public static extern bool CredEnumerate(string filter, int flag, out int count, out IntPtr pCredentials);
  [DllImport("advapi32.dll")]
  public static extern void CredFree(IntPtr cred);
}
"@
Add-Type -TypeDefinition $src

$TYPE_GENERIC = 1
$PERSIST_LOCAL_MACHINE = 2

function Get-Target([string]$n) { return $TargetPrefix + $n }

if ($List) {
  $count = 0
  $pRoot = [IntPtr]::Zero
  if (-not [CredMan]::CredEnumerate($TargetPrefix + "*", 0, [ref]$count, [ref]$pRoot)) { "none"; exit 0 }
  try {
    for ($i = 0; $i -lt $count; $i++) {
      $p = [System.Runtime.InteropServices.Marshal]::ReadIntPtr($pRoot, $i * [System.IntPtr]::Size)
      $cred = [System.Runtime.InteropServices.Marshal]::PtrToStructure($p, [type][CredMan+CREDENTIAL])
      $cred.TargetName
    }
  } finally { [CredMan]::CredFree($pRoot) }
  exit 0
}

if ([string]::IsNullOrEmpty($Name)) { Write-Error "Name is required"; exit 2 }
$target = Get-Target $Name

if ($Set) {
  if (-not $Value) {
    # Read pipeline input (not Console.In: the latter hangs when stdin
    # is open-but-empty, e.g. under start_process). Consumes $input.
    $buf = @($input) -join "`n"
    $Value = $buf.Trim()
  }
  if (-not $Value) { Write-Error "Value is required (argument or pipeline)" ; exit 2 }
  $bytes = [System.Text.Encoding]::Unicode.GetBytes($Value)
  $blob = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($bytes.Length)
  try {
    [System.Runtime.InteropServices.Marshal]::Copy($bytes, 0, $blob, $bytes.Length)
    $cred = New-Object "CredMan+CREDENTIAL"
    $cred.Type = $TYPE_GENERIC
    $cred.TargetName = $target
    $cred.Comment = "tm-bridge managed secret"
    $cred.CredentialBlobSize = $bytes.Length
    $cred.CredentialBlob = $blob
    $cred.Persist = $PERSIST_LOCAL_MACHINE
    $cred.UserName = "tm-bridge"
    if (-not [CredMan]::CredWrite([ref]$cred, 0)) { Write-Error "CredWrite failed for $target"; exit 1 }
    "stored: $target"
  } finally { [System.Runtime.InteropServices.Marshal]::FreeHGlobal($blob) }
  exit 0
}

if ($Get) {
  $p = [IntPtr]::Zero
  if (-not [CredMan]::CredRead($target, $TYPE_GENERIC, 0, [ref]$p)) { Write-Error "not found: $target"; exit 1 }
  try {
    $cred = [System.Runtime.InteropServices.Marshal]::PtrToStructure($p, [type][CredMan+CREDENTIAL])
    $bytes = New-Object byte[] $cred.CredentialBlobSize
    [System.Runtime.InteropServices.Marshal]::Copy($cred.CredentialBlob, $bytes, 0, $cred.CredentialBlobSize)
    [System.Text.Encoding]::Unicode.GetString($bytes)
  } finally { [CredMan]::CredFree($p) }
  exit 0
}

if ($Test) {
  $p = [IntPtr]::Zero
  if ([CredMan]::CredRead($target, $TYPE_GENERIC, 0, [ref]$p)) { [CredMan]::CredFree($p); "OK: $target" }
  else { "FAIL: $target"; exit 1 }
  exit 0
}

Write-Error "No command given. Use -Set, -Get, -List, or -Test."
exit 2
