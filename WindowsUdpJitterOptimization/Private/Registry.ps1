function Export-UjRegistryKey {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$RegistryPath,

    [Parameter(Mandatory)]
    [string]$OutFile
  )

  try {
    & reg.exe export $RegistryPath $OutFile /y | Out-Null
  } catch {
    Write-Verbose -Message ("Registry export failed: {0}" -f $RegistryPath)
  }
}

function Import-UjRegistryFile {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$InFile
  )

  if (-not (Test-Path -Path $InFile)) {
    return
  }

  try {
    & reg.exe import $InFile | Out-Null
  } catch {
    Write-Warning -Message ("Registry import failed: {0}" -f $InFile)
  }
}

function Set-UjRegistryValue {
  [CmdletBinding(SupportsShouldProcess = $true)]
  param(
    [Parameter(Mandatory)]
    [string]$Key,

    [Parameter(Mandatory)]
    [string]$Name,

    [Parameter(Mandatory)]
    [ValidateSet('DWord', 'String')]
    [string]$Type,

    [Parameter(Mandatory)]
    [AllowNull()]
    $Value
  )

  if (-not (Test-Path -Path $Key)) {
    if ($PSCmdlet.ShouldProcess($Key, 'Create registry key')) {
      New-Item -Path $Key -Force | Out-Null
    }
  }

  if (-not $PSCmdlet.ShouldProcess(("{0}\\{1}" -f $Key, $Name), ("Set registry value ({0})" -f $Type))) {
    return
  }

  if ($Type -eq 'DWord') {
    New-ItemProperty -Path $Key -Name $Name -PropertyType DWord -Value ([int]$Value) -Force | Out-Null
    return
  }

  New-ItemProperty -Path $Key -Name $Name -PropertyType String -Value ([string]$Value) -Force | Out-Null
}

