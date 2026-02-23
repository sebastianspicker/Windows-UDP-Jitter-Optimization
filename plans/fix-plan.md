# Fix Plan: Deep Code Inspection Findings

## Overview

This document outlines the detailed fix plan for issues identified during the deep code inspection of the Windows-UDP-Jitter-Optimization project. Issues are prioritized from P0 (critical) to P3 (low priority).

---

## P0 Issues (Critical)

### P0-1: DryRun not passed to backup during Apply action

**File:** `WindowsUdpJitterOptimization/Public/Invoke-UdpJitterOptimization.ps1`  
**Line:** 129  
**Severity:** Critical - Violates user expectation of dry-run mode

**Current Code:**
```powershell
Backup-UjState -BackupFolder $BackupFolder
```

**Problem:**
When a user runs `Invoke-UdpJitterOptimization -Action Apply -DryRun`, the backup operation at line 129 still writes files to disk because `-DryRun` is not passed through.

**Fix:**
```powershell
Backup-UjState -BackupFolder $BackupFolder -DryRun:$DryRun
```

**Testing:**
- Run with `-DryRun` and verify no files are created in backup folder
- Run without `-DryRun` and verify backup files are created

---

## P1 Issues (Breaking/High)

### P1-1: Set-ItemProperty uses invalid -PropertyType parameter

**File:** `WindowsUdpJitterOptimization/Private/Actions.ps1`  
**Lines:** 534-535  
**Severity:** High - Runtime error when DisableGameDvr is used

**Current Code:**
```powershell
Set-ItemProperty -Path $dvr -Name 'AppCaptureEnabled' -PropertyType DWord -Value $value -Force
Set-ItemProperty -Path $dvr -Name 'HistoricalCaptureEnabled' -PropertyType DWord -Value $value -Force
```

**Problem:**
`Set-ItemProperty` does not have a `-PropertyType` parameter. This causes a terminating error when `-DisableGameDvr` is used without `-DryRun`.

**Fix:**
```powershell
New-ItemProperty -Path $dvr -Name 'AppCaptureEnabled' -PropertyType DWord -Value $value -Force | Out-Null
New-ItemProperty -Path $dvr -Name 'HistoricalCaptureEnabled' -PropertyType DWord -Value $value -Force | Out-Null
```

**Testing:**
- Run with `-DisableGameDvr` without `-DryRun` and verify no error
- Verify registry values are set correctly

---

### P1-2: NIC restore treats empty string RegistryValue as valid

**File:** `WindowsUdpJitterOptimization/Private/Actions.ps1`  
**Line:** 185  
**Severity:** High - Can cause invalid restore attempts

**Current Code:**
```powershell
if ($property.RegistryKeyword -and [string]::IsNullOrEmpty($property.RegistryKeyword) -eq $false -and [string]::IsNullOrEmpty($property.RegistryValue) -eq $false) {
```

**Problem:**
The condition checks for non-empty RegistryValue, but the logic is correct. However, the issue is that CSV import can produce empty strings for missing values, and the current check handles this. The real issue is that we should also validate the RegistryValue is not just whitespace.

**Fix:**
The current code already handles empty strings correctly with `[string]::IsNullOrEmpty`. No change needed - this was a false positive on re-inspection.

**Status:** NO FIX NEEDED - Code is correct.

---

### P1-3: RSC restore loses mixed IPv4/IPv6 state

**File:** `WindowsUdpJitterOptimization/Private/Actions.ps1`  
**Lines:** 207-212  
**Severity:** High - Data loss during restore

**Current Code:**
```powershell
$ipv4Enabled = [string]$row.IPv4Enabled -ieq 'True'
$ipv6Enabled = [string]$row.IPv6Enabled -ieq 'True'
$enable = $ipv4Enabled -or $ipv6Enabled
if ($enable) {
  if ($PSCmdlet.ShouldProcess($row.Name, 'Enable NetAdapterRsc')) { Enable-NetAdapterRsc -Name $row.Name -ErrorAction SilentlyContinue | Out-Null }
} else {
  if ($PSCmdlet.ShouldProcess($row.Name, 'Disable NetAdapterRsc')) { Disable-NetAdapterRsc -Name $row.Name -Confirm:$false -ErrorAction SilentlyContinue | Out-Null }
}
```

**Problem:**
If the original state was IPv4 enabled + IPv6 disabled, restore will enable both because `$enable = $true`. The mixed state is lost.

**Fix:**
```powershell
$ipv4Enabled = [string]$row.IPv4Enabled -ieq 'True'
$ipv6Enabled = [string]$row.IPv6Enabled -ieq 'True'
if ($PSCmdlet.ShouldProcess($row.Name, 'Restore NetAdapterRsc IPv4/IPv6')) {
  if ($ipv4Enabled) {
    Enable-NetAdapterRsc -Name $row.Name -IPv4 -ErrorAction SilentlyContinue | Out-Null
  } else {
    Disable-NetAdapterRsc -Name $row.Name -IPv4 -ErrorAction SilentlyContinue | Out-Null
  }
  if ($ipv6Enabled) {
    Enable-NetAdapterRsc -Name $row.Name -IPv6 -ErrorAction SilentlyContinue | Out-Null
  } else {
    Disable-NetAdapterRsc -Name $row.Name -IPv6 -ErrorAction SilentlyContinue | Out-Null
  }
}
```

