# UDP Jitter Optimization for Windows 10/11

PowerShell module and scripts to reduce UDP jitter on Windows endpoints with safety-first defaults, backup/restore, and preset-based tuning.

## Highlights

- Endpoint QoS DSCP marking (`EF=46`) for TeamSpeak/CS2 ports and optional app policies.
- Three presets (`1=Conservative`, `2=Medium`, `3=Higher risk`) with explicit trade-offs.
- Full backup/restore workflow for registry, QoS, NIC advanced properties, RSC, and power plan.
- CLI and WinForms GUI.

## Requirements

- Windows 10/11
- PowerShell 7+
- Run elevated for apply/backup/restore/reset

## Quick Start

```powershell
# Optional for current session
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

# Apply conservative preset
pwsh -NoProfile -ExecutionPolicy Bypass -File .\optimize-udp-jitter.ps1 -Action Apply -Preset 1

# Preview only
pwsh -NoProfile -ExecutionPolicy Bypass -File .\optimize-udp-jitter.ps1 -Action Apply -Preset 2 -DryRun

# Backup and restore
pwsh -NoProfile -ExecutionPolicy Bypass -File .\optimize-udp-jitter.ps1 -Action Backup
pwsh -NoProfile -ExecutionPolicy Bypass -File .\optimize-udp-jitter.ps1 -Action Restore
```

## Screenshots

CLI `Apply -DryRun`:

![CLI Apply DryRun](docs/assets/screenshots/cli-apply-dryrun.png)

CLI `Restore -PassThru`:

![CLI Restore PassThru](docs/assets/screenshots/cli-restore-passthru.png)

GUI (WinForms):

![GUI Main Window](docs/assets/screenshots/gui-main.png)

## GUI

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\optimize-udp-jitter-gui.ps1
```

The GUI supports Apply/Backup/Restore/ResetDefaults and action-specific options (ports, app policies, AFD threshold, power plan, DryRun, GameDVR/URO toggles).

## Module Usage

```powershell
Import-Module .\WindowsUdpJitterOptimization\WindowsUdpJitterOptimization.psd1 -Force
Invoke-UdpJitterOptimization -Action Apply -Preset 1

# Structured result for automation
Invoke-UdpJitterOptimization -Action Restore -PassThru
```

## Key Parameters

- `-Action`: `Apply`, `Backup`, `Restore`, `ResetDefaults`
- `-Preset`: `1`, `2`, `3` (Apply only)
- `-IncludeAppPolicies`, `-AppPaths`
- `-AfdThreshold`
- `-PowerPlan`: `None`, `HighPerformance`, `Ultimate`
- `-DisableGameDvr`, `-DisableUro`
- `-BackupFolder`
- `-AllowUnsafeBackupFolder` (override safety block for system paths)
- `-DryRun`
- `-PassThru`

## Validation and CI

```bash
./scripts/ci-local.sh
```

Runs PSScriptAnalyzer and Pester locally (same checks as CI).

## Documentation

- Technical documentation: [docs/DOCUMENTATION.md](docs/DOCUMENTATION.md)

## Security

Do not share sensitive local data from backups or logs in public issues.
See [SECURITY.md](SECURITY.md).
