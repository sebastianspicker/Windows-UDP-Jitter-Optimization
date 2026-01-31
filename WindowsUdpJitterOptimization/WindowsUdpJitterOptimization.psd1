@{
  RootModule        = 'WindowsUdpJitterOptimization.psm1'
  ModuleVersion     = '1.0.0'
  GUID              = 'd73b26e7-18cb-49c7-9af3-f5d8fd6fa34c'
  Author            = 'Sebastian J. Spicker'
  CompanyName       = ''
  Copyright         = ''
  Description       = 'UDP jitter optimization for Windows 10/11 with backup/restore workflow.'
  PowerShellVersion = '7.0'
  FunctionsToExport = @('Invoke-UdpJitterOptimization')
  CmdletsToExport   = @()
  VariablesToExport = @()
  AliasesToExport   = @()
  PrivateData       = @{
    PSData = @{
      Tags       = @('Windows', 'Networking', 'QoS', 'UDP', 'Latency')
      LicenseUri = ''
      ProjectUri = ''
    }
  }
}