**Note:** Need to verify if `Enable-NetAdapterRsc` supports `-IPv4`/`-IPv6` parameters. If not, document the limitation.

**Testing:**
- Backup with mixed RSC state
- Restore and verify both IPv4 and IPv6 states are preserved

---

### P1-4: ITR lookup uses DisplayName instead of RegistryKeyword

**File:** `WindowsUdpJitterOptimization/Private/Nic.ps1`  
**Line:** 118  
**Severity:** High - Locale-dependent lookup

**Current Code:**
```powershell
$itr = Get-NetAdapterAdvancedProperty -Name $nic.Name -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq 'ITR' }
```

**Problem:**
This lookup uses DisplayName which is locale/driver dependent, inconsistent with the P0 fix that transitioned to RegistryKeywords.

**Fix:**
```powershell
$itr = Get-NetAdapterAdvancedProperty -Name $nic.Name -RegistryKeyword '*InterruptModerationRate' -ErrorAction SilentlyContinue
```

**Testing:**
- Test on system with ITR property
- Verify property is found correctly

---

## P2 Issues (Nice-to-haves)

### P2-1: Duplicate registry value setting in MMCSS audio safety

**File:** `WindowsUdpJitterOptimization/Private/Actions.ps1`  
**Lines:** 300-309  
**Severity:** Medium - Code redundancy

**Current Code:**
```powershell
Set-UjRegistryValue -Key $audio -Name 'Background Only' -Type DWord -Value 0
Set-UjRegistryValue -Key $audio -Name 'Priority' -Type DWord -Value 6
Set-UjRegistryValue -Key $audio -Name 'Clock Rate' -Type DWord -Value 10000
Set-UjRegistryValue -Key $audio -Name 'Scheduling Category' -Type String -Value 'High'
Set-UjRegistryValue -Key $audio -Name 'SFIO Priority' -Type String -Value 'High'

Set-UjRegistryValue -Key $audio -Name 'BackgroundOnly' -Type DWord -Value 0
Set-UjRegistryValue -Key $audio -Name 'SchedulingCategory' -Type String -Value 'High'
Set-UjRegistryValue -Key $audio -Name 'SFIOPriority' -Type String -Value 'High'
```

**Problem:**
Both spaced and non-spaced property names are set. This is redundant and may indicate uncertainty about which naming convention Windows uses.

**Fix:**
Research which naming convention Windows actually uses for MMCSS registry values and remove the duplicates. Based on Windows documentation, the non-spaced versions (BackgroundOnly, SchedulingCategory, SFIOPriority) are the correct ones.

**Recommended Fix:**
```powershell
Set-UjRegistryValue -Key $audio -Name 'BackgroundOnly' -Type DWord -Value 0
Set-UjRegistryValue -Key $audio -Name 'Priority' -Type DWord -Value 6
Set-UjRegistryValue -Key $audio -Name 'Clock Rate' -Type DWord -Value 10000
Set-UjRegistryValue -Key $audio -Name 'SchedulingCategory' -Type String -Value 'High'
Set-UjRegistryValue -Key $audio -Name 'SFIOPriority' -Type String -Value 'High'
```

**Testing:**
- Verify MMCSS audio settings are applied correctly
- Check registry after apply to confirm values

---

### P2-2: Missing RegistryKeywords in map

**File:** `WindowsUdpJitterOptimization/Private/Constants.ps1`  
**Severity:** Medium - Fallback to locale-dependent matching

**Problem:**
The following properties are in `$script:UjNicResetDisplayNames` but not in `$script:UjNicKeywordMap`:
- Green Ethernet
- Power Saving Mode
- WOL & Shutdown Link Speed

**Fix:**
Add standardized keywords to the map:
```powershell
$script:UjNicKeywordMap = @{
  # ... existing entries ...
  'Green Ethernet'           = '*GreenEthernet'
  'Power Saving Mode'        = '*PowerSavingMode'
  'WOL & Shutdown Link Speed' = '*WakeOnLink'
}
```

**Note:** Need to verify the correct RegistryKeyword values for these properties as they may vary by driver vendor.

**Testing:**
- Test on systems with these NIC properties
- Verify keywords match correctly

---

### P2-3: Reset uses localized DisplayName list

**File:** `WindowsUdpJitterOptimization/Private/Actions.ps1`  
**Line:** 613  
**Severity:** Medium - Reset may not work on non-English systems

