<#
Title: UDP Jitter Optimization (Windows 10/11) – Safe Defaults with Tiered Risk + Full Failsafe
Author: Sebastian J. Spicker
License: MIT

Presets (when -Action Apply):
  1 = Conservative (low risk): Protect MMCSS Audio, enable local QoS ("Do not use NLA"), add outbound DSCP EF (46) port policies, disable EEE if supported, take full backups. [MS Docs + vendor refs]
  2 = Medium: + reduce/disable Interrupt Moderation, disable Flow Control/Green/Power-Saving/Jumbo where supported, set AFD FastSendDatagramThreshold=1500 (reboot recommended). 
  3 = Higher risk: + disable RSC, disable LSO/Checksum Offloads, disable ARP/NS offload & WoL, set ITR=0 if present, optionally set SystemResponsiveness=0 and NetworkThrottlingIndex=FFFFFFFF, optionally disable software URO via netsh.

Notes:
- CPU load may increase when disabling interrupt moderation, offloads, RSC or URO; validate with measurements. 
- DSCP marking is outbound and requires devices along the path to honor DSCP for end-to-end effect; locally it is the supported client-side mechanism. 
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
  [switch]$DryRun                                                        # show actions without applying
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Admin {
  $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
  ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) { throw "Please run as Administrator." }
}

function Ensure-Folder { param([string]$Path) if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path | Out-Null } }

function Reg-Export {
  param([string]$RegPath,[string]$OutFile)
  try { & reg.exe export $RegPath $OutFile /y | Out-Null } catch {}
}

function Reg-Import {
  param([string]$InFile)
  if (Test-Path $InFile) { try { & reg.exe import $InFile | Out-Null } catch { Write-Warning "Reg import failed: $InFile" } }
}

function Ensure-RegistryValue {
  param([string]$Key,[string]$Name,[ValidateSet('DWord','String')][string]$Type,$Value)
  if (-not (Test-Path $Key)) { New-Item -Path $Key -Force | Out-Null }
  if ($Type -eq 'DWord') {
    New-ItemProperty -Path $Key -Name $Name -PropertyType DWord -Value ([int]$Value) -Force | Out-Null
  } else {
    New-ItemProperty -Path $Key -Name $Name -PropertyType String -Value ([string]$Value) -Force | Out-Null
  }
}

