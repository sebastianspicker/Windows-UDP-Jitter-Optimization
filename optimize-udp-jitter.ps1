<#
Title: UDP Jitter Optimization (Windows 10/11) - Safe Defaults with Tiered Risk + Full Failsafe
Author: Sebastian J. Spicker
License: MIT

Presets (when -Action Apply):
  1 = Conservative (low risk): Protect MMCSS Audio, enable local QoS ("Do not use NLA"),
      add outbound DSCP EF (46) port policies, disable EEE if supported, take full backups.
  2 = Medium: + reduce/disable Interrupt Moderation, disable Flow Control/Green/Power-Saving/Jumbo where supported,
      set AFD FastSendDatagramThreshold=1500 (reboot recommended).
  3 = Higher risk: + disable RSC, disable LSO/Checksum Offloads, disable ARP/NS offload & WoL,
      set ITR=0 if present, optionally set SystemResponsiveness=0 and NetworkThrottlingIndex=FFFFFFFF,
      optionally disable software URO via netsh.

Notes:
- CPU load may increase when disabling interrupt moderation, offloads, RSC or URO; validate with measurements.
- DSCP marking is outbound and requires devices along the path to honor DSCP for end-to-end effect.
#>

[CmdletBinding()]
param(
  [ValidateSet('Apply','Backup','Restore')] [string]$Action = 'Apply',  # Workflow mode
  [ValidateSet(1,2,3)] [int]$Preset = 1,                                # 1=conservative, 2=medium, 3=higher risk
  [int]$TeamSpeakPort = 9987,                                           # TeamSpeak 3 default UDP
  [int]$CS2PortStart = 27015,                                           # CS2 common server range
  [int]$CS2PortEnd   = 27036,                                           # CS2 common server range
  [switch]$IncludeAppPolicies,                                          # optional: add per-app DSCP policies
  [string[]]$AppPaths = @(),                                            # EXE paths for -AppPathNameMatchCondition
  [int]$AFDThreshold = 1500,                                            # conservative FastSendDatagramThreshold (bytes)
  [ValidateSet('None','HighPerformance','Ultimate')] [string]$PowerPlan = 'None',  # optional
  [switch]$DisableGameDVR,                                              # optional convenience
  [switch]$DisableURO,                                                  # optional software URO off (netsh)
  [string]$BackupFolder = "$env:ProgramData\UDPTune",                   # backup directory
  [switch]$DryRun                                                       # show actions without applying
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------- Helpers ----------------
function Assert-Admin {
  $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
  ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) { throw "Please run as Administrator." }
}

function Ensure-Folder {
  param([string]$Path)
  if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path | Out-Null }
}

function Reg-Export {
  param([string]$RegPath,[string]$OutFile)
  try { & reg.exe export $RegPath $OutFile /y | Out-Null } catch {}
}

function Reg-Import {
  param([string]$InFile)
  if (Test-Path $InFile) {
    try { & reg.exe import $InFile | Out-Null }
    catch { Write-Warning "Reg import failed: $InFile" }
  }
}

function Ensure-RegistryValue {
  param(
    [string]$Key,
    [string]$Name,
    [ValidateSet('DWord','String')][string]$Type,
    $Value
  )
  if (-not (Test-Path $Key)) { New-Item -Path $Key -Force | Out-Null }

  if ($Type -eq 'DWord') {
    New-ItemProperty -Path $Key -Name $Name -PropertyType DWord -Value ([int]$Value) -Force | Out-Null
  } else {
    New-ItemProperty -Path $Key -Name $Name -PropertyType String -Value ([string]$Value) -Force | Out-Null
  }
}

function Get-OurQosPolicies {
  # Only manage policies created by this script (prefix QoS_)
  try {
    Get-NetQosPolicy -ErrorAction Stop | Where-Object { $_.Name -like 'QoS_*' }
  } catch {
    @()
  }
}

