<#
.SYNOPSIS
  Deprecated wrapper.

.DESCRIPTION
  This script is deprecated. Use `optimize-udp-jitter.ps1 -Action ResetDefaults` instead.
#>

[CmdletBinding()]
param(
  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Warning -Message 'deprecated/reset-udp-jitter.ps1 is deprecated; use ./optimize-udp-jitter.ps1 -Action ResetDefaults instead.'

& (Join-Path -Path $PSScriptRoot -ChildPath '../optimize-udp-jitter.ps1') -Action ResetDefaults -DryRun:$DryRun

