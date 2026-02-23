function Get-UjPhysicalUpAdapter {
  [CmdletBinding()]
  [OutputType([Microsoft.PowerShell.Cmdletization.GeneratedTypes.NetAdapter.NetAdapter[]])]
  param()

  Get-NetAdapter -Physical -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' }
}

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

  # P0 Fix: Prefer standardized RegistryKeywords over localized DisplayNames
  $keyword = if ($script:UjNicKeywordMap.ContainsKey($DisplayName)) { $script:UjNicKeywordMap[$DisplayName] } else { $null }

  $property = if ($keyword) {
    Get-NetAdapterAdvancedProperty -Name $Name -RegistryKeyword $keyword -ErrorAction SilentlyContinue
  } else {
    Get-NetAdapterAdvancedProperty -Name $Name -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $DisplayName }
  }

  if (-not $property) {
    Write-Verbose -Message ("{0}: property '{1}' (keyword={2}) not found or not supported." -f $Name, $DisplayName, $keyword)
    return
  }

  if ($DryRun) {
    $keywordLabel = if ($keyword) { $keyword } else { 'no-keyword' }
    Write-UjInformation -Message ("[DryRun] {0}: {1} ({2}) => {3}" -f $Name, $DisplayName, $keywordLabel, $Value)
    return
  }

  $targetHint = if ($keyword) { "Keyword: $keyword" } else { "DisplayName: $DisplayName" }
  if (-not $PSCmdlet.ShouldProcess(("{0}: {1}" -f $Name, $DisplayName), ("Set to '{0}' via {1}" -f $Value, $targetHint))) {
    return
  }

  try {
    if ($keyword) {
      Set-NetAdapterAdvancedProperty -Name $Name -RegistryKeyword $keyword -RegistryValue $Value -NoRestart -ErrorAction Stop | Out-Null
    } else {
      Set-NetAdapterAdvancedProperty -Name $Name -DisplayName $DisplayName -DisplayValue $Value -NoRestart -ErrorAction Stop | Out-Null
    }
  } catch {
    Write-Warning -Message ("{0}: failed to set {1} ({2})" -f $Name, $DisplayName, $_.Exception.Message)
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

  try {
    $adapters = Get-UjPhysicalUpAdapter
  } catch {
    Write-Warning -Message ("Get-NetAdapter failed: {0}" -f $_.Exception.Message)
    return
  }

  foreach ($nic in $adapters) {
    Write-UjInformation -Message ("NIC: {0}" -f $nic.Name)

    Set-UjNicAdvancedPropertyIfSupported -Name $nic.Name -DisplayName 'Energy Efficient Ethernet' -Value 'Disabled' -DryRun:$DryRun

    if ($Preset -ge 2) {
      Set-UjNicAdvancedPropertyIfSupported -Name $nic.Name -DisplayName 'Interrupt Moderation' -Value 'Disabled' -DryRun:$DryRun

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

      # P1-4 Fix: Use RegistryKeyword for ITR lookup (locale-independent)
      $itr = Get-NetAdapterAdvancedProperty -Name $nic.Name -RegistryKeyword '*InterruptModerationRate' -ErrorAction SilentlyContinue
      if ($itr) {
        Set-UjNicAdvancedPropertyIfSupported -Name $nic.Name -DisplayName 'ITR' -Value '0' -DryRun:$DryRun
      }

      Set-UjNicAdvancedPropertyIfSupported -Name $nic.Name -DisplayName 'Receive Buffers' -Value '256' -DryRun:$DryRun
      Set-UjNicAdvancedPropertyIfSupported -Name $nic.Name -DisplayName 'Transmit Buffers' -Value '256' -DryRun:$DryRun
    }
  }
}

