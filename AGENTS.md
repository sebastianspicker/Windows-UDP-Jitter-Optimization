# Agent instructions (repo-local)

This is a PowerShell 7+ project focused on `*.ps1`, `*.psm1`, `*.psd1`.

## Quality gates (Definition of Done)
- `Invoke-ScriptAnalyzer -Path . -Recurse` is green (no errors; warnings reduced or configured).
- `Invoke-Pester -Path ./tests -CI` is green (tests must run offline without touching the OS).
- Avoid copy/paste duplicates (shared helpers belong in `WindowsUdpJitterOptimization/Private`).
- Keep structure consistent and README includes install/run/test commands.

## Tooling
If modules are missing, install for current user only:

```powershell
Install-Module PSScriptAnalyzer,Pester -Scope CurrentUser -Force
```

Run gates:

```powershell
Invoke-ScriptAnalyzer -Path . -Recurse
Invoke-Pester -Path ./tests -CI
```
