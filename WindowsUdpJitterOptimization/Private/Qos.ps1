function Get-UjManagedQosPolicy {
  [CmdletBinding()]
  [OutputType([object])]
  param()

  try {
    Get-NetQosPolicy -ErrorAction Stop | Where-Object { $_.Name -like 'QoS_*' }
  } catch {
    return
  }
}

function Remove-UjManagedQosPolicy {
  [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
  param()

  foreach ($policy in (Get-UjManagedQosPolicy)) {
    if (-not $PSCmdlet.ShouldProcess($policy.Name, 'Remove NetQosPolicy')) {
      continue
    }

    try {
      Remove-NetQosPolicy -Name $policy.Name -Confirm:$false -ErrorAction Stop | Out-Null
    } catch {
      Write-Verbose -Message ("Failed to remove QoS policy: {0}" -f $policy.Name)
    }
  }
}

function New-UjDscpPolicyByPort {
  [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
  param(
    [Parameter(Mandatory)]
    [string]$Name,

    [Parameter(Mandatory)]
    [ValidateRange(1, 65535)]
    [uint16]$PortStart,

    [Parameter(Mandatory)]
    [ValidateRange(1, 65535)]
    [uint16]$PortEnd,

    [Parameter()]
    [ValidateRange(0, 63)]
    [sbyte]$Dscp = 46,

    [Parameter()]
    [switch]$DryRun
  )

  if ($PortEnd -lt $PortStart) {
    throw 'PortEnd must be >= PortStart.'
  }

  if ($DryRun) {
    Write-UjInformation -Message ("[DryRun] QoS {0} UDP {1}-{2} DSCP={3} (local store)" -f $Name, $PortStart, $PortEnd, $Dscp)
    return
  }

  foreach ($existing in (Get-UjManagedQosPolicy | Where-Object { $_.Name -like ($Name + '*') })) {
    if (-not $PSCmdlet.ShouldProcess($existing.Name, 'Remove NetQosPolicy')) {
      continue
    }

    try {
      Remove-NetQosPolicy -Name $existing.Name -Confirm:$false | Out-Null
    } catch {
      Write-Verbose -Message ("Failed to remove existing QoS policy: {0}" -f $existing.Name)
    }
  }

  for ($port = [int]$PortStart; $port -le [int]$PortEnd; $port++) {
    $policyName = if ($PortStart -eq $PortEnd) { $Name } else { "{0}_{1}" -f $Name, $port }
    if (-not $PSCmdlet.ShouldProcess($policyName, 'Create NetQosPolicy (DSCP by UDP port)')) {
      continue
    }

    New-NetQosPolicy -Name $policyName -IPPortMatchCondition ([uint16]$port) -IPProtocolMatchCondition UDP -DSCPAction $Dscp -NetworkProfile All | Out-Null
  }
}

function New-UjDscpPolicyByApp {
  [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
  param(
    [Parameter(Mandatory)]
    [string]$Name,

    [Parameter(Mandatory)]
    [string]$ExePath,

    [Parameter()]
    [ValidateRange(0, 63)]
    [sbyte]$Dscp = 46,

    [Parameter()]
    [switch]$DryRun
  )

  if ($DryRun) {
    Write-UjInformation -Message ("[DryRun] QoS {0} App={1} DSCP={2} (local store)" -f $Name, $ExePath, $Dscp)
    return
  }

  foreach ($existing in (Get-UjManagedQosPolicy | Where-Object { $_.Name -eq $Name })) {
    if (-not $PSCmdlet.ShouldProcess($existing.Name, 'Remove NetQosPolicy')) {
      continue
    }

    try {
      Remove-NetQosPolicy -Name $existing.Name -Confirm:$false | Out-Null
    } catch {
      Write-Verbose -Message ("Failed to remove existing QoS policy: {0}" -f $existing.Name)
    }
  }

  if (-not $PSCmdlet.ShouldProcess($Name, 'Create NetQosPolicy (DSCP by app path)')) {
    return
  }

  New-NetQosPolicy -Name $Name -AppPathNameMatchCondition $ExePath -DSCPAction $Dscp -NetworkProfile All | Out-Null
}
