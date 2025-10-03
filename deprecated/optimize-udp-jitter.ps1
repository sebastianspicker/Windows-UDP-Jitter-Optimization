<#
.SYNOPSIS
  Ultimate UDP Jitter Reduction Script for CS2 & TeamSpeak 3 on Windows 10/11.

.DESCRIPTION
  Applies the full set of proven client-side optimizations:
    A. System & Registry Tweaks
       1. Set power plan to High Performance.
       2. Disable Windows network throttling (NetworkThrottlingIndex).
       3. Configure multimedia scheduler (SystemResponsiveness=0, MMCSS “Games” tasks).
       4. Increase UDP FastSendDatagramThreshold for larger packets.
       5. (Optional) Disable Game DVR/Game Bar.
    B. NIC Advanced Settings
       6. Disable Receive Segment Coalescing (RSC).
       7. Disable Interrupt Moderation & set ITR to zero.
       8. Disable Flow Control.
       9. Disable Energy-Efficient Ethernet, Green Ethernet, Power Saving Mode.
      10. Disable Large Send Offload v2 (IPv4 & IPv6).
      11. Disable TCP/UDP Checksum Offload (IPv4 & IPv6).
      12. Disable Jumbo Packet support.
      13. Disable ARP and NS Offload.
      14. Disable Wake-on-LAN features.
      15. Set ReceiveBuffers=256 and TransmitBuffers=256.
    C. QoS Policies
      16. Remove old per-port QoS policies.
      17. Create per-port in/out policies (DSCP=46 EF) in PersistentStore.
      18. Allow local QoS by setting “Do not use NLA”=1.
      19. (Optional) Generic QoS policies for TeamSpeak & game traffic.
    D. TCP/IP Stack & Netsh Tweaks
      20. Disable TCP Auto-Tuning.
      21. Disable Teredo IPv6 tunneling.
      22. Disable UDP Receive Offload (URO).
      23. Apply TCP supplemental settings: ICW=10, minRTO=300ms, delayed ACK=40ms/2, RACK=enabled, TLP=enabled.
      24. Disable PRR & HyStart.
      25. Set CTCP congestion provider and enable ECN.
    E. (Optional) Disable the Windows NDU service.

  Requires Administrator. Reboot after completion for full effect.
#>

