function Set-UjNicAdvancedPropertyIfSupported {
  [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
  param(
    [Parameter(Mandatory)]
    [string]$Name,

    [Parameter(Mandatory)]
    [string]$DisplayName,

    [Parameter(Mandatory)]
    [string]$Value,

    [Parameter()]
    [switch]$DryRun
  )

  $property = Get-NetAdapterAdvancedProperty -Name $Name -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $DisplayName }
  if (-not $property) {
    return
  }

  if ($DryRun) {
    Write-UjInformation -Message ("[DryRun] {0}: {1} => {2}" -f $Name, $DisplayName, $Value)
    return
  }

  if (-not $PSCmdlet.ShouldProcess(("{0}: {1}" -f $Name, $DisplayName), ("Set to '{0}'" -f $Value))) {
    return
  }

  try {
    Set-NetAdapterAdvancedProperty -Name $Name -DisplayName $DisplayName -DisplayValue $Value -NoRestart -ErrorAction Stop | Out-Null
  } catch {
    Write-Warning -Message ("{0}: failed to set {1}" -f $Name, $DisplayName)
  }
}

function Set-UjNicConfiguration {
  [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
  param(
    [Parameter(Mandatory)]
    [ValidateSet(1, 2, 3)]
    [int]$Preset,

    [Parameter()]
    [switch]$DryRun
  )

  $adapters = Get-NetAdapter -Physical | Where-Object { $_.Status -eq 'Up' }
  foreach ($nic in $adapters) {
    Write-UjInformation -Message ("NIC: {0}" -f $nic.Name)

    Set-UjNicAdvancedPropertyIfSupported -Name $nic.Name -DisplayName 'Energy Efficient Ethernet' -Value 'Disabled' -DryRun:$DryRun

    if ($Preset -ge 2) {
      foreach ($value in @('Disabled', 'Off', 'Low')) {
        Set-UjNicAdvancedPropertyIfSupported -Name $nic.Name -DisplayName 'Interrupt Moderation' -Value $value -DryRun:$DryRun
      }

      Set-UjNicAdvancedPropertyIfSupported -Name $nic.Name -DisplayName 'Flow Control' -Value 'Disabled' -DryRun:$DryRun
      Set-UjNicAdvancedPropertyIfSupported -Name $nic.Name -DisplayName 'Green Ethernet' -Value 'Disabled' -DryRun:$DryRun
      Set-UjNicAdvancedPropertyIfSupported -Name $nic.Name -DisplayName 'Power Saving Mode' -Value 'Disabled' -DryRun:$DryRun
      Set-UjNicAdvancedPropertyIfSupported -Name $nic.Name -DisplayName 'Jumbo Packet' -Value 'Disabled' -DryRun:$DryRun
    }

    if ($Preset -ge 3) {
      if ($DryRun) {
        Write-UjInformation -Message ("[DryRun] Disable-NetAdapterRsc {0}" -f $nic.Name)
      } elseif ($PSCmdlet.ShouldProcess($nic.Name, 'Disable NetAdapterRsc')) {
        try {
          Disable-NetAdapterRsc -Name $nic.Name -Confirm:$false -ErrorAction Stop | Out-Null
        } catch {
          Write-Warning -Message ("RSC disable failed on {0}" -f $nic.Name)
        }
      }

      foreach ($displayName in @(
        'Large Send Offload v2 (IPv4)', 'Large Send Offload v2 (IPv6)',
        'UDP Checksum Offload (IPv4)', 'UDP Checksum Offload (IPv6)',
        'TCP Checksum Offload (IPv4)', 'TCP Checksum Offload (IPv6)'
      )) {
        Set-UjNicAdvancedPropertyIfSupported -Name $nic.Name -DisplayName $displayName -Value 'Disabled' -DryRun:$DryRun
      }

      Set-UjNicAdvancedPropertyIfSupported -Name $nic.Name -DisplayName 'ARP Offload' -Value 'Disabled' -DryRun:$DryRun
      Set-UjNicAdvancedPropertyIfSupported -Name $nic.Name -DisplayName 'NS Offload' -Value 'Disabled' -DryRun:$DryRun
      Set-UjNicAdvancedPropertyIfSupported -Name $nic.Name -DisplayName 'Wake on Magic Packet' -Value 'Disabled' -DryRun:$DryRun
      Set-UjNicAdvancedPropertyIfSupported -Name $nic.Name -DisplayName 'Wake on pattern match' -Value 'Disabled' -DryRun:$DryRun
      Set-UjNicAdvancedPropertyIfSupported -Name $nic.Name -DisplayName 'WOL & Shutdown Link Speed' -Value 'Disabled' -DryRun:$DryRun

      $itr = Get-NetAdapterAdvancedProperty -Name $nic.Name -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq 'ITR' }
      if ($itr) {
        Set-UjNicAdvancedPropertyIfSupported -Name $nic.Name -DisplayName 'ITR' -Value '0' -DryRun:$DryRun
      }

      Set-UjNicAdvancedPropertyIfSupported -Name $nic.Name -DisplayName 'Receive Buffers' -Value '256' -DryRun:$DryRun
      Set-UjNicAdvancedPropertyIfSupported -Name $nic.Name -DisplayName 'Transmit Buffers' -Value '256' -DryRun:$DryRun
    }
  }
}