function Remove-OurQosPolicies {
  $items = Get-OurQosPolicies
  foreach ($p in $items) {
    try { Remove-NetQosPolicy -Name $p.Name -Confirm:$false -ErrorAction Stop | Out-Null } catch {}
  }
}

function Backup-State {
  Write-Host "Backing up current state ..."
  Ensure-Folder -Path $BackupFolder

  # 1) MMCSS SystemProfile
  Reg-Export -RegPath "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" `
            -OutFile (Join-Path $BackupFolder "SystemProfile.reg")

  # 2) AFD Parameters
  Reg-Export -RegPath "HKLM\SYSTEM\CurrentControlSet\Services\AFD\Parameters" `
            -OutFile (Join-Path $BackupFolder "AFD_Parameters.reg")

  # 3) QoS policies (ONLY our policies)
  try {
    $q = Get-OurQosPolicies
    $q | Export-CliXml (Join-Path $BackupFolder "qos_ours.xml")
  } catch {
    Write-Warning "QoS backup skipped (Get-NetQosPolicy failed)."
  }

  # 4) NIC advanced properties snapshot
  try {
    $rows = foreach ($n in (Get-NetAdapter -Physical | Where-Object Status -eq 'Up')) {
      Get-NetAdapterAdvancedProperty -Name $n.Name |
        Select-Object @{n='Adapter';e={$n.Name}}, DisplayName, RegistryKeyword, DisplayValue, RegistryValue
    }
    $rows | Export-Csv -NoTypeInformation -Path (Join-Path $BackupFolder "nic_advanced_backup.csv")
  } catch {
    Write-Warning "NIC advanced snapshot failed."
  }

  # 5) RSC status snapshot
  try {
    Get-NetAdapterRsc | Select-Object Name, IPv4Enabled, IPv6Enabled |
      Export-Csv -NoTypeInformation -Path (Join-Path $BackupFolder "rsc_backup.csv")
  } catch {}

  # 6) Power plan active scheme
  try {
    $cur = (powercfg /GetActiveScheme) -join "`n"
    $cur | Out-File -FilePath (Join-Path $BackupFolder "powerplan.txt") -Encoding utf8
  } catch {}
}

