# REPO MAP

## Structure
- `optimize-udp-jitter.ps1`: Thin wrapper script that imports the module and calls `Invoke-UdpJitterOptimization`.
- `WindowsUdpJitterOptimization/WindowsUdpJitterOptimization.psm1`: Module loader (dot-sources `Public/` and `Private/`).
- `WindowsUdpJitterOptimization/WindowsUdpJitterOptimization.psd1`: Module manifest.
- `WindowsUdpJitterOptimization/Public/Invoke-UdpJitterOptimization.ps1`: Public entry point.
- `WindowsUdpJitterOptimization/Private/`: Internal helpers for QoS, NIC tuning, registry, logging, platform checks, and actions.
- `deprecated/`: Deprecated wrappers for backward compatibility.
- `tests/WindowsUdpJitterOptimization.Tests.ps1`: Offline Pester tests.

## Entry Points
- Script: `optimize-udp-jitter.ps1`.
- Module: `Invoke-UdpJitterOptimization`.

## Key Flows
1) Apply preset
- `Invoke-UdpJitterOptimization`:
  - admin check (unless `-SkipAdminCheck`)
  - backup state (`Backup-UjState`)
  - configure MMCSS audio safety + start services
  - enable local QoS marking
  - create QoS policies by port/app
  - NIC tuning (`Set-UjNicConfiguration`)
  - AFD threshold + undocumented MMCSS tuning
  - optional URO disable, power plan change, Game DVR toggle
  - summary output

2) Backup/Restore
- `Backup-UjState`: exports registry keys, QoS policy inventory, NIC advanced properties, RSC state, power plan.
- `Restore-UjState`: re-imports registry, re-creates QoS policies, restores NIC properties/RSC, and power plan.

3) Reset Defaults
- `Reset-UjBaseline`: resets registry tweaks, NIC properties, QoS policies, and common netsh TCP/UDP settings.

## Data/State
- Registry keys: MMCSS (`SystemProfile`), AFD parameters, QoS NLA settings.
- QoS policies: NetQosPolicy in local store, names prefixed with `QoS_`.
- NIC settings: adapter advanced properties + RSC settings.
- Power plan: active scheme GUID.

## Hotspots / Risk Areas
- `Private/Actions.ps1`: high-impact system changes, registry and netsh modifications.
- `Private/Nic.ps1`: adapter-specific property toggles and RSC changes.
- `Private/Qos.ps1`: policy create/remove logic and naming.

## Tests
- `tests/WindowsUdpJitterOptimization.Tests.ps1`: validates module import, deprecated wrapper behavior, and forbids `Invoke-Expression`.

