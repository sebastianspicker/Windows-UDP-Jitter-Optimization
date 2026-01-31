function Write-UjInformation {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$Message
  )

  Write-Information -MessageData $Message -InformationAction Continue
}

