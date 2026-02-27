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
  Set-UjRegistryValue -Key $audio -Name 'BackgroundOnly' -Type DWord -Value 0
  Set-UjRegistryValue -Key $audio -Name 'Clock Rate' -Type DWord -Value 10000
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
          $guid = '{' + $Matches[1] + '}'
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

  New-ItemProperty -Path $dvr -Name 'AppCaptureEnabled' -PropertyType DWord -Value $value -Force | Out-Null
  New-ItemProperty -Path $dvr -Name 'HistoricalCaptureEnabled' -PropertyType DWord -Value $value -Force | Out-Null
}

function Show-UjSummary {
  [CmdletBinding()]
  param()

  Write-UjInformation -Message "`n=== Performance Summary ==="
  Write-UjInformation -Message 'QoS Policies (Managed):'
  try {
    $managed = Get-UjManagedQosPolicy
    if ($managed) {
      $managed | Sort-Object -Property Name | Select-Object Name, DSCPAction, IPPortMatchCondition, AppPathNameMatchCondition | Format-Table -AutoSize
    } else {
      Write-UjInformation -Message '  No active managed QoS policies.'
    }
  } catch {
    Write-Verbose -Message 'QoS summary skipped.'
  }

  Write-UjInformation -Message "`nNIC Key Optimizations:"
  try {
    foreach ($nic in (Get-UjPhysicalUpAdapter)) {
      $props = Get-NetAdapterAdvancedProperty -Name $nic.Name |
        Where-Object { $_.DisplayName -match 'Energy|Interrupt|Flow|Offload|Large Send|Jumbo|Wake|Power|Green|NS|ARP|ITR|Buffer' }
      if ($props) {
        Write-UjInformation -Message ("  Adapter: {0}" -f $nic.Name)
        $props | Sort-Object -Property DisplayName | Select-Object DisplayName, DisplayValue | Format-Table -AutoSize
      }
    }
  } catch {
    Write-Verbose -Message 'NIC summary skipped.'
  }
}
