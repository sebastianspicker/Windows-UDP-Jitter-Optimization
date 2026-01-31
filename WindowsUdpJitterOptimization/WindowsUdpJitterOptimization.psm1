Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$publicFiles = Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Public') -Filter '*.ps1' -File -ErrorAction SilentlyContinue
foreach ($file in $publicFiles) {
  . $file.FullName
}

$privateFiles = Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Private') -Filter '*.ps1' -File -ErrorAction SilentlyContinue
foreach ($file in $privateFiles) {
  . $file.FullName
}

Export-ModuleMember -Function 'Invoke-UdpJitterOptimization'

