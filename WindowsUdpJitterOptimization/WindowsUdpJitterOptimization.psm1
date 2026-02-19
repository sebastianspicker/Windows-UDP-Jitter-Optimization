Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$publicFiles = Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Public') -Filter '*.ps1' -File -ErrorAction SilentlyContinue
foreach ($file in $publicFiles) {
  . $file.FullName
}

$privateDir = Join-Path -Path $PSScriptRoot -ChildPath 'Private'
. (Join-Path -Path $privateDir -ChildPath 'Constants.ps1')
$privateFiles = Get-ChildItem -Path $privateDir -Filter '*.ps1' -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'Constants.ps1' }
foreach ($file in $privateFiles) {
  . $file.FullName
}

Export-ModuleMember -Function 'Invoke-UdpJitterOptimization'