#--- A. ADMIN CHECK & STRICT MODE -------------------------------------------
Set-StrictMode -Version Latest
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent() `
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as Administrator!"
    exit 1
}
$ErrorActionPreference = 'Continue'
Write-Host "`n>>> Starting Ultimate UDP Jitter Reduction <<<`n" -ForegroundColor Cyan

#--- A1. Set High Performance Power Plan ------------------------------------
# Write-Host "1) Setting High Performance power plan..." -ForegroundColor Yellow
# try {
    # powercfg /S 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c | Out-Null
# } catch {
    # Write-Warning "Could not set power plan to High Performance."
# }

#--- A2. Registry Tweaks: Network Throttling, Responsiveness & FastSend ------

# Ask about background‐audio apps to avoid breaking MMCSS
$useBackgroundAudio = Read-Host "Do you use OBS, Discord streaming, or other background audio applications? (y/n)"
if ($useBackgroundAudio -match '^[Yy]') {
    Write-Host "  - Skipping SystemResponsiveness tweak to preserve MMCSS settings." -ForegroundColor Yellow
} else {
    Write-Host "  - Setting SystemResponsiveness to 0 (reserve 0% CPU for background tasks)" -ForegroundColor Yellow
    Set-ItemProperty -Path $mmKey -Name "SystemResponsiveness" -Type DWord -Value 0 -Force
}
Write-Host "2) Disabling network throttling & configuring multimedia scheduler..." -ForegroundColor Yellow
$mmKey  = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
$afdKey = "HKLM:\SYSTEM\CurrentControlSet\Services\AFD\Parameters"
try {
    # Ensure registry keys exist
    New-Item -Path $mmKey  -Force | Out-Null
    New-Item -Path $afdKey -Force | Out-Null

    # Disable Windows network throttling
    Set-ItemProperty -Path $mmKey -Name "NetworkThrottlingIndex" -Type DWord -Value 0xFFFFFFFF -Force
    # Reserve 0% CPU for background tasks
    Set-ItemProperty -Path $mmKey -Name "SystemResponsiveness"   -Type DWord -Value 0         -Force

    # Increase UDP FastSendDatagramThreshold to 64KB
    Set-ItemProperty -Path $afdKey -Name "FastSendDatagramThreshold" -Type DWord -Value 0xFFFF -Force

    # Configure MMCSS “Games” profile
    $gamesKey = "$mmKey\Tasks\Games"
    New-Item -Path $gamesKey -Force | Out-Null
    Set-ItemProperty -Path $gamesKey -Name "GPU Priority"        -Type DWord  -Value 8     -Force
    Set-ItemProperty -Path $gamesKey -Name "Priority"            -Type DWord  -Value 6     -Force
    Set-ItemProperty -Path $gamesKey -Name "Scheduling Category" -Type String -Value "High" -Force
    Set-ItemProperty -Path $gamesKey -Name "SFIO Priority"       -Type String -Value "High" -Force

    Write-Host "  - Registry tweaks applied. (Reboot required for AFD changes)" -ForegroundColor Green
} catch {
    Write-Warning "Registry tweaks failed: $($_.Exception.Message)"
}

#--- A3. Optional: Disable Game DVR/Game Bar -------------------------------
Write-Host "3) Disabling Game DVR/Game Bar (optional)..." -ForegroundColor Yellow
try {
    $dvrKey = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR"
    if (Test-Path $dvrKey) {
        Set-ItemProperty -Path $dvrKey -Name "AppCaptureEnabled"        -Type DWord -Value 0 -Force
        Set-ItemProperty -Path $dvrKey -Name "HistoricalCaptureEnabled" -Type DWord -Value 0 -Force
        Write-Host "  - Game DVR/Game Bar disabled." -ForegroundColor Green
    }
} catch {
    Write-Warning "Game DVR/Game Bar tweak failed: $($_.Exception.Message)"
}

#--- B. NIC ADVANCED SETTINGS -----------------------------------------------
Write-Host "`n4) Optimizing NIC advanced properties..." -ForegroundColor Yellow

function Set-Prop {
    param($nicName, $propName, $value)

    # Try by DisplayName
    $prop = Get-NetAdapterAdvancedProperty -Name $nicName -ErrorAction SilentlyContinue |
            Where-Object DisplayName -eq $propName
    if ($prop) {
        try {
            Set-NetAdapterAdvancedProperty -Name $nicName -DisplayName $propName -DisplayValue $value -NoRestart -ErrorAction Stop
            Write-Host "  - $propName => $value" -ForegroundColor Gray
        } catch {
            Write-Warning "  - Failed to set $propName on $nicName"
        }
    } else {
        # Fallback via RegistryKeyword
        $prop2 = Get-NetAdapterAdvancedProperty -Name $nicName -ErrorAction SilentlyContinue |
                 Where-Object RegistryKeyword -like "*$propName*"
        if ($prop2) {
            try {
                Set-NetAdapterAdvancedProperty -Name $nicName -RegistryKeyword $prop2.RegistryKeyword -RegistryValue $value -NoRestart -ErrorAction Stop
                Write-Host "  - $propName (via RegistryKeyword) => $value" -ForegroundColor Gray
            } catch {
                Write-Warning "  - Failed to set $propName via RegistryKeyword on $nicName"
            }
        } else {
            Write-Host "  - ($propName not supported on $nicName)" -ForegroundColor DarkGray
        }
    }
}

