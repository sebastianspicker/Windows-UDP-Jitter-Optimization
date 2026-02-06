# CI-Entscheidung

Datum: 2026-02-06

## Entscheidung
FULL CI (Static Checks + Tests).

## Begründung
- Repo enthält ausführbaren PowerShell-Code (Script + Modul), daher klarer Nutzen durch Linting und Tests.
- Tests laufen offline (keine Systemänderungen), sind schnell und deterministisch.
- Keine Secrets und keine Live-Infrastruktur erforderlich.
- Aufwand ist niedrig, Nutzen hoch.

## Umfang der Checks
- `push` + `pull_request`: PSScriptAnalyzer und Pester auf `ubuntu-latest` und `windows-latest`.
- Keine Deploy- oder Live-Infra-Jobs.
- Keine nightly Jobs notwendig, da die Checks schnell sind.

## Threat-Model (CI)
- Fork-PRs sind untrusted: Workflow nutzt `pull_request`, keine Secrets, minimale `permissions` (`contents: read`).
- Kein `pull_request_target` und keine write-Scope Aktionen.
- Supply-Chain-Risiko durch PSGallery: Versions-Pinning + Caching, optional später internes Mirror/PSRepository.

## Upgrade-Pfad zu „erweiterter“ CI
Falls später echte Integrations-/Systemtests nötig sind:
- Self-hosted Windows Runner mit Admin-Rechten (oder dedizierte Test-VMs).
- Separate Workflows für `push` auf `main` oder `workflow_dispatch` mit Secrets.
- Strikte Trennung zwischen untrusted PR Checks und secret-requiring Jobs.