function Backup-State {
  Write-Host "Backing up current state ..."
  Ensure-Folder -Path $BackupFolder

  # 1) MMCSS SystemProfile
  Reg-Export -RegPath "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -OutFile (Join-Path $BackupFolder "SystemProfile.reg")

  # 2) AFD Parameters
  Reg-Export -RegPath "HKLM\SYSTEM\CurrentControlSet\Services\AFD\Parameters" -OutFile (Join-Path $BackupFolder "AFD_Parameters.reg")

  # 3) QoS policies (Persistent/Active)
  try { Get-NetQosPolicy -PolicyStore PersistentStore | Export-CliXml (Join-Path $BackupFolder "qos_persistent.xml") } catch {}
  try { Get-NetQosPolicy -PolicyStore ActiveStore     | Export-CliXml (Join-Path $BackupFolder "qos_active.xml") } catch {}

  # 4) NIC advanced properties snapshot
  try {
    $rows = foreach ($n in (Get-NetAdapter -Physical | Where-Object Status -eq 'Up')) {
      Get-NetAdapterAdvancedProperty -Name $n.Name |
        Select-Object @{n='Adapter';e={$n.Name}}, DisplayName, RegistryKeyword, DisplayValue, RegistryValue
    }
    $rows | Export-Csv -NoTypeInformation -Path (Join-Path $BackupFolder "nic_advanced_backup.csv")
  } catch { Write-Warning "NIC advanced snapshot failed." }

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

  # 3) QoS policies restore (brutal: remove our known policies, then reimport persistent if present)
  foreach ($name in @("QoS_UDP_TS_*","QoS_UDP_CS2_*","QoS_APP_*")) {
    Get-NetQosPolicy -PolicyStore PersistentStore -Name $name -ErrorAction SilentlyContinue | ForEach-Object {
      Remove-NetQosPolicy -Name $_.Name -PolicyStore PersistentStore -Confirm:$false
    }
  }
  $px = Join-Path $BackupFolder "qos_persistent.xml"
  if (Test-Path $px) {
    try {
      $items = Import-CliXml $px
      foreach ($i in $items) {
        # Recreate basic policies (port- or app-based)
        if ($i.IPProtocol -and $i.IPProtocol -eq 'UDP' -and $i.RemotePortRangeStart -and $i.RemotePortRangeEnd) {
          New-NetQosPolicy -Name $i.Name -PolicyStore PersistentStore -IPProtocolMatchCondition UDP -RemotePortStart $i.RemotePortRangeStart -RemotePortEnd $i.RemotePortRangeEnd -DSCPAction $i.DSCPValue -NetworkProfile All | Out-Null
        } elseif ($i.AppPathName) {
          New-NetQosPolicy -Name $i.Name -PolicyStore PersistentStore -AppPathNameMatchCondition $i.AppPathName -DSCPAction $i.DSCPValue -NetworkProfile All | Out-Null
        }
      }
    } catch { Write-Warning "QoS restore skipped (parse failed)." }
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
    } catch { Write-Warning "NIC advanced restore error." }
  }

  # 5) RSC restore
  $rscf = Join-Path $BackupFolder "rsc_backup.csv"
  if (Test-Path $rscf) {
    try {
      $rows = Import-Csv $rscf
      foreach ($r in $rows) {
        if ($r.IPv4Enabled -eq 'True' -or $r.IPv6Enabled -eq 'True') {
          # Can't selectively re-enable per protocol in all driver stacks; try enabling RSC globally on that adapter by re-enabling feature via Set-NetAdapterRsc when available
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
  Ensure-RegistryValue -Key $mm    -Name "SystemResponsiveness" -Type DWord -Value 20
  Ensure-RegistryValue -Key $audio -Name "Priority"             -Type DWord -Value 6
  Ensure-RegistryValue -Key $audio -Name "Background Only"      -Type DWord -Value 0
  Ensure-RegistryValue -Key $audio -Name "Clock Rate"           -Type DWord -Value 10000
  Ensure-RegistryValue -Key $audio -Name "Scheduling Category"  -Type String -Value "High"
  Ensure-RegistryValue -Key $audio -Name "SFIO Priority"        -Type String -Value "High"
  # no-space variants for compatibility
  Ensure-RegistryValue -Key $audio -Name "BackgroundOnly"     -Type DWord -Value 0
  Ensure-RegistryValue -Key $audio -Name "SchedulingCategory" -Type String -Value "High"
  Ensure-RegistryValue -Key $audio -Name "SFIOPriority"       -Type String -Value "High"
}

function Ensure-AudioServices {
  foreach ($svc in @("AudioEndpointBuilder","Audiosrv","MMCSS")) {
    try { Set-Service -Name $svc -StartupType Automatic } catch {}
    try { if ((Get-Service -Name $svc).Status -ne 'Running') { Start-Service -Name $svc } } catch {}
  }
}

function Enable-LocalQoS {
  # Let local DSCP policies apply even when not using NLA (non-domain scenarios).
  $qos = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\QoS"
  New-Item -Path $qos -Force | Out-Null
  Ensure-RegistryValue -Key $qos -Name "Do not use NLA" -Type String -Value "1"
}

function New-DSCPPolicyByPort {
  param([string]$Name,[uint16]$PortStart,[uint16]$PortEnd,[sbyte]$DSCP=46)
  if ($DryRun) { Write-Host "[DryRun] QoS $Name UDP $PortStart-$PortEnd DSCP=$DSCP (PersistentStore)" ; return }
  if (Get-NetQosPolicy -Name $Name -PolicyStore PersistentStore -ErrorAction SilentlyContinue) {
    Remove-NetQosPolicy -Name $Name -PolicyStore PersistentStore -Confirm:$false
  }
  New-NetQosPolicy -Name $Name -PolicyStore PersistentStore -IPProtocolMatchCondition UDP -RemotePortStart $PortStart -RemotePortEnd $PortEnd -DSCPAction $DSCP -NetworkProfile All | Out-Null
}

function New-DSCPPolicyByApp {
  param([string]$Name,[string]$ExePath,[sbyte]$DSCP=46)
  if ($DryRun) { Write-Host "[DryRun] QoS $Name App=$ExePath DSCP=$DSCP (PersistentStore)" ; return }
  if (Get-NetQosPolicy -Name $Name -PolicyStore PersistentStore -ErrorAction SilentlyContinue) {
    Remove-NetQosPolicy -Name $Name -PolicyStore PersistentStore -Confirm:$false
  }
  New-NetQosPolicy -Name $Name -PolicyStore PersistentStore -AppPathNameMatchCondition $ExePath -DSCPAction $DSCP -NetworkProfile All | Out-Null
}

function Set-NIC-IfSupported { param([string]$Name,[string]$DisplayName,[string]$Value)
  $prop = Get-NetAdapterAdvancedProperty -Name $Name -ErrorAction SilentlyContinue | Where-Object DisplayName -eq $DisplayName
  if ($prop) {
    if ($DryRun) { Write-Host "[DryRun] $Name: $DisplayName => $Value" }
    else {
      try { Set-NetAdapterAdvancedProperty -Name $Name -DisplayName $DisplayName -DisplayValue $Value -NoRestart -ErrorAction Stop | Out-Null }
      catch { Write-Warning "$Name: failed to set $DisplayName" }
    }
  }
}

function Apply-NIC {
  $adapters = Get-NetAdapter -Physical | Where-Object {$_.Status -eq 'Up'}
  foreach ($nic in $adapters) {
    Write-Host ("NIC: {0}" -f $nic.Name)

    # Preset 1: disable EEE if supported (reduces latency spikes)
    Set-NIC-IfSupported -Name $nic.Name -DisplayName "Energy Efficient Ethernet" -Value "Disabled"

    if ($Preset -ge 2) {
      # Lower/disable interrupt moderation (less coalescing latency, more CPU)
      foreach ($v in @("Disabled","Off","Low")) { Set-NIC-IfSupported -Name $nic.Name -DisplayName "Interrupt Moderation" -Value $v }
      # Flow Control off can reduce pause-induced latency; risk: drops under congestion
      Set-NIC-IfSupported -Name $nic.Name -DisplayName "Flow Control" -Value "Disabled"
      # Disable common energy features that may add latency jitter
      Set-NIC-IfSupported -Name $nic.Name -DisplayName "Green Ethernet" -Value "Disabled"
      Set-NIC-IfSupported -Name $nic.Name -DisplayName "Power Saving Mode" -Value "Disabled"
      # Ensure Jumbo disabled for uniform client MTU
      Set-NIC-IfSupported -Name $nic.Name -DisplayName "Jumbo Packet" -Value "Disabled"
    }

    if ($Preset -ge 3) {
      # Disable RSC (TCP coalescing) – higher CPU possible
      if ($DryRun) { Write-Host "[DryRun] Disable-NetAdapterRsc $($nic.Name)" } else { try { Disable-NetAdapterRsc -Name $nic.Name -Confirm:$false -ErrorAction Stop | Out-Null } catch { Write-Warning "RSC disable failed on $($nic.Name)" } }
      # Disable offloads (higher CPU, sometimes smoother latency if drivers misbehave)
      foreach ($dn in @("Large Send Offload v2 (IPv4)","Large Send Offload v2 (IPv6)","UDP Checksum Offload (IPv4)","UDP Checksum Offload (IPv6)","TCP Checksum Offload (IPv4)","TCP Checksum Offload (IPv6)")) {
        Set-NIC-IfSupported -Name $nic.Name -DisplayName $dn -Value "Disabled"
      }
      # Ancillary low-level toggles
      Set-NIC-IfSupported -Name $nic.Name -DisplayName "ARP Offload" -Value "Disabled"
      Set-NIC-IfSupported -Name $nic.Name -DisplayName "NS Offload"  -Value "Disabled"
      Set-NIC-IfSupported -Name $nic.Name -DisplayName "Wake on Magic Packet"      -Value "Disabled"
      Set-NIC-IfSupported -Name $nic.Name -DisplayName "Wake on pattern match"     -Value "Disabled"
      Set-NIC-IfSupported -Name $nic.Name -DisplayName "WOL & Shutdown Link Speed" -Value "Disabled"
      # ITR = 0 if exposed (lowest latency, max CPU)
      $itr = Get-NetAdapterAdvancedProperty -Name $nic.Name -ErrorAction SilentlyContinue | Where-Object DisplayName -eq "ITR"
      if ($itr) { Set-NIC-IfSupported -Name $nic.Name -DisplayName "ITR" -Value "0" }
      # Buffers (driver-specific trade-offs)
      Set-NIC-IfSupported -Name $nic.Name -DisplayName "Receive Buffers"  -Value "256"
      Set-NIC-IfSupported -Name $nic.Name -DisplayName "Transmit Buffers" -Value "256"
    }
  }
}

function Apply-AFD {
  if ($Preset -ge 2) {
    $afd = "HKLM:\SYSTEM\CurrentControlSet\Services\AFD\Parameters"
    if ($DryRun) { Write-Host "[DryRun] AFD FastSendDatagramThreshold=$AFDThreshold" }
    else {
      Ensure-RegistryValue -Key $afd -Name "FastSendDatagramThreshold" -Type DWord -Value $AFDThreshold
      Write-Host "AFD FastSendDatagramThreshold set to $AFDThreshold (reboot recommended)."
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
    if ($DryRun) { Write-Host "[DryRun] $cmd" } else { try { & cmd.exe /c $cmd | Out-Null } catch { Write-Warning "Setting URO via netsh failed (may not exist on all builds)." } }
  }
}

function Set-PowerPlan {
  if ($PowerPlan -eq 'None') { return }
  $guidHigh = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"   # High Performance
  $guidUlt  = "e9a42b02-d5df-448d-aa00-03f14749eb61"   # Ultimate Performance
  $guid = $(if ($PowerPlan -eq 'HighPerformance') { $guidHigh } else { $guidUlt })
  if ($DryRun) { Write-Host "[DryRun] powercfg /S $guid (duplicate Ultimate if missing)" }
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
  Write-Host "`nQoS Policies:"; try { Get-NetQosPolicy | Format-Table -AutoSize } catch {}
  Write-Host "`nNIC Key Properties (subset):"
  foreach ($nic in (Get-NetAdapter -Physical | Where-Object {$_.Status -eq 'Up'})) {
    Get-NetAdapterAdvancedProperty -Name $nic.Name | Where-Object {$_.DisplayName -match "Energy|Interrupt|Flow|Offload|Large Send|Jumbo|Wake|Power|Green|NS|ARP|ITR|Buffer"} | Sort-Object DisplayName | Format-Table -AutoSize
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

# Action = Apply
Write-Host "UDP Jitter Optimization – Preset $Preset (Action=Apply)"

# Full backup first (failsafe)
Backup-State

# Audio safety first
Protect-MMCSS-Audio
Ensure-AudioServices

# Enable local QoS usage outside NLA contexts
Enable-LocalQoS

# Outbound DSCP EF policies (TeamSpeak + CS2)
New-DSCPPolicyByPort -Name "QoS_UDP_TS_$TeamSpeakPort" -PortStart $TeamSpeakPort -PortEnd $TeamSpeakPort -DSCP 46
New-DSCPPolicyByPort -Name "QoS_UDP_CS2_${CS2PortStart}_${CS2PortEnd}" -PortStart $CS2PortStart -PortEnd $CS2PortEnd -DSCP 46

# Optional per-app DSCP policies
if ($IncludeAppPolicies -and $AppPaths.Count -gt 0) {
  $i = 0; foreach ($p in $AppPaths) { $i++; New-DSCPPolicyByApp -Name ("QoS_APP_{0}" -f $i) -ExePath $p -DSCP 46 }
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
Write-Host "`nNote: Reboot recommended for AFD/MMCSS registry changes to fully apply."
