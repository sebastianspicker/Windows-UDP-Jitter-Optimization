function Backup-UjState {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$BackupFolder,

    [Parameter()]
    [switch]$DryRun
  )

  Write-UjInformation -Message 'Backing up current state ...'
  if ($DryRun) {
    Write-UjInformation -Message '[DryRun] Skip backup (no writes).'
    return
  }

  New-UjDirectory -Path $BackupFolder | Out-Null

  Export-UjRegistryKey -RegistryPath $script:UjRegistryPathSystemProfileReg -OutFile (Join-Path -Path $BackupFolder -ChildPath $script:UjBackupFileSystemProfile)
  Export-UjRegistryKey -RegistryPath $script:UjRegistryPathAfdParametersReg -OutFile (Join-Path -Path $BackupFolder -ChildPath $script:UjBackupFileAfdParameters)

  try {
    $policies = Get-UjManagedQosPolicy
    if ($policies) {
      $policies | Export-CliXml -Path (Join-Path -Path $BackupFolder -ChildPath $script:UjBackupFileQosOurs)
    } else {
      Write-Verbose -Message 'No QoS policies found to backup.'
    }
  } catch {
    Write-Warning -Message 'QoS backup skipped (Get-NetQosPolicy failed).'
  }

  try {
    $rows = foreach ($n in (Get-UjPhysicalUpAdapters)) {
      Get-NetAdapterAdvancedProperty -Name $n.Name |
        Select-Object @{ Name = 'Adapter'; Expression = { $n.Name } }, DisplayName, RegistryKeyword, DisplayValue, RegistryValue
    }
    $rows | Export-Csv -NoTypeInformation -Path (Join-Path -Path $BackupFolder -ChildPath $script:UjBackupFileNicAdvanced)
  } catch {
    Write-Warning -Message 'NIC advanced snapshot failed.'
  }

  try {
    Get-NetAdapterRsc | Select-Object Name, IPv4Enabled, IPv6Enabled |
      Export-Csv -NoTypeInformation -Path (Join-Path -Path $BackupFolder -ChildPath $script:UjBackupFileRsc)
  } catch {
    Write-Verbose -Message 'RSC snapshot failed.'
  }

  try {
    $powerPlanOutput = & powercfg /GetActiveScheme 2>&1
    if ($LASTEXITCODE -eq 0 -and $powerPlanOutput) {
      $text = $powerPlanOutput -join "`n"
      # Normalize: extract GUID (with or without braces) and write with braces for consistent restore
      $guid = $null
      if ($text -match '\{([0-9a-fA-F-]+)\}') { $guid = $Matches[0] }
      elseif ($text -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') { $guid = '{' + $Matches[1] + '}' }
      if ($guid) {
        $guid | Out-File -FilePath (Join-Path -Path $BackupFolder -ChildPath $script:UjBackupFilePowerplan) -Encoding utf8 -NoNewline
      } else {
        $text | Out-File -FilePath (Join-Path -Path $BackupFolder -ChildPath $script:UjBackupFilePowerplan) -Encoding utf8
      }
    } else {
      Write-Verbose -Message 'Power plan snapshot skipped (powercfg failed or returned no output).'
    }
  } catch {
    Write-Verbose -Message ("Power plan snapshot failed: {0}" -f $_.Exception.Message)
  }
}

function Restore-UjRegistryFromBackup {
  [CmdletBinding(SupportsShouldProcess = $true)]
  param([Parameter(Mandatory)][string]$BackupFolder)

  $systemProfileReg = Join-Path -Path $BackupFolder -ChildPath $script:UjBackupFileSystemProfile
  if ($PSCmdlet.ShouldProcess($systemProfileReg, 'Import registry file')) {
    Import-UjRegistryFile -InFile $systemProfileReg | Out-Null
  }
  $afdReg = Join-Path -Path $BackupFolder -ChildPath $script:UjBackupFileAfdParameters
  if ($PSCmdlet.ShouldProcess($afdReg, 'Import registry file')) {
    Import-UjRegistryFile -InFile $afdReg | Out-Null
  }
}

