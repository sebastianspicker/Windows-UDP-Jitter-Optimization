function Invoke-UdpJitterOptimization {
  <#
  .SYNOPSIS
    Applies, backs up, restores, or resets UDP jitter optimization settings on Windows 10/11.

  .DESCRIPTION
    Applies preset-based UDP jitter optimizations (QoS DSCP, NIC tuning, AFD, MMCSS, URO, power plan, Game DVR),
    or backs up/restores state, or resets to baseline. Requires elevation unless -SkipAdminCheck is used.

  .PARAMETER Action
    Apply, Backup, Restore, or ResetDefaults.

  .PARAMETER Preset
    Risk level 1 (Conservative), 2 (Medium), 3 (Higher risk). Used when Action is Apply.

  .PARAMETER BackupFolder
    Directory for backup/restore files. Default: $env:ProgramData\UDPTune.

  .PARAMETER DryRun
    Print what would be done without making changes.

  .PARAMETER SkipAdminCheck
    Skip administrator privilege check.

  .EXAMPLE
    Invoke-UdpJitterOptimization -Action Apply -Preset 2 -WhatIf

  .EXAMPLE
    Invoke-UdpJitterOptimization -Action Backup -BackupFolder C:\MyBackup
  #>
  [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
  param(
    [Parameter()]
    [ValidateSet('Apply', 'Backup', 'Restore', 'ResetDefaults')]
    [string]$Action = 'Apply',

    [Parameter()]
    [ValidateSet(1, 2, 3)]
    [int]$Preset = 1,

    [Parameter()]
    [ValidateRange(1, 65535)]
    [int]$TeamSpeakPort = 9987,

    [Parameter()]
    [ValidateRange(1, 65535)]
    [int]$CS2PortStart = 27015,

    [Parameter()]
    [ValidateRange(1, 65535)]
    [int]$CS2PortEnd = 27036,

    [Parameter()]
    [switch]$IncludeAppPolicies,

    [Parameter()]
    [string[]]$AppPaths = @(),

    [Parameter()]
    [ValidateRange(0, 65535)]
    [int]$AfdThreshold = 1500,

    [Parameter()]
    [ValidateSet('None', 'HighPerformance', 'Ultimate')]
    [string]$PowerPlan = 'None',

    [Parameter()]
    [switch]$DisableGameDvr,

    [Parameter()]
    [switch]$DisableUro,

    [Parameter()]
    [string]$BackupFolder = (Join-Path -Path $env:ProgramData -ChildPath 'UDPTune'),

    [Parameter()]
    [switch]$DryRun,

    [Parameter()]
    [switch]$SkipAdminCheck
  )

  $target = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { 'LocalMachine' }
  $shouldProcessAction =
    if ($Action -eq 'Backup') { 'Backup UDP jitter optimization state' }
    elseif ($Action -eq 'Restore') { 'Restore UDP jitter optimization state' }
    elseif ($Action -eq 'ResetDefaults') { 'Reset UDP jitter optimization settings to baseline defaults' }
    else { "Apply UDP jitter optimization preset $Preset" }

  if (-not $PSCmdlet.ShouldProcess($target, $shouldProcessAction)) {
    return
  }

  if (-not $SkipAdminCheck) {
    Assert-UjAdministrator
  }

  if ($Action -eq 'Apply' -and $CS2PortEnd -lt $CS2PortStart) {
    throw 'CS2PortEnd must be greater than or equal to CS2PortStart.'
  }

  if ($Action -in @('Backup', 'Restore', 'Apply') -and [string]::IsNullOrWhiteSpace($BackupFolder)) {
    throw 'BackupFolder must not be empty.'
  }

  if (-not $DryRun -and $Action -in @('Backup', 'Restore', 'Apply')) {
    New-UjDirectory -Path $BackupFolder | Out-Null
  }

  if ($Action -eq 'Backup') {
    Backup-UjState -BackupFolder $BackupFolder -DryRun:$DryRun
    Write-UjInformation -Message 'Backup complete.'
    return
  }

  if ($Action -eq 'Restore') {
    Restore-UjState -BackupFolder $BackupFolder -DryRun:$DryRun
    Write-UjInformation -Message 'Restore complete. A reboot may be required.'
    return
  }

  if ($Action -eq 'ResetDefaults') {
    Reset-UjBaseline -DryRun:$DryRun
    return
  }

  Write-UjInformation -Message ("UDP Jitter Optimization - Preset {0} (Action={1})" -f $Preset, $Action)

  Backup-UjState -BackupFolder $BackupFolder -DryRun:$DryRun

  Set-UjMmcssAudioSafety -DryRun:$DryRun
  Start-UjAudioService -DryRun:$DryRun

  Enable-UjLocalQosMarking -DryRun:$DryRun

  New-UjDscpPolicyByPort -Name ("QoS_UDP_TS_{0}" -f $TeamSpeakPort) -PortStart $TeamSpeakPort -PortEnd $TeamSpeakPort -Dscp $script:UjDefaultDscp -DryRun:$DryRun
  New-UjDscpPolicyByPort -Name ("QoS_UDP_CS2_{0}_{1}" -f $CS2PortStart, $CS2PortEnd) -PortStart $CS2PortStart -PortEnd $CS2PortEnd -Dscp $script:UjDefaultDscp -DryRun:$DryRun

  if ($IncludeAppPolicies -and $null -ne $AppPaths -and $AppPaths.Count -gt 0) {
    $i = 0
    foreach ($path in $AppPaths) {
      if ([string]::IsNullOrWhiteSpace($path)) {
        continue
      }
      $i++
      New-UjDscpPolicyByApp -Name ('QoS_APP_{0}' -f $i) -ExePath $path -Dscp $script:UjDefaultDscp -DryRun:$DryRun
    }
  }

  Set-UjNicConfiguration -Preset $Preset -DryRun:$DryRun
  Set-UjAfdFastSendDatagramThreshold -Preset $Preset -AfdThreshold $AfdThreshold -DryRun:$DryRun
  Set-UjUndocumentedNetworkMmcssTuning -Preset $Preset -DryRun:$DryRun

  if ($DisableUro -or $Preset -ge 3) {
    Set-UjUroState -State Disabled -DryRun:$DryRun
  }

  if ($PowerPlan -ne 'None') {
    Set-UjPowerPlan -PowerPlan $PowerPlan -DryRun:$DryRun
  }

  if ($DisableGameDvr) {
    Set-UjGameDvrState -State Disabled -DryRun:$DryRun
  }

  Show-UjSummary
  Write-UjInformation -Message ''
  Write-UjInformation -Message 'Note: Reboot recommended for AFD/MMCSS registry changes to fully apply.'
}
