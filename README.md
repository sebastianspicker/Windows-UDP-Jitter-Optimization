# UDP Jitter Optimization for Windows 10/11
Safe defaults with tiered risk levels and full backup/restore workflow for real‑time UDP workloads (e.g., CS2, TeamSpeak).[2]

- Focus: outbound DSCP marking via Windows QoS Policies plus conservative NIC/stack tuning for lower latency variance.[1][2]
- Presets: 1=Conservative, 2=Medium, 3=Higher risk, each with explicit CPU/compatibility trade‑offs and full failsafe backups.[2]

## Scope: Client vs. Server
- Client endpoints: apply endpoint DSCP policies, enable local QoS, and selectively adjust NIC energy/latency features to stabilize voice/game traffic on Windows 10/11.[3][1][2]
- Server endpoints: use the same Windows QoS mechanisms but consider data‑center NIC tuning guidance and platform vendor docs; verify that network devices honor DSCP and align server NIC features with low‑latency guidance.[4][1][2]

## What the script changes
- QoS (endpoint DSCP EF=46): creates port‑based policies in PersistentStore for CS2/TeamSpeak and optionally app‑based policies, with idempotent removal/re‑create logic.[1]
- Enable local QoS on non‑domain machines: sets “Do not use NLA” so DSCP isn’t cleared by NLA contexts, consistent with Microsoft QoS guidance.[3]
- MMCSS audio safety: ensures SystemProfile\Tasks\Audio exists with stable defaults and starts core audio services to avoid silent audio failures.[5][6]
- NIC tuning per preset: disables Energy Efficient Ethernet by default; reduces interrupt moderation and disables flow/green/power‑saving/jumbo at preset 2; adds RSC/offload/ITR toggles at preset 3, with CPU‑cost warnings.[7][2]
- AFD threshold (conservative): sets FastSendDatagramThreshold=1500 to align with MTU‑sized UDP datagrams, avoiding overly aggressive global thresholds.[8]
- Full backup/restore: exports MMCSS/AFD registry, inventories QoS policies, snapshots NIC advanced properties and RSC status, and saves the active power plan for rollback.[9][10][1]

## Presets and trade‑offs
- Preset 1 (Conservative, default)  
  - Client: protect MMCSS audio; enable local QoS; add DSCP EF policies for CS2/TS; disable EEE if supported.[6][5][2][3][1]
  - Server: same QoS approach; leave advanced NIC offloads/moderation intact unless measured issues exist, per Microsoft server tuning guidance.[2]
- Preset 2 (Medium)  
  - Client: reduce/disable interrupt moderation, disable flow control/green/power‑saving/jumbo, set AFD FastSendDatagramThreshold=1500 (reboot recommended).[11][8][2]
  - Server: evaluate per‑workload; flow control/interrupt moderation changes can affect throughput under congestion, so test under realistic load.[2]
- Preset 3 (Higher risk)  
  - Client: optional RSC off, LSO/checksum offloads off, ARP/NS/WoL off, ITR=0 if exposed, optional SystemResponsiveness=0 and NetworkThrottlingIndex=FFFFFFFF, and optional URO disable via netsh.[12][13][5][7][2]
  - Server: only apply with clear measurements and change control; these may raise CPU/ISR/DPC and affect scalability on busy hosts.[2]

Notes:
- DSCP is outbound marking; end‑to‑end benefit requires that intermediate devices honor DSCP, which is common in enterprise/provider QoS designs.[3][1]
- Reducing moderation/turning off offloads/RSC/URO can lower jitter but increases CPU; always measure before and after.[7][12][2]

## Client guidance (Windows 10/11)
- Use New‑NetQosPolicy to DSCP‑mark voice/game ports in PersistentStore; verify with Get‑NetQosPolicy that policies are active.[14][1]
- Enable local QoS (“Do not use NLA”) so DSCP tags persist on non‑domain machines per Microsoft guidance.[3]
- Disable Energy Efficient Ethernet (EEE) where supported and consider lowering interrupt moderation if CPU headroom exists.[2]
- Keep offloads enabled by default; only disable in preset 3 for driver‑specific issues after measurement.[2]

## Server guidance (Windows Server)
- Apply QoS marking with the same PowerShell cmdlets; domain GPOs can centralize QoS if desired, using Microsoft’s QoS port range guidance as a model.[1][3]
- Tune NICs following Microsoft’s server networking tuning guidance; prioritize RSS/RSC/offload usage unless profiling shows latency spikes.[2]
- Validate DC/ToR/edge policies to ensure DSCP EF is recognized and mapped to a low‑latency queue across the path, per common provider QoS practice.[15]

## Requirements
- Windows 10/11 with administrative privileges; PowerShell can apply QoS in PersistentStore without RSAT on clients.[1]
- Reboot recommended after AFD/MMCSS registry changes for full effect; DSCP policy and NIC changes apply immediately.[5][8]

