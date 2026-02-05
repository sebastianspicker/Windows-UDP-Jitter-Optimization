function Backup-UjState {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$BackupFolder
  )

  Write-UjInformation -Message 'Backing up current state ...'
  New-UjDirectory -Path $BackupFolder | Out-Null

  Export-UjRegistryKey -RegistryPath 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' -OutFile (Join-Path -Path $BackupFolder -ChildPath 'SystemProfile.reg')
  Export-UjRegistryKey -RegistryPath 'HKLM\SYSTEM\CurrentControlSet\Services\AFD\Parameters' -OutFile (Join-Path -Path $BackupFolder -ChildPath 'AFD_Parameters.reg')

  try {
    Get-UjManagedQosPolicy | Export-CliXml -Path (Join-Path -Path $BackupFolder -ChildPath 'qos_ours.xml')
  } catch {
    Write-Warning -Message 'QoS backup skipped (Get-NetQosPolicy failed).'
  }

  try {
    $rows = foreach ($n in (Get-NetAdapter -Physical | Where-Object { $_.Status -eq 'Up' })) {
      Get-NetAdapterAdvancedProperty -Name $n.Name |
        Select-Object @{ Name = 'Adapter'; Expression = { $n.Name } }, DisplayName, RegistryKeyword, DisplayValue, RegistryValue
    }
    $rows | Export-Csv -NoTypeInformation -Path (Join-Path -Path $BackupFolder -ChildPath 'nic_advanced_backup.csv')
  } catch {
    Write-Warning -Message 'NIC advanced snapshot failed.'
  }

  try {
    Get-NetAdapterRsc | Select-Object Name, IPv4Enabled, IPv6Enabled |
      Export-Csv -NoTypeInformation -Path (Join-Path -Path $BackupFolder -ChildPath 'rsc_backup.csv')
  } catch {
    Write-Verbose -Message 'RSC snapshot failed.'
  }

  try {
    (powercfg /GetActiveScheme) -join "`n" | Out-File -FilePath (Join-Path -Path $BackupFolder -ChildPath 'powerplan.txt') -Encoding utf8
  } catch {
    Write-Verbose -Message 'Power plan snapshot failed.'
  }
}

