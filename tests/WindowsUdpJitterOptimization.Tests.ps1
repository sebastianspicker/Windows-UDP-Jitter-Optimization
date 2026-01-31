Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'WindowsUdpJitterOptimization repo' {
  It 'imports the module and exposes Invoke-UdpJitterOptimization' {
    $manifestPath = Join-Path -Path $PSScriptRoot -ChildPath '../WindowsUdpJitterOptimization/WindowsUdpJitterOptimization.psd1'
    Import-Module -Name $manifestPath -Force
    (Get-Command -Name Invoke-UdpJitterOptimization -ErrorAction Stop).CommandType | Should -Be 'Function'
  }

  It 'keeps deprecated scripts as thin wrappers' {
    $reset = Get-Content -Path (Join-Path -Path $PSScriptRoot -ChildPath '../deprecated/reset-udp-jitter.ps1') -Raw
    $opt = Get-Content -Path (Join-Path -Path $PSScriptRoot -ChildPath '../deprecated/optimize-udp-jitter.ps1') -Raw
    $reset | Should -Match 'ResetDefaults'
    $opt | Should -Match '\.\./optimize-udp-jitter\.ps1'
    $opt | Should -Match '@args'
  }

  It 'does not use Invoke-Expression' {
    $hits = Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath '..') -Recurse -File -Include '*.ps1', '*.psm1' |
      Where-Object { $_.FullName -notmatch '[\\\\/]tests[\\\\/]' } |
      Select-String -Pattern 'Invoke-Expression' -SimpleMatch -ErrorAction SilentlyContinue
    $hits | Should -BeNullOrEmpty
  }
}
