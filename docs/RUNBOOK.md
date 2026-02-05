# RUNBOOK

This repo is a PowerShell 7+ module + wrapper script for Windows UDP jitter tuning. The module is Windows-specific, but tests run offline (no registry/NIC changes).

## Setup

Prereqs:
- PowerShell 7+

Install dev modules (current user only):

```powershell
pwsh -NoProfile -Command 'Install-Module PSScriptAnalyzer,Pester -Scope CurrentUser -Force'
```

## Fast Loop (recommended before every PR)

```powershell
pwsh -NoProfile -Command 'Invoke-ScriptAnalyzer -Path . -Recurse'
pwsh -NoProfile -Command 'Invoke-Pester -Path ./tests -CI'
```

## Full Loop

Same as Fast Loop (no build step defined in this repo).

## Lint / Static checks (SAST)

```powershell
pwsh -NoProfile -Command 'Invoke-ScriptAnalyzer -Path . -Recurse'
```

## Tests

```powershell
pwsh -NoProfile -Command 'Invoke-Pester -Path ./tests -CI'
```

## Build

No build step defined. The module is loaded directly from source.

## Security Minimum

Secret scan (lightweight, manual):

```powershell
pwsh -NoProfile -Command "git grep -n -i -E 'password|secret|token|apikey|api_key|private_key|client_secret'"
```

SAST:

```powershell
pwsh -NoProfile -Command 'Invoke-ScriptAnalyzer -Path . -Recurse'
```

SCA / dependencies:
- No dependency manifest/lockfile is present. Current dev dependencies are PowerShell Gallery modules `PSScriptAnalyzer` and `Pester` (installed in CI and locally as needed).
- If a manifest is introduced (e.g., `RequiredModules` in the `.psd1`), add an SCA step here.

## Troubleshooting

- Module import fails: verify PowerShell 7+ and run from repo root.
- Pester fails on non-Windows: tests should remain offline. If a test touches Windows-only cmdlets, mark it with `-Skip` or mock the cmdlet.
- ScriptAnalyzer warnings: run with `-Recurse` from repo root to match CI.