function Restore-State {
  Write-Host "Restoring previous state ..."

  # 1) MMCSS SystemProfile
  Reg-Import -InFile (Join-Path $BackupFolder "SystemProfile.reg")

  # 2) AFD Parameters
  Reg-Import -InFile (Join-Path $BackupFolder "AFD_Parameters.reg")

  # 3) QoS policies restore (ONLY our policies)
  Remove-OurQosPolicies

  $qx = Join-Path $BackupFolder "qos_ours.xml"
  if (Test-Path $qx) {
    try {
      $items = Import-CliXml $qx
      foreach ($i in $items) {
        # Recreate ONLY two supported shapes used by this script:
        #   a) Port-based: IPPortMatchCondition + UDP
        #   b) App-based : AppPathNameMatchCondition
        $name = $i.Name

        # DSCP action: prefer DSCPAction, fall back to DSCPValue
        $dscp = $null
        if ($i.PSObject.Properties.Name -contains 'DSCPAction' -and $i.DSCPAction -ne $null -and [int]$i.DSCPAction -ge 0) { $dscp = [int]$i.DSCPAction }
        elseif ($i.PSObject.Properties.Name -contains 'DSCPValue' -and $i.DSCPValue -ne $null -and [int]$i.DSCPValue -ge 0) { $dscp = [int]$i.DSCPValue }
        else { $dscp = 46 }

        $proto = 'UDP'
        if ($i.PSObject.Properties.Name -contains 'IPProtocolMatchCondition' -and $i.IPProtocolMatchCondition) {
          $proto = [string]$i.IPProtocolMatchCondition
        }

        if ($i.PSObject.Properties.Name -contains 'IPPortMatchCondition' -and [int]$i.IPPortMatchCondition -gt 0) {
          # Port-based
          New-NetQosPolicy -Name $name -IPPortMatchCondition ([uint16]$i.IPPortMatchCondition) -IPProtocolMatchCondition $proto -DSCPAction ([sbyte]$dscp) -NetworkProfile All | Out-Null
          continue
        }

        if ($i.PSObject.Properties.Name -contains 'AppPathNameMatchCondition' -and $i.AppPathNameMatchCondition) {
          # App-based
          New-NetQosPolicy -Name $name -AppPathNameMatchCondition ([string]$i.AppPathNameMatchCondition) -DSCPAction ([sbyte]$dscp) -NetworkProfile All | Out-Null
          continue
        }
      }
    } catch {
      Write-Warning "QoS restore skipped (import/parse failed)."
    }
  }

  # 4) NIC advanced restore (best-effort per DisplayName/RegistryKeyword)
  $csv = Join-Path $BackupFolder "nic_advanced_backup.csv"
  if (Test-Path $csv) {
    try {
      $data = Import-Csv $csv
      $adapters = $data | Select-Object -Expand Adapter -Unique
      foreach ($a in $adapters) {
        $props = $data | Where-Object Adapter -eq $a
        foreach ($p in $props) {
          try {
            if ($p.DisplayName -and $p.DisplayValue) {
              Set-NetAdapterAdvancedProperty -Name $a -DisplayName $p.DisplayName -DisplayValue $p.DisplayValue -NoRestart -ErrorAction Stop | Out-Null
            } elseif ($p.RegistryKeyword -and $p.RegistryValue) {
              Set-NetAdapterAdvancedProperty -Name $a -RegistryKeyword $p.RegistryKeyword -RegistryValue $p.RegistryValue -NoRestart -ErrorAction Stop | Out-Null
            }
          } catch {}
        }
      }
    } catch {
      Write-Warning "NIC advanced restore error."
    }
  }

  # 5) RSC restore
  $rscf = Join-Path $BackupFolder "rsc_backup.csv"
  if (Test-Path $rscf) {
    try {
      $rows = Import-Csv $rscf
      foreach ($r in $rows) {
        if ($r.IPv4Enabled -eq 'True' -or $r.IPv6Enabled -eq 'True') {
          try { Enable-NetAdapterRsc -Name $r.Name -ErrorAction SilentlyContinue | Out-Null } catch {}
        } else {
          try { Disable-NetAdapterRsc -Name $r.Name -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch {}
        }
      }
    } catch {}
  }

  # 6) Power plan restore (best-effort: parse GUID from saved line)
  $pp = Join-Path $BackupFolder "powerplan.txt"
  if (Test-Path $pp) {
    $text = Get-Content $pp -Raw
    if ($text -match '{[0-9a-fA-F-]+}') {
      $guid = $Matches[0]
      try { & powercfg /S $guid | Out-Null } catch {}
    }
  }

  Write-Host "Restore complete. A reboot may be required for registry-based settings."
}

function Protect-MMCSS-Audio {
  # Ensure MMCSS Audio keys exist with stable defaults to prevent silent audio failures.
  $mm = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
  $tasks = "$mm\Tasks"
  $audio = "$tasks\Audio"

  if (-not (Test-Path $tasks)) { New-Item -Path $tasks -Force | Out-Null }
  if (-not (Test-Path $audio)) { New-Item -Path $audio -Force | Out-Null }

  Ensure-RegistryValue -Key $mm    -Name "SystemResponsiveness" -Type DWord  -Value 20
  Ensure-RegistryValue -Key $audio -Name "Priority"            -Type DWord  -Value 6
  Ensure-RegistryValue -Key $audio -Name "Background Only"     -Type DWord  -Value 0
  Ensure-RegistryValue -Key $audio -Name "Clock Rate"          -Type DWord  -Value 10000
  Ensure-RegistryValue -Key $audio -Name "Scheduling Category" -Type String -Value "High"
  Ensure-RegistryValue -Key $audio -Name "SFIO Priority"       -Type String -Value "High"

  # no-space variants for compatibility
  Ensure-RegistryValue -Key $audio -Name "BackgroundOnly"      -Type DWord  -Value 0
  Ensure-RegistryValue -Key $audio -Name "SchedulingCategory"  -Type String -Value "High"
  Ensure-RegistryValue -Key $audio -Name "SFIOPriority"        -Type String -Value "High"
}

function Ensure-AudioServices {
  foreach ($svc in @("AudioEndpointBuilder","Audiosrv","MMCSS")) {
    try { Set-Service -Name $svc -StartupType Automatic } catch {}
    try {
      if ((Get-Service -Name $svc).Status -ne 'Running') { Start-Service -Name $svc }
    } catch {}
  }
}

function Enable-LocalQoS {
  # Let local DSCP policies apply even when not using NLA (non-domain scenarios).
  $qos = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\QoS"
  New-Item -Path $qos -Force | Out-Null
  Ensure-RegistryValue -Key $qos -Name "Do not use NLA" -Type String -Value "1"
}

function New-DSCPPolicyByPort {
  param(
    [string]$Name,
    [uint16]$PortStart,
    [uint16]$PortEnd,
    [sbyte]$DSCP = 46
  )

  if ($DryRun) {
    Write-Host ("[DryRun] QoS {0} UDP {1}-{2} DSCP={3} (local store)" -f $Name, $PortStart, $PortEnd, $DSCP)
    return
  }

  # Remove existing policies with same prefix (QoS_* only), then recreate
  try {
    $existing = Get-OurQosPolicies | Where-Object { $_.Name -like ($Name + '*') }
    foreach ($e in $existing) {
      try { Remove-NetQosPolicy -Name $e.Name -Confirm:$false | Out-Null } catch {}
    }
  } catch {}

  for ($p = [int]$PortStart; $p -le [int]$PortEnd; $p++) {
    $policyName = if ($PortStart -eq $PortEnd) { $Name } else { "{0}_{1}" -f $Name, $p }

    # IPPortMatchCondition matches either source or destination port; suitable to apply same policy on client/server.
    New-NetQosPolicy -Name $policyName -IPPortMatchCondition ([uint16]$p) -IPProtocolMatchCondition UDP -DSCPAction $DSCP -NetworkProfile All | Out-Null
  }
}

function New-DSCPPolicyByApp {
  param([string]$Name,[string]$ExePath,[sbyte]$DSCP=46)

  if ($DryRun) {
    Write-Host ("[DryRun] QoS {0} App={1} DSCP={2} (local store)" -f $Name, $ExePath, $DSCP)
    return
  }

  try {
    $existing = Get-OurQosPolicies | Where-Object { $_.Name -eq $Name }
    foreach ($e in $existing) {
      try { Remove-NetQosPolicy -Name $e.Name -Confirm:$false | Out-Null } catch {}
    }
  } catch {}

  New-NetQosPolicy -Name $Name -AppPathNameMatchCondition $ExePath -DSCPAction $DSCP -NetworkProfile All | Out-Null
}

function Set-NIC-IfSupported {
  param([string]$Name,[string]$DisplayName,[string]$Value)

  $prop = Get-NetAdapterAdvancedProperty -Name $Name -ErrorAction SilentlyContinue | Where-Object DisplayName -eq $DisplayName
  if ($prop) {
    if ($DryRun) { Write-Host ("[DryRun] {0}: {1} => {2}" -f $Name, $DisplayName, $Value) }
    else {
      try { Set-NetAdapterAdvancedProperty -Name $Name -DisplayName $DisplayName -DisplayValue $Value -NoRestart -ErrorAction Stop | Out-Null }
      catch { Write-Warning ("{0}: failed to set {1}" -f $Name, $DisplayName) }
    }
  }
}

function Apply-NIC {
  $adapters = Get-NetAdapter -Physical | Where-Object { $_.Status -eq 'Up' }
  foreach ($nic in $adapters) {
    Write-Host ("NIC: {0}" -f $nic.Name)

    # Preset 1: disable EEE if supported
    Set-NIC-IfSupported -Name $nic.Name -DisplayName "Energy Efficient Ethernet" -Value "Disabled"

    if ($Preset -ge 2) {
      foreach ($v in @("Disabled","Off","Low")) { Set-NIC-IfSupported -Name $nic.Name -DisplayName "Interrupt Moderation" -Value $v }
      Set-NIC-IfSupported -Name $nic.Name -DisplayName "Flow Control" -Value "Disabled"
      Set-NIC-IfSupported -Name $nic.Name -DisplayName "Green Ethernet" -Value "Disabled"
      Set-NIC-IfSupported -Name $nic.Name -DisplayName "Power Saving Mode" -Value "Disabled"
      Set-NIC-IfSupported -Name $nic.Name -DisplayName "Jumbo Packet" -Value "Disabled"
    }

    if ($Preset -ge 3) {
      if ($DryRun) { Write-Host ("[DryRun] Disable-NetAdapterRsc {0}" -f $nic.Name) }
      else {
        try { Disable-NetAdapterRsc -Name $nic.Name -Confirm:$false -ErrorAction Stop | Out-Null }
        catch { Write-Warning ("RSC disable failed on {0}" -f $nic.Name) }
      }

      foreach ($dn in @(
        "Large Send Offload v2 (IPv4)","Large Send Offload v2 (IPv6)",
        "UDP Checksum Offload (IPv4)","UDP Checksum Offload (IPv6)",
        "TCP Checksum Offload (IPv4)","TCP Checksum Offload (IPv6)"
      )) {
        Set-NIC-IfSupported -Name $nic.Name -DisplayName $dn -Value "Disabled"
      }

      Set-NIC-IfSupported -Name $nic.Name -DisplayName "ARP Offload" -Value "Disabled"
      Set-NIC-IfSupported -Name $nic.Name -DisplayName "NS Offload"  -Value "Disabled"
      Set-NIC-IfSupported -Name $nic.Name -DisplayName "Wake on Magic Packet"      -Value "Disabled"
      Set-NIC-IfSupported -Name $nic.Name -DisplayName "Wake on pattern match"     -Value "Disabled"
      Set-NIC-IfSupported -Name $nic.Name -DisplayName "WOL & Shutdown Link Speed" -Value "Disabled"

      $itr = Get-NetAdapterAdvancedProperty -Name $nic.Name -ErrorAction SilentlyContinue | Where-Object DisplayName -eq "ITR"
      if ($itr) { Set-NIC-IfSupported -Name $nic.Name -DisplayName "ITR" -Value "0" }

      Set-NIC-IfSupported -Name $nic.Name -DisplayName "Receive Buffers"  -Value "256"
      Set-NIC-IfSupported -Name $nic.Name -DisplayName "Transmit Buffers" -Value "256"
    }
  }
}

function Apply-AFD {
  if ($Preset -ge 2) {
    $afd = "HKLM:\SYSTEM\CurrentControlSet\Services\AFD\Parameters"
    if ($DryRun) { Write-Host ("[DryRun] AFD FastSendDatagramThreshold={0}" -f $AFDThreshold) }
    else {
      Ensure-RegistryValue -Key $afd -Name "FastSendDatagramThreshold" -Type DWord -Value $AFDThreshold
      Write-Host ("AFD FastSendDatagramThreshold set to {0} (reboot recommended)." -f $AFDThreshold)
    }
  }
}

function Apply-UndocumentedNetworkMMCSS {
  if ($Preset -ge 3) {
    $mm = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
    if ($DryRun) { Write-Host "[DryRun] SystemResponsiveness=0; NetworkThrottlingIndex=FFFFFFFF" }
    else {
      Ensure-RegistryValue -Key $mm -Name "SystemResponsiveness"    -Type DWord -Value 0
      Ensure-RegistryValue -Key $mm -Name "NetworkThrottlingIndex" -Type DWord -Value 0xFFFFFFFF
    }
  }
}

function Manage-URO {
  if ($DisableURO -or $Preset -ge 3) {
    $cmd = "netsh int udp set global uro=disabled"
    if ($DryRun) { Write-Host ("[DryRun] {0}" -f $cmd) }
    else {
      try { & cmd.exe /c $cmd | Out-Null }
      catch { Write-Warning "Setting URO via netsh failed (may not exist on all builds)." }
    }
  }
}

function Set-PowerPlan {
  if ($PowerPlan -eq 'None') { return }

  $guidHigh = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"   # High Performance
  $guidUlt  = "e9a42b02-d5df-448d-aa00-03f14749eb61"   # Ultimate Performance
  $guid = $(if ($PowerPlan -eq 'HighPerformance') { $guidHigh } else { $guidUlt })

  if ($DryRun) { Write-Host ("[DryRun] powercfg /S {0}" -f $guid) }
  else {
    if ($PowerPlan -eq 'Ultimate') { & powercfg /duplicatescheme $guidUlt | Out-Null }
    & powercfg /S $guid | Out-Null
  }
}

function Disable-GameDVR {
  if ($DisableGameDVR) {
    $dvr = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR"
    if (Test-Path $dvr) {
      New-ItemProperty -Path $dvr -Name "AppCaptureEnabled"        -PropertyType DWord -Value 0 -Force | Out-Null
      New-ItemProperty -Path $dvr -Name "HistoricalCaptureEnabled" -PropertyType DWord -Value 0 -Force | Out-Null
    }
  }
}

function Show-Summary {
  Write-Host "`nQoS Policies (QoS_*):"
  try { Get-OurQosPolicies | Sort-Object Name | Format-Table -AutoSize } catch {}

  Write-Host "`nNIC Key Properties (subset):"
  foreach ($nic in (Get-NetAdapter -Physical | Where-Object { $_.Status -eq 'Up' })) {
    Get-NetAdapterAdvancedProperty -Name $nic.Name |
      Where-Object { $_.DisplayName -match "Energy|Interrupt|Flow|Offload|Large Send|Jumbo|Wake|Power|Green|NS|ARP|ITR|Buffer" } |
      Sort-Object DisplayName |
      Format-Table -AutoSize
  }
}

# ----------------- Main -----------------
Assert-Admin
Ensure-Folder -Path $BackupFolder

if ($Action -eq 'Backup') {
  Backup-State
  Write-Host "Backup complete."
  return
}

if ($Action -eq 'Restore') {
  Restore-State
  Write-Host "Restore complete. A reboot may be required."
  return
}

Write-Host ('UDP Jitter Optimization - Preset {0} (Action={1})' -f $Preset, $Action)

# Full backup first (failsafe)
Backup-State

# Audio safety first
Protect-MMCSS-Audio
Ensure-AudioServices

# Enable local QoS usage outside NLA contexts
Enable-LocalQoS

# DSCP EF policies (TeamSpeak + CS2)
New-DSCPPolicyByPort -Name ("QoS_UDP_TS_{0}" -f $TeamSpeakPort) -PortStart $TeamSpeakPort -PortEnd $TeamSpeakPort -DSCP 46
New-DSCPPolicyByPort -Name ("QoS_UDP_CS2_{0}_{1}" -f $CS2PortStart, $CS2PortEnd) -PortStart $CS2PortStart -PortEnd $CS2PortEnd -DSCP 46

# Optional per-app DSCP policies
if ($IncludeAppPolicies -and $AppPaths.Count -gt 0) {
  $i = 0
  foreach ($p in $AppPaths) {
    $i++
    New-DSCPPolicyByApp -Name ('QoS_APP_{0}' -f $i) -ExePath $p -DSCP 46
  }
}

# NIC staged tuning
Apply-NIC

# AFD threshold (medium+)
Apply-AFD

# Higher-risk MMCSS network tweaks (only preset 3)
Apply-UndocumentedNetworkMMCSS

# URO (software) management
Manage-URO

# Optional power plan & Game DVR
Set-PowerPlan
Disable-GameDVR

Show-Summary
Write-Host ''
Write-Host 'Note: Reboot recommended for AFD/MMCSS registry changes to fully apply.'
