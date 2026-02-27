<#
.SYNOPSIS
  Applies or restores UDP jitter optimizations on Windows 10/11 (thin wrapper around the module).

.DESCRIPTION
  This script imports the WindowsUdpJitterOptimization module from the same directory
  and invokes Invoke-UdpJitterOptimization with the same parameters. Use -Action Apply
  to apply a preset, Backup/Restore for state, or ResetDefaults to restore baseline.

.PARAMETER Action
  Apply, Backup, Restore, or ResetDefaults.

.PARAMETER Preset
  Risk level 1 (Conservative), 2 (Medium), or 3 (Higher risk). Only used when Action is Apply.

.PARAMETER AllowUnsafeBackupFolder
  Allows backup/restore/apply paths under sensitive system directories.

.PARAMETER PassThru
  Returns a structured result object for automation.

.PARAMETER SkipAdminCheck
  Skip the administrator privilege check (e.g. for testing or constrained environments).

.EXAMPLE
  .\optimize-udp-jitter.ps1 -Action Apply -Preset 2 -WhatIf

.EXAMPLE
  .\optimize-udp-jitter.ps1 -Action Backup -BackupFolder C:\MyBackup

.NOTES
  Author: Sebastian J. Spicker
  License: MIT
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

  [string]$BackupFolder,

  [switch]$AllowUnsafeBackupFolder,

  [switch]$PassThru,

  [switch]$DryRun,

  [switch]$SkipAdminCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$manifestPath = Join-Path -Path $PSScriptRoot -ChildPath 'WindowsUdpJitterOptimization/WindowsUdpJitterOptimization.psd1'
Import-Module -Name $manifestPath -Force

if (-not $PSBoundParameters.ContainsKey('BackupFolder')) {
  $PSBoundParameters['BackupFolder'] = Get-UjDefaultBackupFolder
}

Invoke-UdpJitterOptimization @PSBoundParameters