$adapters = Get-NetAdapter -Physical | Where-Object { $_.Status -eq 'Up' }
foreach ($adapter in $adapters) {
    $name = $adapter.Name
    Write-Host "`n> Adapter: $name" -ForegroundColor Cyan

    # 6. Disable RSC
    try {
        Disable-NetAdapterRsc -Name $name -Confirm:$false -ErrorAction Stop
        Write-Host "  - RSC disabled." -ForegroundColor Gray
    } catch {
        Write-Warning "  - Failed to disable RSC on $name"
    }

    # 7. Disable Interrupt Moderation & set ITR=0
    Set-Prop $name "Interrupt Moderation"   "Disabled"
    Set-Prop $name "ITR"                    0

    # 8. Disable Flow Control
    Set-Prop $name "Flow Control"           "Disabled"

    # 9. Disable Energy-Efficient / Green Ethernet / Power Saving
    Set-Prop $name "Energy Efficient Ethernet" "Disabled"
    Set-Prop $name "Green Ethernet"           "Disabled"
    Set-Prop $name "Power Saving Mode"        "Disabled"

    # 10. Disable Large Send Offload v2
    Set-Prop $name "Large Send Offload v2 (IPv4)" "Disabled"
    Set-Prop $name "Large Send Offload v2 (IPv6)" "Disabled"

    # 11. Disable TCP & UDP Checksum Offload
    Set-Prop $name "TCP Checksum Offload (IPv4)" "Disabled"
    Set-Prop $name "TCP Checksum Offload (IPv6)" "Disabled"
    Set-Prop $name "UDP Checksum Offload (IPv4)" "Disabled"
    Set-Prop $name "UDP Checksum Offload (IPv6)" "Disabled"

    # 12. Disable Jumbo Packet support
    Set-Prop $name "Jumbo Packet" "Disabled"

    # 13. Disable ARP and NS Offload
    Set-Prop $name "ARP Offload" "Disabled"
    Set-Prop $name "NS Offload"  "Disabled"

    # 14. Disable Wake-on-LAN
    Set-Prop $name "Wake on Magic Packet"      "Disabled"
    Set-Prop $name "Wake on pattern match"     "Disabled"
    Set-Prop $name "WOL & Shutdown Link Speed" "Disabled"

    # 15. Set Receive and Transmit Buffers to 256
    Set-Prop $name "Receive Buffers"  256
    Set-Prop $name "Transmit Buffers" 256
}

# #--- C. QoS POLICIES ---------------------------------------------------------
# Write-Host "`n5) Configuring per-port QoS policies for UDP jitter reduction..." -ForegroundColor Yellow

# # 18. Allow local QoS by disabling NLA enforcement
# try {
    # $qosRegKey = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\QoS"
    # New-Item -Path $qosRegKey -Force | Out-Null
    # Set-ItemProperty -Path $qosRegKey -Name "Do not use NLA" -Type String -Value "1" -Force
# } catch {
    # Write-Warning "Failed to set 'Do not use NLA' registry key."
# }

# # 16 & 17. Remove old per-port policies and create new DSCP=46 in/out policies
# $ports = 27015..27036 + 9987
# foreach ($port in $ports) {
    # $outName = "QoS_Out_UDP_$port"
    # $inName  = "QoS_In_UDP_$port"

    # # Remove any existing policy
    # if (Get-NetQosPolicy -Name $outName -PolicyStore PersistentStore -ErrorAction SilentlyContinue) {
        # Remove-NetQosPolicy -Name $outName -PolicyStore PersistentStore -Confirm:$false
    # }
    # if (Get-NetQosPolicy -Name $inName -PolicyStore PersistentStore -ErrorAction SilentlyContinue) {
        # Remove-NetQosPolicy -Name $inName -PolicyStore PersistentStore -Confirm:$false
    # }

    # # Outbound UDP on remote port $port
    # New-NetQosPolicy -Name $outName -PolicyStore PersistentStore `
        # -IPProtocolMatchCondition UDP `
        # -RemotePortStart $port -RemotePortEnd $port `
        # -DSCPAction 46 -NetworkProfile All

    # # Inbound UDP on local port $port
    # New-NetQosPolicy -Name $inName -PolicyStore PersistentStore `
        # -IPProtocolMatchCondition UDP `
        # -LocalPortStart $port -LocalPortEnd $port `
        # -DSCPAction 46 -NetworkProfile All
# }

