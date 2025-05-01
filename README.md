# UDP Jitter Reduction for Windows

This repository provides two PowerShell scripts:

1. **`optimize-udp-jitter.ps1`**: Applies a comprehensive set of client-side tweaks to minimize UDP jitter and improve latency for gaming (Counter-Strike 2) and VoIP (TeamSpeak 3) on Windows 10/11.
2. **`reset-udp-jitter.ps1`**: Reverts all changes applied by the optimization script, restoring Windows to its default network settings.

## Table of Contents

- [Background & Motivation](#background--motivation)
- [Features & Tweaks](#features--tweaks)
  - [A. System & Registry Tweaks](#a-system--registry-tweaks)
  - [B. NIC Advanced Settings](#b-nic-advanced-settings)
  - [C. QoS Policies](#c-qos-policies)
  - [D. TCP/IP Stack & Netsh Tweaks](#d-tcpip-stack--netsh-tweaks)
  - [E. Optional: NDU Service](#e-optional-ndu-service)
- [Prerequisites](#prerequisites)
- [Usage](#usage)
- [Testing & Verification](#testing--verification)
- [Reset Script](#reset-script)
- [FAQ](#faq)

## Background & Motivation

Modern Windows installs include features that, while optimizing for throughput and multimedia workloads, can introduce variability (jitter) in packet transmission—detrimental for real-time applications like online gaming and VoIP. This project combines:

- Community-verified tweaks (SpeedGuide, Reddit, StackOverflow)
- Microsoft documentation on network throttling and TCP internals
- Hardware vendor recommendations (Intel, Broadcom)

into a single, idempotent PowerShell script that:

- Removes OS-imposed limits on packet processing
- Tunes network interface hardware parameters
- Prioritizes real-time UDP traffic via DSCP
- Fine‑tunes the TCP/IP stack for coexisting TCP flows

## Features & Tweaks

### A. System & Registry Tweaks

1. **High Performance Power Plan**  
   Ensures CPU and system devices remain at peak performance.
2. **Disable Network Throttling** (`NetworkThrottlingIndex = 0xFFFFFFFF`)  
   Removes Windows’ built‑in limit on network packet processing rates.
3. **Multimedia Scheduler** (`SystemResponsiveness = 0`)  
   Reserves 0% CPU for background tasks when multimedia apps are active.
4. **UDP FastSendDatagramThreshold** (`0xFFFF`)  
   Increases the threshold for the fast I/O path to 64 KB, avoiding delays on packets >1 KB.
5. **Optional Game DVR/Game Bar Disable**  
   Stops background game capture services to eliminate additional overhead.

### B. NIC Advanced Settings

Applies per‑adapter advanced property changes (via `Get-/Set-NetAdapterAdvancedProperty`), including:

- **Disable RSC (Receive Segment Coalescing)**
- **Disable Interrupt Moderation** & set **ITR** to 0
- **Disable Flow Control**
- **Disable Energy‑Efficient Ethernet**, **Green Ethernet**, **Power Saving Mode**
- **Disable LSO v2** (Large Send Offload) for IPv4 & IPv6
- **Disable TCP/UDP Checksum Offload**
- **Disable Jumbo Packet support**
- **Disable ARP/NS Offload**
- **Disable Wake-on-LAN** features
- **Set ReceiveBuffers & TransmitBuffers** to 256

These changes force the NIC to deliver each packet immediately at the cost of slightly higher CPU usage.

### C. QoS Policies

Creates and removes QoS policies in the **PersistentStore** to tag UDP traffic with DSCP=46 (EF) for both:

- **Local** (incoming) ports 27015–27036 & 9987
- **Remote** (outgoing) ports 27015–27036 & 9987

Also disables Network Location Awareness enforcement (`Do not use NLA = 1`) so local QoS applies on non‑domain PCs. Optionally adds generic policies:

- **HighPriority_TeamSpeak** (UDP 9987)
- **HighPriority_Game** (UDP 27015–27036)

### D. TCP/IP Stack & Netsh Tweaks

Uses `netsh` and `Set-NetTCPSetting` to:

- **Disable TCP Auto-Tuning** (Window Scaling = disabled)
- **Disable Teredo** IPv6 tunneling
- **Disable UDP Receive Offload** (URO)
- **Supplemental TCP settings**:
  - Initial Congestion Window (`icw=10`)
  - Minimum RTO (`minrto=300`ms)
  - Delayed ACK timeout (`40`ms) & frequency (`2`)
  - RACK & TLP **enabled**
  - PRR & HyStart **disabled**
- **Set TCP profile** to use **CTCP** and enable **ECN** if supported

These ensure TCP flows coexist nicely without starving UDP real‑time traffic.

### E. (Optional) NDU Service

Disables the Network Data Usage service (`NDU`) to eliminate its potential memory and CPU overhead. This is commented out by default.

## Prerequisites

- **Windows 10 or 11** (PowerShell 3.0+)
- **Administrator** rights
- **Reboot** after running the optimization script

## Usage

1. Open an elevated PowerShell prompt.
2. Run:  
   ```powershell
   Set-ExecutionPolicy RemoteSigned -Scope Process
   .\optimize-udp-jitter.ps1
   ```
3. Reboot your system to apply all registry and AFD changes.

To revert to defaults:

```powershell
.\reset-udp-jitter.ps1
# then reboot
```

## Testing & Verification

- **PingPlotter**, **psping**, or **WinMTR** to measure jitter before/after.  
- **Wireshark** to inspect DSCP tags in UDP packets.  
- **Task Manager → Performance → Networking** to verify no unusual CPU spikes on NIC drivers.

## Reset Script

The `reset-udp-jitter.ps1` script performs the inverse of each tweak, restoring:

- Balanced power plan
- Default registry values and MMCSS keys
- Game DVR/Game Bar
- NIC advanced properties & RSC
- QoS policies & NLA enforcement
- CPU/NIC offload defaults & netsh settings
- CTCP = NewReno & ECN Disabled
- (Optional) NDU service to automatic start

Always reboot after running the reset script.

## FAQ

**Q: Will these tweaks break non‑gaming traffic?**  
A: Most settings improve latency at the cost of marginal CPU usage. Throughput‑heavy workloads (large file transfers) may see slightly lower max bandwidth but minimal effect in typical home/gaming use.

**Q: My router ignores DSCP.**  
A: DSCP priority only helps if upstream devices honor it. Without router QoS you might not see DSCP improvements, but all other tweaks still reduce local jitter.

**Q: Can I tweak settings incrementally?**  
A: Yes. You can comment out sections of the script to test individual changes (e.g., only NIC settings or only registry tweaks).

## Manual Device Manager Settings for ASUS XG-C100C V2

For optimal performance and minimal UDP jitter, the following **manual** adjustments in the Windows Device Manager are recommended specifically for the ASUS XG-C100C V2 adapter:

1. **Speed & Duplex**  
   - **Path:** Device Manager → Network Adapters → ASUS XG-C100C V2 → Properties → Advanced → **Speed & Duplex**
   - **Value:** `10 Gbps Full Duplex`
   - **Benefit:** Locks the adapter to 10 Gbps and prevents auto-negotiation downshifts or renegotiations that can introduce transient latency spikes.

2. **Energy-Efficient Ethernet (EEE)**  
   - **Path:** Device Manager → ASUS XG-C100C V2 → Properties → Advanced → **Energy Efficient Ethernet**
   - **Value:** `Disabled`
   - **Benefit:** Disables 802.3az power-saving mode to prevent micro-delays when the link wakes from low-power states.

3. **Interrupt Moderation / Interrupt Moderation Rate**  
   - **Path:** Device Manager → ASUS XG-C100C V2 → Properties → Advanced → **Interrupt Moderation** / **Interrupt Moderation Rate**
   - **Value:** `Disabled` for full disable, or if unavailable, set **Interrupt Moderation Rate** to `Low`
   - **Benefit:** Ensures packets trigger immediate CPU interrupts, reducing buffering delays at the cost of slightly higher CPU load.

4. **Downshift Retries** (if present)  
   - **Path:** Device Manager → ASUS XG-C100C V2 → Properties → Advanced → **Downshift Retries**
   - **Value:** `Disabled`
   - **Benefit:** Prevents the NIC from silently falling back to lower link speeds (5G/2.5G/1G) after transient link errors, ensuring a stable 10 Gbps connection.

5. **Device Power Management**  
   - **Path:** Device Manager → ASUS XG-C100C V2 → Properties → Power Management
   - **Disable:** `Allow the computer to turn off this device to save power`
   - **Benefit:** Prevents Windows from powering down the adapter during low activity, which can cause latency spikes when waking.

6. **PCIe Link State Power Management**  
   - **Path:** Control Panel → Power Options → Change plan settings → Change advanced power settings → PCI Express → **Link State Power Management**
   - **Value:** `Off` or `Maximum Performance`
   - **Benefit:** Ensures the PCIe bus remains fully powered and avoids link power-saving transitions.

Implementing these manual Device Manager tweaks alongside the automated script will deliver the lowest possible UDP latency and jitter on the ASUS XG-C100C V2.