function Restore-UjQosFromBackup {
  [CmdletBinding(SupportsShouldProcess = $true)]
  param([Parameter(Mandatory)][string]$BackupFolder)

  $qosInventory = Join-Path -Path $BackupFolder -ChildPath $script:UjBackupFileQosOurs
  $qosItems = $null
  if (Test-Path -Path $qosInventory) {
    try { $qosItems = Import-CliXml -Path $qosInventory } catch {
      Write-Warning -Message ("QoS restore skipped: could not import/parse {0}. {1}" -f $qosInventory, $_.Exception.Message)
      return
    }
  } else {
    Write-Verbose -Message 'No QoS backup file found; skipping QoS restore.'
    return
  }

  if ($PSCmdlet.ShouldProcess('Managed QoS policies', 'Remove before restore')) {
    Remove-UjManagedQosPolicy
  }

  foreach ($item in $qosItems) {
    $name = $item.Name
    $dscp = $script:UjDefaultDscp
    try {
      if ($item.PSObject.Properties.Name -contains 'DSCPAction' -and $null -ne $item.DSCPAction) { $dscpValue = [int]$item.DSCPAction; if ($dscpValue -ge 0 -and $dscpValue -le 63) { $dscp = $dscpValue } }
      elseif ($item.PSObject.Properties.Name -contains 'DSCPValue' -and $null -ne $item.DSCPValue) { $dscpValue = [int]$item.DSCPValue; if ($dscpValue -ge 0 -and $dscpValue -le 63) { $dscp = $dscpValue } }
    } catch { Write-Verbose -Message ("Failed to parse DSCP for policy {0}, using default" -f $name) }
    $proto = 'UDP'
    if ($item.PSObject.Properties.Name -contains 'IPProtocolMatchCondition' -and $item.IPProtocolMatchCondition) { $proto = [string]$item.IPProtocolMatchCondition }

    $portHandled = $false
    if ($item.PSObject.Properties.Name -contains 'IPPortMatchCondition') {
      try {
        $portValue = [int]$item.IPPortMatchCondition
        if ($portValue -gt 0 -and $portValue -le 65535) {
          if ($PSCmdlet.ShouldProcess($name, 'Recreate NetQosPolicy (port-based)')) {
            try { New-NetQosPolicy -Name $name -IPPortMatchCondition ([uint16]$portValue) -IPProtocolMatchCondition $proto -DSCPAction ([sbyte]$dscp) -NetworkProfile All | Out-Null }
            catch { Write-Warning -Message ("QoS policy '{0}' (port-based) failed: {1}" -f $name, $_.Exception.Message) }
          }
          $portHandled = $true
        }
      } catch { }
    }
    if (-not $portHandled -and $item.PSObject.Properties.Name -contains 'AppPathNameMatchCondition' -and $item.AppPathNameMatchCondition) {
      if ($PSCmdlet.ShouldProcess($name, 'Recreate NetQosPolicy (app-based)')) {
        try { New-NetQosPolicy -Name $name -AppPathNameMatchCondition ([string]$item.AppPathNameMatchCondition) -DSCPAction ([sbyte]$dscp) -NetworkProfile All | Out-Null }
        catch { Write-Warning -Message ("QoS policy '{0}' (app-based) failed: {1}" -f $name, $_.Exception.Message) }
      }
    }
  }
}

