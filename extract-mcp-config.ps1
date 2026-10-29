# extract-mcp-config.ps1 -- find MCPServersJSON in copied leveldb files,
# dump a large window around each hit to disk for parsing.
$dst = "$env:TEMP\ls-capture"
$outDir = "$env:TEMP\mcp-extract"
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$i = 0
foreach ($f in (Get-ChildItem $dst -File | Where-Object { $_.Name -match '\.ldb|\.log' })) {
  $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
  $text = [System.Text.Encoding]::ASCII.GetString($bytes)
  $idx = 0
  while ($true) {
    $idx = $text.IndexOf('MCPServersJSON', $idx)
    if ($idx -lt 0) { break }
    $len = [Math]::Min(120000, $text.Length - $idx)
    $chunk = $text.Substring($idx, $len)
    $clean = $chunk -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', ''
    $i++
    $outFile = Join-Path $outDir ("hit-{0:D2}-in-{1}-at-{2}.txt" -f $i, $f.Name, $idx)
    [System.IO.File]::WriteAllText($outFile, $clean)
    $idx += 1000
  }
}
"extracted $i windows to $outDir"
Get-ChildItem $outDir | Select-Object Name, Length | Format-Table -AutoSize | Out-String
