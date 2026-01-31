function Test-UjIsAdministrator {
  [CmdletBinding()]
  [OutputType([bool])]
  param()

  try {
    $principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  } catch {
    Write-Verbose -Message 'Admin check failed (non-Windows or restricted platform).'
    return $false
  }
}

function Assert-UjAdministrator {
  [CmdletBinding()]
  param()

  if (-not (Test-UjIsAdministrator)) {
    throw 'Please run as Administrator.'
  }
}
