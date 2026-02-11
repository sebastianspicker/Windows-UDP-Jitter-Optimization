<#
.SYNOPSIS
  Deprecated wrapper.

.DESCRIPTION
  This script is deprecated. Use the root `optimize-udp-jitter.ps1` instead.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Warning -Message 'deprecated/optimize-udp-jitter.ps1 is deprecated; use ./optimize-udp-jitter.ps1 instead.'

& (Join-Path -Path $PSScriptRoot -ChildPath '../optimize-udp-jitter.ps1') @args
