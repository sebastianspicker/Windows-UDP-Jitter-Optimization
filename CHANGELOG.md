# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- `Invoke-UdpJitterOptimization` now supports `-PassThru` with structured result output for automation.
- `Invoke-UdpJitterOptimization` now supports `-AllowUnsafeBackupFolder` to explicitly override backup path safety checks.
- Restore component status model (`OK|Warn|Skipped`) across `Registry`, `Qos`, `NicAdvanced`, `Rsc`, and `PowerPlan`.
- New private action split files:
  - `Private/Actions.BackupRestore.ps1`
  - `Private/Actions.Apply.ps1`
  - `Private/Actions.Reset.ps1`
- New backup folder safety helper `Test-UjUnsafeBackupFolder`.
- New Pester coverage for PassThru schema, unsafe backup folder behavior, restore status mapping, and CLI default backup folder resolution.

### Changed

- Module loader (`WindowsUdpJitterOptimization.psm1`) now uses deterministic private/public script load order.
- CLI wrapper (`optimize-udp-jitter.ps1`) resolves default backup folder via module function `Get-UjDefaultBackupFolder` when not provided.
- GUI (`optimize-udp-jitter-gui.ps1`) now applies action-dependent control enablement, centralized input validation, and phased log output (`[Validate]`, action phase, `[Output]`, `[Done]`).
- Documentation consolidated aggressively to one technical document: `docs/DOCUMENTATION.md`.
- README reduced to quick operational entrypoint with a single technical docs link.

### Removed

- `testResults.xml` from repository tracking.
- Deprecated/duplicate technical docs:
  - `docs/BUGS-AND-FIXES.md`
  - `docs/INSPECTION-AND-FIXES.md`
  - `docs/plans/repo-and-code-improvements-plan.md`
- Legacy monolithic private action file `Private/Actions.ps1`.

### Fixed

- Restore summary now exposes full per-component status instead of registry-only output.
- Backup folder duplication removed from CLI default parameter expression.
- Dry-run Apply path no longer emits an empty information message.
- Backup folder unsafe-path detection hardened to check canonical sensitive roots (`Windows`, `System32`, `Program Files`) more robustly.
- GUI run action now has explicit reentry protection to avoid accidental double-execution on rapid clicks.
