# emit-keys-for-paste.ps1 -- hands vault secrets to you one at a time for
# pasting into TypingMind after a crash. Keys NEVER touch disk or logs:
# each is copied to the clipboard, you paste it, press Enter, next one.
# Usage:
#   (default)              interactive: loop through all keys
#   -Name githubPat        single key to clipboard
#   -ListOnly              show which keys exist, no values
param(
  [string]$Name = "",
  [switch]$ListOnly
)
$ErrorActionPreference = 'Stop'
$credman = 'C:\Users\shawn\tm-bridge\credman.ps1'

# Keys TypingMind needs pasted (tmKey is for the bridge OpenAPI plugin, listed last)
$keys = @(
  @{ name = 'githubPat';   label = 'GitHub PAT           -> TypingMind github connector (GITHUB_PERSONAL_ACCESS_TOKEN)' },
  @{ name = 'exaApiKey';   label = 'Exa API key          -> TypingMind exa connector (EXA_API_KEY)' },
  @{ name = 'renderToken'; label = 'Render token         -> TypingMind render connector (Authorization: Bearer ...)' },
  @{ name = 'wooKey';      label = 'WooCommerce key      -> TypingMind woo connector (WOOCOMMERCE_CONSUMER_KEY)' },
  @{ name = 'wooSecret';   label = 'WooCommerce secret   -> TypingMind woo connector (WOOCOMMERCE_CONSUMER_SECRET)' },
  @{ name = 'tmKey';       label = 'Bridge key (x-tm-key)-> TypingMind tm-bridge OpenAPI plugin' }
)

if ($ListOnly) {
  foreach ($k in $keys) {
    $t = & $credman -Test -Name $k.name
    Write-Output ("{0,-12} {1}" -f $k.name, $t)
  }
  exit 0
}

if ($Name -ne "") {
  $match = $keys | Where-Object { $_.name -eq $Name }
  if (-not $match) { Write-Output "unknown key name: $Name"; exit 1 }
  $val = (& $credman -Get -Name $Name | Out-String).Trim()
  if (-not $val) { Write-Output "vault read failed for $Name"; exit 1 }
  Set-Clipboard -Value $val
  Write-Output "$($match.label)"
  Write-Output "-> copied to clipboard ($($val.Length) chars). Paste it now."
  exit 0
}

Write-Output "=== KEY PASTE HELPER - one at a time, clipboard only ==="
foreach ($k in $keys) {
  $val = (& $credman -Get -Name $k.name | Out-String).Trim()
  if (-not $val) { Write-Output "SKIP $($k.name): vault read failed"; continue }
  Set-Clipboard -Value $val
  Write-Output ""
  Write-Output $k.label
  Write-Output "-> COPIED TO CLIPBOARD ($($val.Length) chars). Paste into TypingMind, then press Enter."
  Read-Host "ready for next key?"
}
Write-Output ""
Write-Output "All keys emitted. Vault values unchanged (read-only)."