**Current Code:**
```powershell
foreach ($displayName in $script:UjNicResetDisplayNames) {
  if ($PSCmdlet.ShouldProcess(("{0}: {1}" -f $adapter.Name, $displayName), 'Reset NetAdapterAdvancedProperty')) {
    try { Reset-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName $displayName -Confirm:$false -ErrorAction Stop | Out-Null }
```

**Problem:**
`Reset-NetAdapterAdvancedProperty` is called with DisplayName which is locale-dependent. On non-English Windows, these names won't match.

**Fix:**
Create a keyword-based reset approach:
1. Add `$script:UjNicResetKeywords` array in Constants.ps1 with RegistryKeywords
2. Use `-RegistryKeyword` parameter instead of `-DisplayName`

**Constants.ps1 addition:**
```powershell
$script:UjNicResetKeywords = @(
  '*EEE', '*InterruptModeration', '*FlowControl', '*GreenEthernet', '*PowerSavingMode',
  '*JumboPacket', '*LsoV2IPv4', '*LsoV2IPv6', '*UDPChecksumOffloadIPv4', '*UDPChecksumOffloadIPv6',
  '*TCPChecksumOffloadIPv4', '*TCPChecksumOffloadIPv6', '*ARPOffload', '*NSOffload',
  '*WakeOnMagicPacket', '*WakeOnPattern', '*InterruptModerationRate', '*ReceiveBuffers', '*TransmitBuffers'
)
```

**Actions.ps1 fix:**
```powershell
foreach ($keyword in $script:UjNicResetKeywords) {
  if ($PSCmdlet.ShouldProcess(("{0}: {1}" -f $adapter.Name, $keyword), 'Reset NetAdapterAdvancedProperty')) {
    try { Reset-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword $keyword -Confirm:$false -ErrorAction Stop | Out-Null }
```

**Testing:**
- Test reset on English Windows
- Test reset on non-English Windows (if possible)

---

## P3 Issues (Low Priority)

### P3-1: Get-UjManagedQosPolicy hides query failures

**File:** `WindowsUdpJitterOptimization/Private/Qos.ps1`  
**Lines:** 6-11  
**Severity:** Low - Difficult to diagnose issues

**Current Code:**
```powershell
try {
  Get-NetQosPolicy -ErrorAction Stop | Where-Object { $_.Name -like 'QoS_*' }
} catch {
  Write-Warning -Message ("Get-NetQosPolicy failed: {0}. Treat as no managed policies." -f $_.Exception.Message)
  return
}
```

**Problem:**
On catch, the function returns nothing, so callers cannot distinguish between "no policies" and "query failed".

**Fix:**
Add a verbose log and consider returning a marker or throwing:
```powershell
try {
  Get-NetQosPolicy -ErrorAction Stop | Where-Object { $_.Name -like 'QoS_*' }
} catch {
  Write-Warning -Message ("Get-NetQosPolicy failed: {0}. Treat as no managed policies." -f $_.Exception.Message)
  Write-Verbose -Message "QoS query failure - backup/restore may be incomplete"
  return
}
```

**Status:** LOW PRIORITY - Current behavior is acceptable with the warning message.

---

## Implementation Order

1. **P0-1:** Fix DryRun bypass in Invoke-UdpJitterOptimization.ps1
2. **P1-1:** Fix Set-ItemProperty invalid parameter in Actions.ps1
3. **P1-4:** Fix ITR lookup in Nic.ps1
4. **P1-3:** Fix RSC restore state loss in Actions.ps1
5. **P2-3:** Add keyword-based reset in Constants.ps1 and Actions.ps1
6. **P2-2:** Add missing RegistryKeywords in Constants.ps1
7. **P2-1:** Remove duplicate registry value setting in Actions.ps1
8. **P3-1:** Add verbose logging for QoS query failure (optional)

---

## Testing Checklist

After implementing fixes, verify:

- [ ] `Invoke-UdpJitterOptimization -Action Apply -DryRun` creates no files
- [ ] `Invoke-UdpJitterOptimization -Action Apply -DisableGameDvr` works without error
- [ ] `Invoke-UdpJitterOptimization -Action Backup -DryRun` creates no files
- [ ] `Invoke-UdpJitterOptimization -Action Restore -DryRun` makes no changes
- [ ] NIC properties are correctly identified on non-English Windows (if testable)
- [ ] RSC restore preserves mixed IPv4/IPv6 state
- [ ] Reset works correctly on all systems

---

## Files to Modify

| File | Changes |
|------|---------|
| `WindowsUdpJitterOptimization/Public/Invoke-UdpJitterOptimization.ps1` | P0-1 |
| `WindowsUdpJitterOptimization/Private/Actions.ps1` | P1-1, P1-3, P2-1, P2-3 |
| `WindowsUdpJitterOptimization/Private/Nic.ps1` | P1-4 |
| `WindowsUdpJitterOptimization/Private/Constants.ps1` | P2-2, P2-3 |
| `deep_code_inspection.md` | Update with new findings |
