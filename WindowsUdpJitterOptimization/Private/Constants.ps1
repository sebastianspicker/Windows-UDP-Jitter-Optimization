# Central constants for registry paths (reg.exe vs PowerShell provider), backup file names, and defaults.
# Dot-sourced first by the module so all Private/Public scripts can reference them.

# Registry paths for PowerShell provider (with colon)
$script:UjRegistryPathSystemProfile = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
$script:UjRegistryPathAfdParameters = 'HKLM:\SYSTEM\CurrentControlSet\Services\AFD\Parameters'
$script:UjRegistryPathQos = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\QoS'

# Default backup folder (single source of truth; CLI/GUI use this or Get-UjDefaultBackupFolder)
# On non-Windows (e.g. tests on macOS) avoid C: drive so Join-Path does not fail
$script:UjDefaultBackupFolderBase = if ([string]::IsNullOrWhiteSpace($env:ProgramData)) {
  if ($env:OS -eq 'Windows_NT') { 'C:\ProgramData' } else { [System.IO.Path]::GetTempPath().TrimEnd([System.IO.Path]::DirectorySeparatorChar) }
} else {
  $env:ProgramData
}
$script:UjDefaultBackupFolder = Join-Path -Path $script:UjDefaultBackupFolderBase -ChildPath 'UDPTune'

# Backup file names (child names under BackupFolder)
$script:UjBackupFileManifest = 'backup_manifest.json'
$script:UjBackupFileSystemProfile = 'SystemProfile.reg'
$script:UjBackupFileAfdParameters = 'AFD_Parameters.reg'
$script:UjBackupFileQosOurs = 'qos_ours.xml'
$script:UjBackupFileNicAdvanced = 'nic_advanced_backup.csv'
$script:UjBackupFileRsc = 'rsc_backup.csv'
$script:UjBackupFilePowerplan = 'powerplan.txt'

# Default DSCP value for QoS policies (EF / Expedited Forwarding)
$script:UjDefaultDscp = 46

# QoS naming ownership boundaries managed by this module.
# Only these prefixes are treated as removable/restorable managed policies.
$script:UjManagedQosNamePrefixes = @('QoS_UDP_TS_', 'QoS_UDP_CS2_', 'QoS_APP_')

# Maximum number of per-port QoS policies (cap for large port ranges)
$script:UjMaxPortPolicies = 100

# Standardized Registry Keywords (Microsoft specification) for NIC properties.
# These are locale-independent and driver-agnostic.
$script:UjNicKeywordMap = @{
  'Energy Efficient Ethernet'      = '*EEE'
  'Interrupt Moderation'           = '*InterruptModeration'
  'Flow Control'                   = '*FlowControl'
  'Jumbo Packet'                   = '*JumboPacket'
  'Large Send Offload v2 (IPv4)'   = '*LsoV2IPv4'
  'Large Send Offload v2 (IPv6)'   = '*LsoV2IPv6'
  'UDP Checksum Offload (IPv4)'    = '*UDPChecksumOffloadIPv4'
  'UDP Checksum Offload (IPv6)'    = '*UDPChecksumOffloadIPv6'
  'TCP Checksum Offload (IPv4)'    = '*TCPChecksumOffloadIPv4'
  'TCP Checksum Offload (IPv6)'    = '*TCPChecksumOffloadIPv6'
  'ARP Offload'                    = '*ARPOffload'
  'NS Offload'                     = '*NSOffload'
  'Wake on Magic Packet'           = '*WakeOnMagicPacket'
  'Wake on pattern match'          = '*WakeOnPattern'
  'ITR'                            = '*InterruptModerationRate'
  'Receive Buffers'                = '*ReceiveBuffers'
  'Transmit Buffers'               = '*TransmitBuffers'
  # P2-2 Fix: Add missing keywords for Green Ethernet, Power Saving Mode, WOL & Shutdown Link Speed
  'Green Ethernet'                 = '*GreenEthernet'
  'Power Saving Mode'              = '*PowerSavingMode'
  'WOL & Shutdown Link Speed'      = '*WakeOnLink'
}

# P2-3 Fix: Keywords for reset operations (locale-independent)
$script:UjNicResetKeywords = @(
  '*EEE', '*InterruptModeration', '*FlowControl', '*GreenEthernet', '*PowerSavingMode',
  '*JumboPacket', '*LsoV2IPv4', '*LsoV2IPv6', '*UDPChecksumOffloadIPv4', '*UDPChecksumOffloadIPv6',
  '*TCPChecksumOffloadIPv4', '*TCPChecksumOffloadIPv6', '*ARPOffload', '*NSOffload',
  '*WakeOnMagicPacket', '*WakeOnPattern', '*WakeOnLink', '*InterruptModerationRate',
  '*ReceiveBuffers', '*TransmitBuffers'
)