function Restore-UjNicFromBackup {
  [CmdletBinding(SupportsShouldProcess = $true)]
  param([Parameter(Mandatory)][string]$BackupFolder)

  $csv = Join-Path -Path $BackupFolder -ChildPath $script:UjBackupFileNicAdvanced
  if (-not (Test-Path -Path $csv)) { return }
  try {
    $data = Import-Csv -Path $csv
    $firstRow = $data | Select-Object -First 1
    if (-not $firstRow -or -not ($firstRow.PSObject.Properties.Name -contains 'Adapter')) {
      Write-Warning -Message 'NIC advanced restore skipped: CSV missing or invalid (no Adapter column).'
      return
    }
    $adapters = $data | Select-Object -ExpandProperty Adapter -Unique
    foreach ($adapter in $adapters) {
      foreach ($property in ($data | Where-Object { $_.Adapter -eq $adapter })) {
        try {
          if ($property.PSObject.Properties.Name -contains 'DisplayName' -and [string]::IsNullOrEmpty($property.DisplayName) -eq $false -and $property.PSObject.Properties.Name -contains 'DisplayValue') {
            if ($PSCmdlet.ShouldProcess($adapter, ("Restore NIC advanced property: {0}" -f $property.DisplayName))) {
              Set-NetAdapterAdvancedProperty -Name $adapter -DisplayName $property.DisplayName -DisplayValue $property.DisplayValue -NoRestart -ErrorAction Stop | Out-Null
            }
            continue
          }
          if ($property.RegistryKeyword -and [string]::IsNullOrEmpty($property.RegistryKeyword) -eq $false -and [string]::IsNullOrEmpty($property.RegistryValue) -eq $false) {
            if ($PSCmdlet.ShouldProcess($adapter, ("Restore NIC advanced property keyword: {0}" -f $property.RegistryKeyword))) {
              Set-NetAdapterAdvancedProperty -Name $adapter -RegistryKeyword $property.RegistryKeyword -RegistryValue $property.RegistryValue -NoRestart -ErrorAction Stop | Out-Null
            }
            continue
          }
        } catch { Write-Verbose -Message ("NIC property restore failed: {0} ({1})" -f $adapter, $property.DisplayName) }
      }
    }
  } catch { Write-Warning -Message 'NIC advanced restore error.' }
}

function Restore-UjRscFromBackup {
  [CmdletBinding(SupportsShouldProcess = $true)]
  param([Parameter(Mandatory)][string]$BackupFolder)

  $rscFile = Join-Path -Path $BackupFolder -ChildPath $script:UjBackupFileRsc
  if (-not (Test-Path -Path $rscFile)) { return }
  try {
    foreach ($row in (Import-Csv -Path $rscFile)) {
      $ipv4Enabled = [string]$row.IPv4Enabled -ieq 'True'
      $ipv6Enabled = [string]$row.IPv6Enabled -ieq 'True'
      $enable = $ipv4Enabled -or $ipv6Enabled
      if ($enable) {
        if ($PSCmdlet.ShouldProcess($row.Name, 'Enable NetAdapterRsc')) { Enable-NetAdapterRsc -Name $row.Name -ErrorAction SilentlyContinue | Out-Null }
      } else {
        if ($PSCmdlet.ShouldProcess($row.Name, 'Disable NetAdapterRsc')) { Disable-NetAdapterRsc -Name $row.Name -Confirm:$false -ErrorAction SilentlyContinue | Out-Null }
      }
    }
  } catch { Write-Verbose -Message 'RSC restore failed.' }
}

