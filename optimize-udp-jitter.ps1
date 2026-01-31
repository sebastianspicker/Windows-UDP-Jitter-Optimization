<#
Title: UDP Jitter Optimization (Windows 10/11) - Safe Defaults with Tiered Risk + Full Failsafe
Author: Sebastian J. Spicker
License: MIT

This script is a thin wrapper around the module in ./WindowsUdpJitterOptimization.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
  [ValidateSet('Apply', 'Backup', 'Restore', 'ResetDefaults')]
  [string]$Action = 'Apply',

  [ValidateSet(1, 2, 3)]
  [int]$Preset = 1,

  [ValidateRange(1, 65535)]
  [int]$TeamSpeakPort = 9987,

  [ValidateRange(1, 65535)]
  [int]$CS2PortStart = 27015,

  [ValidateRange(1, 65535)]
  [int]$CS2PortEnd = 27036,

  [switch]$IncludeAppPolicies,

  [string[]]$AppPaths = @(),

  [ValidateRange(0, 65535)]
  [int]$AfdThreshold = 1500,

  [ValidateSet('None', 'HighPerformance', 'Ultimate')]
  [string]$PowerPlan = 'None',

  [switch]$DisableGameDvr,

  [switch]$DisableUro,

  [string]$BackupFolder = (Join-Path -Path $env:ProgramData -ChildPath 'UDPTune'),

  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$manifestPath = Join-Path -Path $PSScriptRoot -ChildPath 'WindowsUdpJitterOptimization/WindowsUdpJitterOptimization.psd1'
Import-Module -Name $manifestPath -Force

Invoke-UdpJitterOptimization @PSBoundParameters
