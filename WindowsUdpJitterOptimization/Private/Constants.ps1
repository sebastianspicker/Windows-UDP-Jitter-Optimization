# Central constants for registry paths (reg.exe vs PowerShell provider), backup file names, and defaults.
# Dot-sourced first by the module so all Private/Public scripts can reference them.

# Registry paths for PowerShell provider (with colon)
$script:UjRegistryPathSystemProfile = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
$script:UjRegistryPathAfdParameters = 'HKLM:\SYSTEM\CurrentControlSet\Services\AFD\Parameters'
$script:UjRegistryPathQos = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\QoS'

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

# NIC advanced property display names that this module may set (used for reset-only-these in ResetDefaults)
$script:UjNicResetDisplayNames = @(
  'Energy Efficient Ethernet',
  'Interrupt Moderation',
  'Flow Control',
  'Green Ethernet',
  'Power Saving Mode',
  'Jumbo Packet',
  'Large Send Offload v2 (IPv4)',
  'Large Send Offload v2 (IPv6)',
  'UDP Checksum Offload (IPv4)',
  'UDP Checksum Offload (IPv6)',
  'TCP Checksum Offload (IPv4)',
  'TCP Checksum Offload (IPv6)',
  'ARP Offload',
  'NS Offload',
  'Wake on Magic Packet',
  'Wake on pattern match',
  'WOL & Shutdown Link Speed',
  'ITR',
  'Receive Buffers',
  'Transmit Buffers'
)

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
}
