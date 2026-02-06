# CI

## Überblick
Der Workflow `CI` führt statische Analyse und Tests aus.
- Workflow-Datei: `.github/workflows/ci.yml`
- Trigger: `push`, `pull_request`
- Jobs: PowerShell Checks auf `ubuntu-latest` und `windows-latest`
- Checks: PSScriptAnalyzer + Pester

## Lokal ausführen
Empfohlen:
- `./scripts/ci-local.sh`

Alternativ (direkt in PowerShell):
- `pwsh -NoProfile -NonInteractive -File ./scripts/ci.ps1`

Hinweis: Das Script installiert fehlende Module (PSScriptAnalyzer/Pester) in `CurrentUser` und nutzt PSGallery.

## Caching
CI cached PowerShell-Module in den Standardpfaden der Runner.
- Ubuntu: `~/.local/share/powershell/Modules`
- Windows: `C:\Users\runneradmin\Documents\PowerShell\Modules`

Wenn Modulversionen geändert werden, muss der Cache-Key in `.github/workflows/ci.yml` angepasst werden.

## Secrets
Aktuell werden keine Secrets verwendet.

## CI erweitern
- Neue Checks in `scripts/ci.ps1` ergänzen.
- Cache-Key aktualisieren, wenn zusätzliche Module oder Versionen hinzukommen.
- Für secret-requiring Jobs separate Workflows anlegen (nur `push` auf `main` oder `workflow_dispatch`).