function Restore-UjState {
  [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
  param(
    [Parameter(Mandatory)]
    [string]$BackupFolder
  )

  Write-UjInformation -Message 'Restoring previous state ...'

  Import-UjRegistryFile -InFile (Join-Path -Path $BackupFolder -ChildPath 'SystemProfile.reg')
  Import-UjRegistryFile -InFile (Join-Path -Path $BackupFolder -ChildPath 'AFD_Parameters.reg')

  Remove-UjManagedQosPolicy

  $qosInventory = Join-Path -Path $BackupFolder -ChildPath 'qos_ours.xml'
  if (Test-Path -Path $qosInventory) {
    try {
      $items = Import-CliXml -Path $qosInventory
      foreach ($item in $items) {
        $name = $item.Name
        $dscp =
          if ($item.PSObject.Properties.Name -contains 'DSCPAction' -and $null -ne $item.DSCPAction -and [int]$item.DSCPAction -ge 0) { [int]$item.DSCPAction }
          elseif ($item.PSObject.Properties.Name -contains 'DSCPValue' -and $null -ne $item.DSCPValue -and [int]$item.DSCPValue -ge 0) { [int]$item.DSCPValue }
          else { 46 }

        $proto = 'UDP'
        if ($item.PSObject.Properties.Name -contains 'IPProtocolMatchCondition' -and $item.IPProtocolMatchCondition) {
          $proto = [string]$item.IPProtocolMatchCondition
        }

        if ($item.PSObject.Properties.Name -contains 'IPPortMatchCondition' -and [int]$item.IPPortMatchCondition -gt 0) {
          if ($PSCmdlet.ShouldProcess($name, 'Recreate NetQosPolicy (port-based)')) {
            New-NetQosPolicy -Name $name -IPPortMatchCondition ([uint16]$item.IPPortMatchCondition) -IPProtocolMatchCondition $proto -DSCPAction ([sbyte]$dscp) -NetworkProfile All | Out-Null
          }
          continue
        }

        if ($item.PSObject.Properties.Name -contains 'AppPathNameMatchCondition' -and $item.AppPathNameMatchCondition) {
          if ($PSCmdlet.ShouldProcess($name, 'Recreate NetQosPolicy (app-based)')) {
            New-NetQosPolicy -Name $name -AppPathNameMatchCondition ([string]$item.AppPathNameMatchCondition) -DSCPAction ([sbyte]$dscp) -NetworkProfile All | Out-Null
          }
          continue
        }
      }
    } catch {
      Write-Warning -Message 'QoS restore skipped (import/parse failed).'
    }
  }

  $csv = Join-Path -Path $BackupFolder -ChildPath 'nic_advanced_backup.csv'
  if (Test-Path -Path $csv) {
    try {
      $data = Import-Csv -Path $csv
      $adapters = $data | Select-Object -ExpandProperty Adapter -Unique
      foreach ($adapter in $adapters) {
        foreach ($property in ($data | Where-Object { $_.Adapter -eq $adapter })) {
          try {
            if ($property.DisplayName -and $property.DisplayValue) {
              if ($PSCmdlet.ShouldProcess($adapter, ("Restore NIC advanced property: {0}" -f $property.DisplayName))) {
                Set-NetAdapterAdvancedProperty -Name $adapter -DisplayName $property.DisplayName -DisplayValue $property.DisplayValue -NoRestart -ErrorAction Stop | Out-Null
              }
              continue
            }

            if ($property.RegistryKeyword -and $null -ne $property.RegistryValue) {
              if ($PSCmdlet.ShouldProcess($adapter, ("Restore NIC advanced property keyword: {0}" -f $property.RegistryKeyword))) {
                Set-NetAdapterAdvancedProperty -Name $adapter -RegistryKeyword $property.RegistryKeyword -RegistryValue $property.RegistryValue -NoRestart -ErrorAction Stop | Out-Null
              }
              continue
            }
          } catch {
            Write-Verbose -Message ("NIC property restore failed: {0} ({1})" -f $adapter, $property.DisplayName)
          }
        }
      }
    } catch {
      Write-Warning -Message 'NIC advanced restore error.'
    }
  }

  $rscFile = Join-Path -Path $BackupFolder -ChildPath 'rsc_backup.csv'
  if (Test-Path -Path $rscFile) {
    try {
      foreach ($row in (Import-Csv -Path $rscFile)) {
        $enable = ($row.IPv4Enabled -eq 'True' -or $row.IPv6Enabled -eq 'True')
        if ($enable) {
          if ($PSCmdlet.ShouldProcess($row.Name, 'Enable NetAdapterRsc')) {
            Enable-NetAdapterRsc -Name $row.Name -ErrorAction SilentlyContinue | Out-Null
          }
        } else {
          if ($PSCmdlet.ShouldProcess($row.Name, 'Disable NetAdapterRsc')) {
            Disable-NetAdapterRsc -Name $row.Name -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
          }
        }
      }
    } catch {
      Write-Verbose -Message 'RSC restore failed.'
    }
  }

  $powerPlanFile = Join-Path -Path $BackupFolder -ChildPath 'powerplan.txt'
  if (Test-Path -Path $powerPlanFile) {
    $text = Get-Content -Path $powerPlanFile -Raw
    if ($text -match '{[0-9a-fA-F-]+}') {
      $guid = $Matches[0]
      if ($PSCmdlet.ShouldProcess($guid, 'Restore power plan')) {
        try {
          & powercfg /S $guid | Out-Null
        } catch {
          Write-Verbose -Message 'Power plan restore failed.'
        }
      }
    }
  }

  Write-UjInformation -Message 'Restore complete. A reboot may be required for registry-based settings.'
}

function Set-UjMmcssAudioSafety {
  [CmdletBinding(SupportsShouldProcess = $true)]
  param(
    [Parameter()]
    [switch]$DryRun
  )

  if ($DryRun) {
    Write-UjInformation -Message '[DryRun] Ensure MMCSS audio safety registry values.'
    return
  }

  $mm = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
  $tasks = Join-Path -Path $mm -ChildPath 'Tasks'
  $audio = Join-Path -Path $tasks -ChildPath 'Audio'

  if (-not (Test-Path -Path $tasks) -and $PSCmdlet.ShouldProcess($tasks, 'Create registry key')) {
    New-Item -Path $tasks -Force | Out-Null
  }

  if (-not (Test-Path -Path $audio) -and $PSCmdlet.ShouldProcess($audio, 'Create registry key')) {
    New-Item -Path $audio -Force | Out-Null
  }

  Set-UjRegistryValue -Key $mm -Name 'SystemResponsiveness' -Type DWord -Value 20
  Set-UjRegistryValue -Key $audio -Name 'Priority' -Type DWord -Value 6
  Set-UjRegistryValue -Key $audio -Name 'Background Only' -Type DWord -Value 0
  Set-UjRegistryValue -Key $audio -Name 'Clock Rate' -Type DWord -Value 10000
  Set-UjRegistryValue -Key $audio -Name 'Scheduling Category' -Type String -Value 'High'
  Set-UjRegistryValue -Key $audio -Name 'SFIO Priority' -Type String -Value 'High'

  Set-UjRegistryValue -Key $audio -Name 'BackgroundOnly' -Type DWord -Value 0
  Set-UjRegistryValue -Key $audio -Name 'SchedulingCategory' -Type String -Value 'High'
  Set-UjRegistryValue -Key $audio -Name 'SFIOPriority' -Type String -Value 'High'
}

function Start-UjAudioService {
  [CmdletBinding(SupportsShouldProcess = $true)]
  param(
    [Parameter()]
    [switch]$DryRun
  )

  if ($DryRun) {
    Write-UjInformation -Message '[DryRun] Ensure audio services are Automatic and running.'
    return
  }

  foreach ($serviceName in @('AudioEndpointBuilder', 'Audiosrv', 'MMCSS')) {
    try {
      if ($PSCmdlet.ShouldProcess($serviceName, 'Set service startup type to Automatic')) {
        Set-Service -Name $serviceName -StartupType Automatic
      }
    } catch {
      Write-Verbose -Message ("Set-Service failed: {0}" -f $serviceName)
    }

    try {
      $service = Get-Service -Name $serviceName
      if ($service.Status -ne 'Running' -and $PSCmdlet.ShouldProcess($serviceName, 'Start service')) {
        Start-Service -Name $serviceName
      }
    } catch {
      Write-Verbose -Message ("Start-Service failed: {0}" -f $serviceName)
    }
  }
}

function Enable-UjLocalQosMarking {
  [CmdletBinding(SupportsShouldProcess = $true)]
  param(
    [Parameter()]
    [switch]$DryRun
  )

  if ($DryRun) {
    Write-UjInformation -Message '[DryRun] Enable local QoS marking (Do not use NLA).'
    return
  }

  $qos = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\QoS'
  if ($PSCmdlet.ShouldProcess($qos, 'Create registry key')) {
    New-Item -Path $qos -Force | Out-Null
  }

  Set-UjRegistryValue -Key $qos -Name 'Do not use NLA' -Type String -Value '1'
}

function Set-UjAfdFastSendDatagramThreshold {
  [CmdletBinding(SupportsShouldProcess = $true)]
  param(
    [Parameter(Mandatory)]
    [ValidateSet(1, 2, 3)]
    [int]$Preset,

    [Parameter(Mandatory)]
    [ValidateRange(0, 65535)]
    [int]$AfdThreshold,

    [Parameter()]
    [switch]$DryRun
  )

  if ($Preset -lt 2) {
    return
  }

  $afd = 'HKLM:\SYSTEM\CurrentControlSet\Services\AFD\Parameters'
  if ($DryRun) {
    Write-UjInformation -Message ("[DryRun] AFD FastSendDatagramThreshold={0}" -f $AfdThreshold)
    return
  }

  if (-not $PSCmdlet.ShouldProcess($afd, ("Set FastSendDatagramThreshold to {0}" -f $AfdThreshold))) {
    return
  }

  Set-UjRegistryValue -Key $afd -Name 'FastSendDatagramThreshold' -Type DWord -Value $AfdThreshold -Confirm:$false
  Write-UjInformation -Message ("AFD FastSendDatagramThreshold set to {0} (reboot recommended)." -f $AfdThreshold)
}

function Set-UjUndocumentedNetworkMmcssTuning {
  [CmdletBinding(SupportsShouldProcess = $true)]
  param(
    [Parameter(Mandatory)]
    [ValidateSet(1, 2, 3)]
    [int]$Preset,

    [Parameter()]
    [switch]$DryRun
  )

  if ($Preset -lt 3) {
    return
  }

  $mm = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
  if ($DryRun) {
    Write-UjInformation -Message '[DryRun] SystemResponsiveness=0; NetworkThrottlingIndex=FFFFFFFF'
    return
  }

  if (-not $PSCmdlet.ShouldProcess($mm, 'Set SystemResponsiveness=0 and NetworkThrottlingIndex=FFFFFFFF')) {
    return
  }

  Set-UjRegistryValue -Key $mm -Name 'SystemResponsiveness' -Type DWord -Value 0 -Confirm:$false
  Set-UjRegistryValue -Key $mm -Name 'NetworkThrottlingIndex' -Type DWord -Value 0xFFFFFFFF -Confirm:$false
}

function Set-UjUroState {
  [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
  param(
    [Parameter(Mandatory)]
    [ValidateSet('Enabled', 'Disabled')]
    [string]$State,

    [Parameter()]
    [switch]$DryRun
  )

  $cmd = @('int', 'udp', 'set', 'global', ('uro={0}' -f $State.ToLowerInvariant()))
  if ($DryRun) {
    Write-UjInformation -Message ("[DryRun] netsh {0}" -f ($cmd -join ' '))
    return
  }

  if (-not $PSCmdlet.ShouldProcess('UDP', ("Set URO to {0}" -f $State))) {
    return
  }

  try {
    & netsh @cmd | Out-Null
  } catch {
    Write-Warning -Message 'Setting URO via netsh failed (may not exist on all builds).'
  }
}

function Set-UjPowerPlan {
  [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
  param(
    [Parameter(Mandatory)]
    [ValidateSet('Balanced', 'HighPerformance', 'Ultimate')]
    [string]$PowerPlan,

    [Parameter()]
    [switch]$DryRun
  )

  $guidHigh = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
  $guidUlt = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
  $guidBalanced = '381b4222-f694-41f0-9685-ff5bb260df2e'

  $guid =
    if ($PowerPlan -eq 'HighPerformance') { $guidHigh }
    elseif ($PowerPlan -eq 'Ultimate') { $guidUlt }
    else { $guidBalanced }

  if ($DryRun) {
    Write-UjInformation -Message ("[DryRun] powercfg /S {0}" -f $guid)
    return
  }

  if (-not $PSCmdlet.ShouldProcess($PowerPlan, 'Set active power plan')) {
    return
  }

  if ($PowerPlan -eq 'Ultimate') {
    try {
      & powercfg /duplicatescheme $guidUlt | Out-Null
    } catch {
      Write-Verbose -Message 'powercfg /duplicatescheme failed.'
    }
  }

  & powercfg /S $guid | Out-Null
}

function Set-UjGameDvrState {
  [CmdletBinding(SupportsShouldProcess = $true)]
  param(
    [Parameter(Mandatory)]
    [ValidateSet('Enabled', 'Disabled')]
    [string]$State,

    [Parameter()]
    [switch]$DryRun
  )

  if ($DryRun) {
    Write-UjInformation -Message ("[DryRun] Set GameDVR capture to {0}." -f $State)
    return
  }

  $dvr = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR'
  if (-not (Test-Path -Path $dvr)) {
    return
  }

  $value = if ($State -eq 'Disabled') { 0 } else { 1 }
  if (-not $PSCmdlet.ShouldProcess($dvr, ("Set GameDVR capture to {0}" -f $State))) {
    return
  }

  Set-ItemProperty -Path $dvr -Name 'AppCaptureEnabled' -Type DWord -Value $value -Force
  Set-ItemProperty -Path $dvr -Name 'HistoricalCaptureEnabled' -Type DWord -Value $value -Force
}

function Show-UjSummary {
  [CmdletBinding()]
  param()

  Write-UjInformation -Message "`nQoS Policies (QoS_*):"
  try {
    Get-UjManagedQosPolicy | Sort-Object -Property Name | Format-Table -AutoSize
  } catch {
    Write-Verbose -Message 'QoS summary skipped.'
  }

  Write-UjInformation -Message "`nNIC Key Properties (subset):"
  try {
    foreach ($nic in (Get-NetAdapter -Physical | Where-Object { $_.Status -eq 'Up' })) {
      Get-NetAdapterAdvancedProperty -Name $nic.Name |
        Where-Object { $_.DisplayName -match 'Energy|Interrupt|Flow|Offload|Large Send|Jumbo|Wake|Power|Green|NS|ARP|ITR|Buffer' } |
        Sort-Object -Property DisplayName |
        Format-Table -AutoSize
    }
  } catch {
    Write-Verbose -Message 'NIC summary skipped.'
  }
}

function Reset-UjBaseline {
  [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
  param(
    [Parameter()]
    [switch]$DryRun
  )

  Set-UjPowerPlan -PowerPlan Balanced -DryRun:$DryRun

  $mmKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
  $afdKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\AFD\Parameters'
  $gamesKey = Join-Path -Path $mmKey -ChildPath 'Tasks\\Games'
  $qosRegKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\QoS'

  if (-not $DryRun -and $PSCmdlet.ShouldProcess($mmKey, 'Remove registry tweaks')) {
    Remove-ItemProperty -Path $mmKey -Name 'NetworkThrottlingIndex' -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $mmKey -Name 'SystemResponsiveness' -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $afdKey -Name 'FastSendDatagramThreshold' -ErrorAction SilentlyContinue
    if (Test-Path -Path $gamesKey) {
      Remove-Item -Path $gamesKey -Recurse -Force -ErrorAction SilentlyContinue
    }
  } elseif ($DryRun) {
    Write-UjInformation -Message '[DryRun] Remove registry tweaks (NetworkThrottlingIndex/SystemResponsiveness/FastSendDatagramThreshold/MMCSS Games)'
  }

  Set-UjGameDvrState -State Enabled -DryRun:$DryRun

  if ($DryRun) {
    Write-UjInformation -Message '[DryRun] Reset NIC advanced properties and re-enable RSC.'
  } else {
    foreach ($adapter in (Get-NetAdapter -Physical | Where-Object { $_.Status -eq 'Up' })) {
      if ($PSCmdlet.ShouldProcess($adapter.Name, 'Reset NetAdapterAdvancedProperty')) {
        Reset-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName '*' -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
      }
      if ($PSCmdlet.ShouldProcess($adapter.Name, 'Enable NetAdapterRsc')) {
        Enable-NetAdapterRsc -Name $adapter.Name -ErrorAction SilentlyContinue | Out-Null
      }
    }
  }

  if ($DryRun) {
    Write-UjInformation -Message '[DryRun] Remove QoS_* policies and clear Do not use NLA.'
  } else {
    Remove-UjManagedQosPolicy
    Remove-ItemProperty -Path $qosRegKey -Name 'Do not use NLA' -ErrorAction SilentlyContinue
  }

  foreach ($netshArgs in @(
    @('int', 'tcp', 'set', 'global', 'autotuninglevel=normal'),
    @('interface', 'teredo', 'set', 'state', 'default'),
    @('int', 'udp', 'set', 'global', 'uro=enabled'),
    @('int', 'tcp', 'set', 'supplemental', 'internet', 'icw=default'),
    @('int', 'tcp', 'set', 'supplemental', 'internet', 'minrto=default'),
    @('int', 'tcp', 'set', 'supplemental', 'internet', 'delayedacktimeout=default'),
    @('int', 'tcp', 'set', 'supplemental', 'internet', 'delayedackfrequency=default'),
    @('int', 'tcp', 'set', 'supplemental', 'internet', 'rack=disabled'),
    @('int', 'tcp', 'set', 'supplemental', 'internet', 'taillossprobe=disabled'),
    @('int', 'tcp', 'set', 'global', 'prr=enabled'),
    @('int', 'tcp', 'set', 'global', 'hystart=enabled')
  )) {
    if ($DryRun) {
      Write-UjInformation -Message ("[DryRun] netsh {0}" -f ($netshArgs -join ' '))
      continue
    }

    if (-not $PSCmdlet.ShouldProcess('netsh', ($netshArgs -join ' '))) {
      continue
    }

    try {
      & netsh @netshArgs | Out-Null
    } catch {
      Write-Verbose -Message ("netsh failed: {0}" -f ($netshArgs -join ' '))
    }
  }

  try {
    $ts = Get-NetTCPSetting -SettingName Internet
    if ($DryRun) {
      Write-UjInformation -Message '[DryRun] Set NetTCPSetting Internet: CongestionProvider=NewReno, ECN=Disabled'
    } elseif ($PSCmdlet.ShouldProcess('NetTCPSetting Internet', 'Restore congestion & ECN defaults')) {
      Set-NetTCPSetting -SettingName Internet -CongestionProvider NewReno -EcnCapability Disabled `
        -AutoReusePortRangeEnabled $ts.AutoReusePortRangeEnabled `
        -AutoReusePortRangeNumberOfPorts $ts.AutoReusePortRangeNumberOfPorts `
        -AutoReusePortRangeMaxPorts $ts.AutoReusePortRangeMaxPorts | Out-Null
    }
  } catch {
    Write-Verbose -Message 'Get/Set-NetTCPSetting failed (may be unavailable on this platform).'
  }

  Write-UjInformation -Message 'All settings restored to baseline defaults. Reboot recommended for full effect.'
}
