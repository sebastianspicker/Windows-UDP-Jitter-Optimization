<#
.SYNOPSIS
  Reset script to undo Ultimate UDP Jitter Reduction optimizations and restore Windows defaults.

.DESCRIPTION
  Reverts all registry, NIC, QoS and netsh tweaks applied by the jitter-reduction script:
    A. Power Plan → Balanced
    B. Registry → remove NetworkThrottlingIndex, SystemResponsiveness, FastSendDatagramThreshold, MMCSS “Games” key
    C. Game DVR/Game Bar → re-enable
    D. NIC Advanced Settings → reset all advanced properties; re-enable RSC
    E. QoS Policies → remove per-port and generic policies; clear “Do not use NLA”
    F. netsh/TCP Stack → restore defaults for autotuning, teredo, URO, supplemental settings, PRR, HyStart
    G. CTCP & ECN → set back to NewReno and Disabled
    H. (Optional) NDU Service → set to Automatic
  Requires Administrator. Reboot after completion.
#>

#--- A. ADMIN CHECK ----------------------------------------------------------
Set-StrictMode -Version Latest
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent() `
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as Administrator!"
    exit 1
}
Write-Host "`n>>> Resetting UDP Jitter Tweaks to Defaults <<<`n" -ForegroundColor Cyan

#--- A1. Power Plan ----------------------------------------------------------
Write-Host "Restoring Balanced power plan..." -ForegroundColor Yellow
try {
    # GUID for Balanced plan
    powercfg /S 381b4222-f694-41f0-9685-ff5bb260df2e | Out-Null
    Write-Host "  - Power plan set to Balanced." -ForegroundColor Green
} catch {
    Write-Warning "  - Failed to restore power plan."
}

#--- B. Registry Cleanup -----------------------------------------------------
Write-Host "`nRemoving registry tweaks..." -ForegroundColor Yellow
$mmKey   = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
$afdKey  = "HKLM:\SYSTEM\CurrentControlSet\Services\AFD\Parameters"
$gamesKey= "$mmKey\Tasks\Games"
Try {
    Remove-ItemProperty -Path $mmKey   -Name "NetworkThrottlingIndex"   -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $mmKey   -Name "SystemResponsiveness"     -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $afdKey  -Name "FastSendDatagramThreshold" -ErrorAction SilentlyContinue
    if (Test-Path $gamesKey) {
        Remove-Item -Path $gamesKey -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host "  - Registry tweaks removed." -ForegroundColor Green
} catch {
    Write-Warning "  - Error cleaning registry: $($_.Exception.Message)"
}

#--- C. Re-enable Game DVR/Game Bar -----------------------------------------
Write-Host "`nRe-enabling Game DVR/Game Bar..." -ForegroundColor Yellow
Try {
    $dvr = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR"
    if (Test-Path $dvr) {
        Set-ItemProperty -Path $dvr -Name "AppCaptureEnabled"        -Type DWord -Value 1 -Force
        Set-ItemProperty -Path $dvr -Name "HistoricalCaptureEnabled" -Type DWord -Value 1 -Force
        Write-Host "  - Game DVR/Game Bar re-enabled." -ForegroundColor Green
    } else {
        Write-Host "  - Game DVR/Game Bar key not present." -ForegroundColor Gray
    }
} catch {
    Write-Warning "  - Could not re-enable Game DVR/Game Bar: $($_.Exception.Message)"
}

#--- D. Reset NIC Advanced Settings -----------------------------------------
Write-Host "`nResetting NIC advanced properties to driver defaults..." -ForegroundColor Yellow
$adapters = Get-NetAdapter -Physical | Where-Object { $_.Status -eq 'Up' }
foreach ($adapter in $adapters) {
    $name = $adapter.Name
    Write-Host "`n> Adapter: $name" -ForegroundColor Cyan
    try {
        # Reset all advanced properties
        Reset-NetAdapterAdvancedProperty -Name $name -DisplayName "*" -Confirm:$false -ErrorAction Stop
        Write-Host "  - Advanced properties reset." -ForegroundColor Gray
    } catch {
        Write-Warning "  - Could not reset advanced props on $name"
    }
    try {
        # Re-enable Receive Segment Coalescing
        Enable-NetAdapterRsc -Name $name -ErrorAction Stop
        Write-Host "  - RSC re-enabled." -ForegroundColor Gray
    } catch {
        Write-Warning "  - Could not re-enable RSC on $name"
    }
}

#--- E. Remove QoS Policies -------------------------------------------------
Write-Host "`nRemoving QoS policies..." -ForegroundColor Yellow
try {
    # Remove per-port policies in PersistentStore
    $ports = 27015..27036 + 9987
    foreach ($p in $ports) {
        foreach ($n in @("QoS_Out_UDP_$p","QoS_In_UDP_$p")) {
            if (Get-NetQosPolicy -Name $n -PolicyStore PersistentStore -ErrorAction SilentlyContinue) {
                Remove-NetQosPolicy -Name $n -PolicyStore PersistentStore -Confirm:$false
            }
        }
    }
    # Remove generic Local policies
    foreach ($n in @("HighPriority_TeamSpeak","HighPriority_Game")) {
        if (Get-NetQosPolicy -Name $n -PolicyStore Local -ErrorAction SilentlyContinue) {
            Remove-NetQosPolicy -Name $n -PolicyStore Local -Confirm:$false
        }
    }
    # Clear “Do not use NLA”
    $qosRegKey = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\QoS"
    Remove-ItemProperty -Path $qosRegKey -Name "Do not use NLA" -ErrorAction SilentlyContinue
    Write-Host "  - QoS policies and registry key cleared." -ForegroundColor Green
} catch {
    Write-Warning "  - Error removing QoS policies: $($_.Exception.Message)"
}

#--- F. netsh & TCP Stack Reset ----------------------------------------------
Write-Host "`nRestoring netsh/TCP defaults..." -ForegroundColor Yellow
try {
    netsh int tcp set global autotuninglevel=normal | Out-Null
    Write-Host "  - TCP Auto-Tuning set to normal." -ForegroundColor Gray
} catch {
    Write-Warning "  - Failed to reset TCP Auto-Tuning."
}
try {
    netsh interface teredo set state default | Out-Null
    Write-Host "  - Teredo tunneling set to default." -ForegroundColor Gray
} catch {
    Write-Warning "  - Failed to reset Teredo."
}
try {
    netsh int udp set global uro=enabled | Out-Null
    Write-Host "  - UDP Receive Offload enabled." -ForegroundColor Gray
} catch {
    Write-Warning "  - Failed to reset UDP URO."
}

# Reset supplemental TCP settings to defaults
$defaults = @(
  "netsh int tcp set supplemental internet icw=default",
  "netsh int tcp set supplemental internet minrto=default",
  "netsh int tcp set supplemental internet delayedacktimeout=default",
  "netsh int tcp set supplemental internet delayedackfrequency=default",
  "netsh int tcp set supplemental internet rack=disabled",
  "netsh int tcp set supplemental internet taillossprobe=disabled",
  "netsh int tcp set global prr=enabled",
  "netsh int tcp set global hystart=enabled"
)
foreach ($cmd in $defaults) {
    try {
        Invoke-Expression $cmd | Out-Null
        Write-Host "  - $cmd" -ForegroundColor Gray
    } catch {
        Write-Warning "  - Failed: $cmd"
    }
}

#--- G. CTCP & ECN Reset -----------------------------------------------------
Write-Host "`nRestoring TCP congestion & ECN defaults..." -ForegroundColor Yellow
try {
    $ts = Get-NetTCPSetting -SettingName Internet
    # Default provider = NewReno
    Set-NetTCPSetting -SettingName Internet -CongestionProvider NewReno `
      -EcnCapability Disabled `
      -AutoReusePortRangeEnabled $ts.AutoReusePortRangeEnabled `
      -AutoReusePortRangeNumberOfPorts $ts.AutoReusePortRangeNumberOfPorts `
      -AutoReusePortRangeMaxPorts $ts.AutoReusePortRangeMaxPorts | Out-Null
    Write-Host "  - CongestionProvider=NewReno, ECN=Disabled" -ForegroundColor Gray
} catch {
    Write-Warning "  - Failed to restore CTCP/ECN defaults."
}

#--- H. Optional: Re-enable NDU Service --------------------------------------
<# 
Write-Host "`nRe-enabling NDU service..." -ForegroundColor Yellow
try {
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Ndu" -Name "Start" -Type DWord -Value 2 -Force
    Write-Host "  - NDU service set to Automatic." -ForegroundColor Gray
} catch {
    Write-Warning "  - Failed to re-enable NDU service."
}
#>

Write-Host "`nAll settings restored to defaults. **REBOOT** now for full effect." -ForegroundColor Green
