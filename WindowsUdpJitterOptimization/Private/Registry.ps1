function Export-UjRegistryKey {
  [CmdletBinding()]
  [OutputType([bool])]
  param(
    [Parameter(Mandatory)]
    [string]$RegistryPath,

    [Parameter(Mandatory)]
    [string]$OutFile
  )

  try {
    $outDir = Split-Path -Path $OutFile -Parent
    if ($outDir -and -not (Test-Path -Path $outDir)) {
      New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }

    $result = & reg.exe export $RegistryPath $OutFile /y 2>&1
    if ($LASTEXITCODE -ne 0) {
      Write-Warning -Message ("Registry export failed for {0} (exit code {1}): {2}" -f $RegistryPath, $LASTEXITCODE, ($result -join ' '))
      return $false
    }
    return $true
  } catch {
    Write-Warning -Message ("Registry export failed: {0} - {1}" -f $RegistryPath, $_.Exception.Message)
    return $false
  }
}

function Import-UjRegistryFile {
  [CmdletBinding()]
  [OutputType([bool])]
  param(
    [Parameter(Mandatory)]
    [string]$InFile
  )

  if (-not (Test-Path -Path $InFile)) {
    Write-Warning -Message ("Registry import skipped: file not found '{0}'." -f $InFile)
    return $false
  }

  try {
    $null = & reg.exe import $InFile 2>&1
    if ($LASTEXITCODE -ne 0) {
      Write-Warning -Message ("Registry import failed for {0} (reg.exe exited with {1})." -f $InFile, $LASTEXITCODE)
      return $false
    }
    return $true
  } catch {
    Write-Warning -Message ("Registry import failed: {0} - {1}" -f $InFile, $_.Exception.Message)
    return $false
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

  if (-not $PSCmdlet.ShouldProcess((Join-Path -Path $Key -ChildPath $Name), ("Set registry value ({0})" -f $Type))) {
    return
  }

  if ($Type -eq 'DWord') {
    New-ItemProperty -Path $Key -Name $Name -PropertyType DWord -Value ([int]$Value) -Force | Out-Null
    return
  }

  New-ItemProperty -Path $Key -Name $Name -PropertyType String -Value ([string]$Value) -Force | Out-Null
}

