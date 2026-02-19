# UDP Jitter Optimization for Windows 10/11
Safe defaults with tiered risk levels and full backup/restore workflow for real‑time UDP workloads (e.g., CS2, TeamSpeak).
- Focus: outbound DSCP marking via Windows QoS Policies plus conservative NIC/stack tuning for lower latency variance.
- Presets: `1=Conservative, 2=Medium, 3=Higher risk`, each with explicit CPU/compatibility trade‑offs and full failsafe backups.

## Scope: Client vs. Server
- Client endpoints: apply endpoint DSCP policies, enable local QoS, and selectively adjust NIC energy/latency features to stabilize voice/game traffic on Windows 10/11.
- Server endpoints: use the same Windows QoS mechanisms but consider data‑center NIC tuning guidance and platform vendor docs; verify that network devices honor DSCP and align server NIC features with low‑latency guidance.

## What the script changes
- QoS (endpoint `DSCP EF=46`): creates port‑based policies in PersistentStore for CS2/TeamSpeak and optionally app‑based policies, with idempotent removal/re‑create logic.
- Enable local QoS on non‑domain machines: sets “Do not use NLA” so DSCP isn’t cleared by NLA contexts, consistent with Microsoft QoS guidance.
- MMCSS audio safety: ensures `SystemProfile\Tasks\Audio` exists with stable defaults and starts core audio services to avoid silent audio failures.
- NIC tuning per preset: disables Energy Efficient Ethernet by default; reduces interrupt moderation and disables flow/green/power‑saving/jumbo at preset 2; adds RSC/offload/ITR toggles at preset 3, with CPU‑cost warnings.
- AFD threshold (conservative): sets `FastSendDatagramThreshold=1500` to align with MTU‑sized UDP datagrams, avoiding overly aggressive global thresholds.
- Full backup/restore: exports MMCSS/AFD registry, inventories QoS policies, snapshots NIC advanced properties and RSC status, and saves the active power plan for rollback.

## Presets and trade‑offs
- Preset 1 (Conservative, default)  
  - Client: protect MMCSS audio; enable local QoS; add DSCP EF policies for CS2/TS; disable EEE if supported.
  - Server: same QoS approach; leave advanced NIC offloads/moderation intact unless measured issues exist, per Microsoft server tuning guidance.
- Preset 2 (Medium)  
  - Client: reduce/disable interrupt moderation, disable flow control/green/power‑saving/jumbo, set AFD `FastSendDatagramThreshold=1500` (reboot recommended).
  - Server: evaluate per‑workload; flow control/interrupt moderation changes can affect throughput under congestion, so test under realistic load.
- Preset 3 (Higher risk)  
  - Client: optional RSC off, LSO/checksum offloads off, ARP/NS/WoL off, `ITR=0` if exposed, optional `SystemResponsiveness=0` and `NetworkThrottlingIndex=FFFFFFFF`, and optional URO disable via netsh.
  - Server: only apply with clear measurements and change control; these may raise CPU/ISR/DPC and affect scalability on busy hosts.

Notes:
- DSCP is outbound marking; end‑to‑end benefit requires that intermediate devices honor DSCP, which is common in enterprise/provider QoS designs.
- Reducing moderation/turning off offloads/RSC/URO can lower jitter but increases CPU; always measure before and after.

## Client guidance (Windows 10/11)
- Use `New‑NetQosPolicy` to DSCP‑mark voice/game ports in PersistentStore; verify with `Get‑NetQosPolicy` that policies are active.
- Enable local QoS (“Do not use NLA”) so DSCP tags persist on non‑domain machines per Microsoft guidance.
- Disable Energy Efficient Ethernet (EEE) where supported and consider lowering interrupt moderation if CPU headroom exists.
- Keep offloads enabled by default; only disable in preset 3 for driver‑specific issues after measurement.

## Server guidance (Windows Server)
- Apply QoS marking with the same PowerShell cmdlets; domain GPOs can centralize QoS if desired, using Microsoft’s QoS port range guidance as a model.
- Tune NICs following Microsoft’s server networking tuning guidance; prioritize RSS/RSC/offload usage unless profiling shows latency spikes.
- Validate DC/ToR/edge policies to ensure DSCP EF is recognized and mapped to a low‑latency queue across the path, per common provider QoS practice.

## Requirements
- Windows 10/11 with administrative privileges; PowerShell can apply QoS in PersistentStore without RSAT on clients.
- Reboot recommended after AFD/MMCSS registry changes for full effect; DSCP policy and NIC changes apply immediately.

## Quick start (Windows 10/11)
Run PowerShell 7+ as Administrator:

