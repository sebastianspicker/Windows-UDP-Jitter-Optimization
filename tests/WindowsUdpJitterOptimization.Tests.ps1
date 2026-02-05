Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ManifestPath = Join-Path -Path $PSScriptRoot -ChildPath '../WindowsUdpJitterOptimization/WindowsUdpJitterOptimization.psd1'
Import-Module -Name $ManifestPath -Force

Describe 'WindowsUdpJitterOptimization repo' {
  It 'exposes Invoke-UdpJitterOptimization' {
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

  Context 'DryRun safety' {
    InModuleScope WindowsUdpJitterOptimization {
      It 'skips MMCSS registry changes on DryRun' {
        Mock -CommandName Set-UjRegistryValue
        Mock -CommandName New-Item

        Set-UjMmcssAudioSafety -DryRun

        Assert-MockCalled -CommandName Set-UjRegistryValue -Times 0
        Assert-MockCalled -CommandName New-Item -Times 0
      }

      It 'skips audio service changes on DryRun' {
        { Start-UjAudioService -DryRun } | Should -Not -Throw
      }

      It 'skips local QoS registry changes on DryRun' {
        Mock -CommandName Set-UjRegistryValue
        Mock -CommandName New-Item

        Enable-UjLocalQosMarking -DryRun

        Assert-MockCalled -CommandName Set-UjRegistryValue -Times 0
        Assert-MockCalled -CommandName New-Item -Times 0
      }

      It 'skips GameDVR changes on DryRun' {
        Mock -CommandName Set-ItemProperty

        Set-UjGameDvrState -State Disabled -DryRun

        Assert-MockCalled -CommandName Set-ItemProperty -Times 0
      }
    }
  }
}