function Restore-UjPowerPlanFromBackup {
  [CmdletBinding(SupportsShouldProcess = $true)]
  param([Parameter(Mandatory)][string]$BackupFolder)

  $powerPlanFile = Join-Path -Path $BackupFolder -ChildPath $script:UjBackupFilePowerplan
  if (-not (Test-Path -Path $powerPlanFile)) { return }
  $text = Get-Content -Path $powerPlanFile -Raw
  $guid = $null
  if ($text -match '\{([0-9a-fA-F-]+)\}') { $guid = $Matches[0] }
  elseif ($text -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') { $guid = $Matches[1] }
  if (-not $guid) {
    Write-Warning -Message 'Power plan restore skipped: no valid GUID found in powerplan.txt.'
    return
  }
  if ($PSCmdlet.ShouldProcess($guid, 'Restore power plan')) {
    try {
      $null = & powercfg /S $guid 2>&1
      if ($LASTEXITCODE -ne 0) { Write-Warning -Message ("Power plan restore failed (powercfg /S exited with {0})." -f $LASTEXITCODE) }
    } catch { Write-Verbose -Message ("Power plan restore failed: {0}" -f $_.Exception.Message) }
  }
}

function Restore-UjState {
  [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
  param(
    [Parameter(Mandatory)]
    [string]$BackupFolder,

    [Parameter()]
    [switch]$DryRun
  )

  Write-UjInformation -Message 'Restoring previous state ...'
  if ($DryRun) {
    Write-UjInformation -Message '[DryRun] Skip restore (no writes).'
    return
  }

  Restore-UjRegistryFromBackup -BackupFolder $BackupFolder
  Restore-UjQosFromBackup -BackupFolder $BackupFolder
  Restore-UjNicFromBackup -BackupFolder $BackupFolder
  Restore-UjRscFromBackup -BackupFolder $BackupFolder
  Restore-UjPowerPlanFromBackup -BackupFolder $BackupFolder

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

  $mm = $script:UjRegistryPathSystemProfile
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

  $qos = $script:UjRegistryPathQos
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

  $afd = $script:UjRegistryPathAfdParameters
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

  $mm = $script:UjRegistryPathSystemProfile
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
    $null = & netsh @cmd 2>&1
    if ($LASTEXITCODE -ne 0) {
      Write-Warning -Message ("Setting URO via netsh failed (exit code {0}; may not exist on all builds)." -f $LASTEXITCODE)
    }
  } catch {
    Write-Warning -Message ("Setting URO via netsh failed: {0}" -f $_.Exception.Message)
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
      $dupOut = & powercfg /duplicatescheme $guidUlt 2>&1
      if ($LASTEXITCODE -eq 0 -and $dupOut) {
        $dupText = $dupOut -join ' '
        if ($dupText -match '\{([0-9a-fA-F-]+)\}') {
          $guid = $Matches[0]
        } elseif ($dupText -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
          $guid = $Matches[1]
        }
      }
    } catch {
      Write-Verbose -Message 'powercfg /duplicatescheme failed.'
    }
  }

  $null = & powercfg /S $guid 2>&1
  if ($LASTEXITCODE -ne 0) {
    Write-Warning -Message ("Setting power plan failed (powercfg /S exited with {0})." -f $LASTEXITCODE)
  }
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

  Set-ItemProperty -Path $dvr -Name 'AppCaptureEnabled' -PropertyType DWord -Value $value -Force
  Set-ItemProperty -Path $dvr -Name 'HistoricalCaptureEnabled' -PropertyType DWord -Value $value -Force
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
    foreach ($nic in (Get-UjPhysicalUpAdapters)) {
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

  $mmKey = $script:UjRegistryPathSystemProfile
  $afdKey = $script:UjRegistryPathAfdParameters
  $gamesKey = Join-Path -Path $mmKey -ChildPath 'Tasks\Games'
  $qosRegKey = $script:UjRegistryPathQos

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
    try {
      $adapters = Get-UjPhysicalUpAdapters
    } catch {
      Write-Warning -Message ("Get-NetAdapter failed during reset: {0}" -f $_.Exception.Message)
      $adapters = @()
    }
    foreach ($adapter in $adapters) {
      foreach ($displayName in $script:UjNicResetDisplayNames) {
        if ($PSCmdlet.ShouldProcess(("{0}: {1}" -f $adapter.Name, $displayName), 'Reset NetAdapterAdvancedProperty')) {
          try {
            Reset-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName $displayName -Confirm:$false -ErrorAction Stop | Out-Null
          } catch {
            Write-Verbose -Message ("Reset property '{0}' on {1}: {2}" -f $displayName, $adapter.Name, $_.Exception.Message)
          }
        }
      }
      if ($PSCmdlet.ShouldProcess($adapter.Name, 'Enable NetAdapterRsc')) {
        Enable-NetAdapterRsc -Name $adapter.Name -ErrorAction SilentlyContinue | Out-Null
      }
    }
  }

  if ($DryRun) {
    Write-UjInformation -Message '[DryRun] Remove QoS_* policies and clear Do not use NLA.'
  } else {
    if ($PSCmdlet.ShouldProcess('Managed QoS policies', 'Remove QoS_* policies')) {
      Remove-UjManagedQosPolicy
    }
    if ($PSCmdlet.ShouldProcess($qosRegKey, 'Remove Do not use NLA registry value')) {
      Remove-ItemProperty -Path $qosRegKey -Name 'Do not use NLA' -ErrorAction SilentlyContinue
    }
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
      $null = & netsh @netshArgs 2>&1
      if ($LASTEXITCODE -ne 0) {
        Write-Warning -Message ("netsh failed (exit {0}): {1}" -f $LASTEXITCODE, ($netshArgs -join ' '))
      }
    } catch {
      Write-Warning -Message ("netsh failed: {0} - {1}" -f ($netshArgs -join ' '), $_.Exception.Message)
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