```powershell
# (Optional) allow running in the current session only
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

# Apply preset 1 (safe default)
pwsh -NoProfile -ExecutionPolicy Bypass -File .\optimize-udp-jitter.ps1 -Action Apply -Preset 1

# Backup / restore
pwsh -NoProfile -ExecutionPolicy Bypass -File .\optimize-udp-jitter.ps1 -Action Backup
pwsh -NoProfile -ExecutionPolicy Bypass -File .\optimize-udp-jitter.ps1 -Action Restore

# Reset to baseline defaults
pwsh -NoProfile -ExecutionPolicy Bypass -File .\optimize-udp-jitter.ps1 -Action ResetDefaults

# Preview (no system changes)
pwsh -NoProfile -ExecutionPolicy Bypass -File .\optimize-udp-jitter.ps1 -Action Apply -Preset 2 -DryRun
```

Module usage (advanced):

```powershell
Import-Module .\WindowsUdpJitterOptimization\WindowsUdpJitterOptimization.psd1 -Force
Invoke-UdpJitterOptimization -Action Apply -Preset 1
```

## Documentation
- **Full documentation (English, with architecture and Mermaid diagrams):** [docs/DOCUMENTATION.md](docs/DOCUMENTATION.md)

## Configuration
Key parameters (see `optimize-udp-jitter.ps1 -?` for full help):
- `-Action`: `Apply`, `Backup`, `Restore`, or `ResetDefaults`.
- `-Preset`: `1` (Conservative), `2` (Medium), `3` (Higher risk).
- `-TeamSpeakPort`, `-CS2PortStart`, `-CS2PortEnd`: port ranges for DSCP policies.
- `-IncludeAppPolicies`, `-AppPaths`: optional app-based QoS policies.
- `-AfdThreshold`: AFD `FastSendDatagramThreshold` (preset 2+).
- `-PowerPlan`: `None`, `HighPerformance`, or `Ultimate`.
- `-DisableGameDvr`, `-DisableUro`: optional toggles.
- `-BackupFolder`: backup location (default under `ProgramData`).
- `-DryRun`: preview only, no system changes.

## Usage
- Apply: run elevated PowerShell and invoke the script with a preset; optional per‑session execution policy may be set for convenience.
- Backup/Restore: use the script’s Backup and Restore actions to snapshot and revert registry/QoS/NIC/power plan states.

Examples:
- Apply preset 1 (safe default) on a client endpoint.
- Apply preset 2 where CPU headroom exists and lower latency is needed.
- Apply preset 3 only after measuring benefits and understanding CPU impacts.

## Verification
- QoS policies: `Get‑NetQosPolicy` in `ActiveStore/PersistentStore` to confirm policies exist and match intended ports/apps.
- NIC advanced properties: `Get‑/Set‑NetAdapterAdvancedProperty` to verify EEE/Interrupt Moderation/Flow/Jumbo states per adapter.
- Netsh trace/diagnostics: use `netsh` capabilities to record networking traces if deeper analysis is required.

## Rollback
- The script restores MMCSS/AFD registry from .reg snapshots, re‑creates QoS from inventory, restores NIC advanced settings and RSC state, and switches back to the saved power plan.
- A reboot may be needed for registry settings to fully re‑apply, particularly AFD/MMCSS changes.

## Validation (build / run / test)

All commands are run from the repository root. Tests and lint are offline and do not change the system.

| Command | Description |
|--------|-------------|
| **Lint** | `pwsh -NoProfile -Command 'Install-Module PSScriptAnalyzer -Scope CurrentUser -Force; Invoke-ScriptAnalyzer -Path . -Recurse'` |
| **Tests** | `pwsh -NoProfile -Command 'Install-Module Pester -Scope CurrentUser -Force; Invoke-Pester -Path ./tests -CI'` |
| **Full CI** | `./scripts/ci-local.sh` (same as GitHub Actions) |
| **Run (dry run)** | `pwsh -NoProfile -ExecutionPolicy Bypass -File ./optimize-udp-jitter.ps1 -Action Apply -Preset 1 -DryRun` |

There is no build step; the module is loaded directly from source. See `CONTRIBUTING.md` for prerequisites and `docs/BUGS-AND-FIXES.md` for known issues and required fixes.

## CI
GitHub Actions runs PSScriptAnalyzer and Pester on `push` and `pull_request`.

## Security
- Do not include secrets, tokens, or sensitive system data in issues or logs.
- Report security concerns via a GitHub issue with minimal, non-sensitive details.
- See `SECURITY.md` for the full security policy.

## Troubleshooting
- Module import fails: ensure PowerShell 7+ and run from repo root.
- ScriptAnalyzer warnings: run with `-Recurse` from repo root to match CI.
- Pester failures on non-Windows: tests must remain offline; mock or skip Windows-only cmdlets.

## Safety note:
- Changes are mostly reversible via the built‑in backup/restore workflow; always test under representative load, and use change control on servers. Use at your own risk.
