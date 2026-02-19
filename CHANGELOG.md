# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- CHANGELOG.md for change history.
- `Private/Constants.ps1`: central registry paths, backup file names, default DSCP, NIC reset display names.
- `Get-UjPhysicalUpAdapter` helper in Nic.ps1 for consistent "physical up" adapter usage.
- Restore helpers: `Restore-UjRegistryFromBackup`, `Restore-UjQosFromBackup`, `Restore-UjNicFromBackup`, `Restore-UjRscFromBackup`, `Restore-UjPowerPlanFromBackup`; `Restore-UjState` now orchestrates these.
- Comment-based help for `Invoke-UdpJitterOptimization` and for `optimize-udp-jitter.ps1`.
- `-SkipAdminCheck` parameter on root script `optimize-udp-jitter.ps1` for script/module parity.

### Changed

- Documentation: BUGS-AND-FIXES.md §10 updated to reflect that `reset-udp-jitter.ps1` is historically removed; root script is the single entry point.
- Backup: power plan backup normalizes GUID (with or without braces) and writes consistent format for restore.
- Restore: power plan restore accepts GUID with or without braces; warns if no valid GUID found.
- Restore: QoS restore validates backup file and parses before removing policies; per-policy try/catch; port vs app branch fixed (no unconditional continue after failed port parse).
- Restore: NIC advanced restore treats empty string `RegistryValue` as invalid (§24).
- Reset: only resets NIC advanced properties that the module sets (using `UjNicResetDisplayNames`), not `DisplayName '*'`.
- Module loads `Constants.ps1` first, then remaining Private scripts.

### Fixed

- Restore and Reset now gate registry import, QoS removal, and NLA registry removal with `ShouldProcess` (-WhatIf/-Confirm respected).
- GameDVR: `Set-ItemProperty -Type DWord` replaced with `-PropertyType DWord` so -DisableGameDvr does not throw.
- Power plan Ultimate: `powercfg /duplicatescheme` output is parsed and the new GUID is used for `powercfg /S`.
- DryRun is passed to Backup and Restore; no directory creation or writes when DryRun is set; BackupFolder/New-UjDirectory skipped for ResetDefaults and when DryRun.
- `Get-UjManagedQosPolicy`: on catch, writes Warning with error details instead of silent return.
- Registry: `Export-UjRegistryKey` returns bool and warns on failure; `Import-UjRegistryFile` warns when file missing and returns bool; LASTEXITCODE checked.
- URO and Reset netsh: LASTEXITCODE checked after each invocation; warnings on non-zero exit.