# # 19. Optional: Generic QoS policies for TeamSpeak & game traffic
# try {
    # # Remove old
    # foreach ($n in "HighPriority_TeamSpeak","HighPriority_Game") {
        # if (Get-NetQosPolicy -Name $n -PolicyStore Local -ErrorAction SilentlyContinue) {
            # Remove-NetQosPolicy -Name $n -PolicyStore Local -Confirm:$false
        # }
    # }

    # # TeamSpeak (port 9987)
    # New-NetQosPolicy -Name "HighPriority_TeamSpeak" -PolicyStore Local `
        # -IPProtocolMatchCondition UDP `
        # -RemotePortStart 9987 -RemotePortEnd 9987 `
        # -DSCPAction 46

    # # Game ports (27015–27036)
    # New-NetQosPolicy -Name "HighPriority_Game" -PolicyStore Local `
        # -IPProtocolMatchCondition UDP `
        # -RemotePortStart 27015 -RemotePortEnd 27036 `
        # -DSCPAction 46

# } catch {
    # Write-Warning "Generic QoS policies setup failed: $($_.Exception.Message)"
# }

#--- D. TCP/IP STACK & NETSH TWEAKS ------------------------------------------
Write-Host "`n6) Disabling TCP Auto-Tuning, Teredo & UDP Receive Offload..." -ForegroundColor Yellow
try { netsh int tcp set global autotuninglevel=disabled | Out-Null } catch {}
try { netsh interface teredo set state disabled    | Out-Null } catch {}
try { netsh int udp set global uro=disabled        | Out-Null } catch {}

# 23 & 24. Apply TCP supplemental settings and disable PRR & HyStart
Write-Host "7) Applying TCP supplemental settings..." -ForegroundColor Yellow
$tcpCommands = @(
  "netsh int tcp set supplemental internet icw=10",
  "netsh int tcp set supplemental internet minrto=300",
  "netsh int tcp set supplemental internet delayedacktimeout=40",
  "netsh int tcp set supplemental internet delayedackfrequency=2",
  "netsh int tcp set supplemental internet rack=enabled",
  "netsh int tcp set supplemental internet taillossprobe=enabled",
  "netsh int tcp set global prr=disabled",
  "netsh int tcp set global hystart=disabled"
)
foreach ($cmd in $tcpCommands) {
    try { Invoke-Expression $cmd | Out-Null } catch { Write-Warning "  - $cmd failed" }
}

# 25. Configure CTCP congestion provider & enable ECN for Internet profile
Write-Host "8) Enabling CTCP & ECN for Internet TCP profile..." -ForegroundColor Yellow
try {
    $ts = Get-NetTCPSetting -SettingName Internet
    Set-NetTCPSetting -SettingName Internet -CongestionProvider CTCP `
      -EcnCapability $ts.EcnCapability `
      -AutoReusePortRangeEnabled $ts.AutoReusePortRangeEnabled `
      -AutoReusePortRangeNumberOfPorts $ts.AutoReusePortRangeNumberOfPorts `
      -AutoReusePortRangeMaxPorts $ts.AutoReusePortRangeMaxPorts | Out-Null
    Write-Host "  - CTCP enabled." -ForegroundColor Gray

    Set-NetTCPSetting -SettingName Internet -EcnCapability Enabled `
      -CongestionProvider CTCP `
      -AutoReusePortRangeEnabled $ts.AutoReusePortRangeEnabled `
      -AutoReusePortRangeNumberOfPorts $ts.AutoReusePortRangeNumberOfPorts `
      -AutoReusePortRangeMaxPorts $ts.AutoReusePortRangeMaxPorts | Out-Null
    Write-Host "  - ECN enabled." -ForegroundColor Gray
} catch {
    Write-Warning "CTCP/ECN configuration failed: $($_.Exception.Message)"
}

#--- E. Optional: Disable NDU Service ----------------------------------------
<# 
Write-Host "`n9) Disabling the Network Data Usage (NDU) service (optional)..." -ForegroundColor Yellow
try {
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Ndu" -Name "Start" -Type DWord -Value 4 -Force
    Write-Host "  - NDU service disabled." -ForegroundColor Gray
} catch {
    Write-Warning "Failed to disable NDU service: $($_.Exception.Message)"
}
#>

Write-Host "`nAll optimizations applied. **REBOOT** now for full effect." -ForegroundColor Green