## Usage
- Apply: run elevated PowerShell and invoke the script with a preset; optional per‑session execution policy may be set for convenience.[16][1]
- Backup/Restore: use the script’s Backup and Restore actions to snapshot and revert registry/QoS/NIC/power plan states.[1]

Examples:
- Apply preset 1 (safe default) on a client endpoint.[2]
- Apply preset 2 where CPU headroom exists and lower latency is needed.[2]
- Apply preset 3 only after measuring benefits and understanding CPU impacts.[2]

## Verification
- QoS policies: Get‑NetQosPolicy in ActiveStore/PersistentStore to confirm policies exist and match intended ports/apps.[14]
- NIC advanced properties: Get‑/Set‑NetAdapterAdvancedProperty to verify EEE/Interrupt Moderation/Flow/Jumbo states per adapter.[10]
- Netsh trace/diagnostics: use netsh capabilities to record networking traces if deeper analysis is required.[17]

## Rollback
- The script restores MMCSS/AFD registry from .reg snapshots, re‑creates QoS from inventory, restores NIC advanced settings and RSC state, and switches back to the saved power plan.[9][10][1]
- A reboot may be needed for registry settings to fully re‑apply, particularly AFD/MMCSS changes.[8][5]

## Enterprise and provider references
- Microsoft: Network Adapter Performance Tuning in Windows (EEE, interrupt moderation, offloads, low‑latency considerations).[2]
- Microsoft: NetQos module (New‑/Set‑/Get‑NetQosPolicy) for DSCP policies on Windows endpoints.[18][14][1]
- Microsoft: QoS for Skype/Teams clients, port ranges and “Do not use NLA” for local DSCP.[3]
- Microsoft: MMCSS fundamentals and scheduling categories, basis for audio safety.[5]
- Microsoft: UDP Receive Segment Coalescing Offload (URO/UDP‑RSC) platform documentation.[13][19]
- Microsoft: RSC management cmdlets for per‑adapter configuration.[7][9]
- Oracle: Coherence performance tuning notes referencing conservative AFD FastSendDatagramThreshold around MTU.[8]
- Cisco: Enabling DSCP QoS tagging on Windows endpoints as part of end‑to‑end QoS design.[15]
- NVIDIA Networking: performance optimization/tuning notes relevant to Windows NICs in low‑latency contexts.[4]
- Dell: advanced property configuration examples for Windows environments.[20]

Safety note:
- Changes are reversible via the built‑in backup/restore workflow; always test under representative load, and use change control on servers.[1][2]

[1](https://learn.microsoft.com/en-us/powershell/module/netqos/new-netqospolicy?view=windowsserver2025-ps)
[2](https://learn.microsoft.com/en-us/windows-server/networking/technologies/network-subsystem/net-sub-performance-tuning-nics)
[3](https://learn.microsoft.com/en-us/skypeforbusiness/manage/network-management/qos/configuring-port-ranges-for-your-skype-clients)
[4](https://docs.nvidia.com/networking/display/WINOFv55054000/General+Performance+Optimization+and+Tuning)
[5](https://learn.microsoft.com/en-us/windows/win32/procthread/multimedia-class-scheduler-service)
[6](https://djdallmann.github.io/GamingPCSetup/CONTENT/RESEARCH/FINDINGS/registrykeys_mmcss.txt)
[7](https://learn.microsoft.com/en-us/powershell/module/netadapter/disable-netadapterrsc?view=windowsserver2025-ps)
[8](https://docs.oracle.com/en/middleware/fusion-middleware/coherence/12.2.1.4/administer/performance-tuning.html)
[9](https://learn.microsoft.com/en-us/powershell/module/netadapter/get-netadapterrsc?view=windowsserver2025-ps)
[10](https://learn.microsoft.com/en-us/powershell/module/netadapter/set-netadapteradvancedproperty?view=windowsserver2025-ps)
[11](https://learn.microsoft.com/en-us/windows-server/networking/technologies/hpn/hpn-hardware-only-features)
[12](https://microsoft.github.io/msquic/msquicdocs/docs/TSG.html)
[13](https://learn.microsoft.com/en-us/windows-hardware/drivers/network/udp-rsc-offload)
[14](https://learn.microsoft.com/en-us/powershell/module/netqos/get-netqospolicy?view=windowsserver2025-ps)
[15](https://www.cisco.com/c/en/us/support/docs/quality-of-service-qos/qos-configuration-monitoring/221868-enable-dscp-qos-tagging-on-windows-machi.html)
[16](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.security/set-executionpolicy?view=powershell-7.5)
[17](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/netsh)
[18](https://learn.microsoft.com/en-us/powershell/module/netqos/set-netqospolicy?view=windowsserver2025-ps)
[19](https://learn.microsoft.com/de-de/windows-hardware/drivers/network/udp-rsc-offload)
[20](https://www.dell.com/support/manuals/en-us/ax-760/ashci_scalable_deployment_option_guide_windows/update-network-adapter-advanced-properties?guid=guid-a3d86927-f96d-416a-bb62-44ec26dd45fa&lang=en-us)
