function Invoke-UdpJitterOptimization {
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

  New-UjDirectory -Path $BackupFolder | Out-Null

  if ($Action -eq 'Backup') {
    Backup-UjState -BackupFolder $BackupFolder
    Write-UjInformation -Message 'Backup complete.'
    return
  }

  if ($Action -eq 'Restore') {
    Restore-UjState -BackupFolder $BackupFolder
    Write-UjInformation -Message 'Restore complete. A reboot may be required.'
    return
  }

  if ($Action -eq 'ResetDefaults') {
    Reset-UjBaseline -DryRun:$DryRun
    return
  }

  Write-UjInformation -Message ("UDP Jitter Optimization - Preset {0} (Action={1})" -f $Preset, $Action)

  Backup-UjState -BackupFolder $BackupFolder

  Set-UjMmcssAudioSafety -DryRun:$DryRun
  Start-UjAudioService -DryRun:$DryRun

  Enable-UjLocalQosMarking -DryRun:$DryRun

  New-UjDscpPolicyByPort -Name ("QoS_UDP_TS_{0}" -f $TeamSpeakPort) -PortStart $TeamSpeakPort -PortEnd $TeamSpeakPort -Dscp 46 -DryRun:$DryRun
  New-UjDscpPolicyByPort -Name ("QoS_UDP_CS2_{0}_{1}" -f $CS2PortStart, $CS2PortEnd) -PortStart $CS2PortStart -PortEnd $CS2PortEnd -Dscp 46 -DryRun:$DryRun

  if ($IncludeAppPolicies -and $null -ne $AppPaths -and $AppPaths.Count -gt 0) {
    $i = 0
    foreach ($path in $AppPaths) {
      if ([string]::IsNullOrWhiteSpace($path)) {
        continue
      }
      $i++
      New-UjDscpPolicyByApp -Name ('QoS_APP_{0}' -f $i) -ExePath $path -Dscp 46 -DryRun:$DryRun
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
