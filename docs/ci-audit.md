# CI Audit

Datum: 2026-02-06

| Workflow | Failure(s) | Root Cause | Fix Plan | Risiko | Verifikation |
| --- | --- | --- | --- | --- | --- |
| CI | Step "Install dependencies" fehlgeschlagen auf `ubuntu-latest` und `windows-latest` (Runs 2026-01-31, 2026-02-05). | Detail-Logs konnten ohne Admin-Token nicht heruntergeladen werden (403). Wahrscheinlich ist der Fehler im Dependency-Bootstrap (NuGet Provider/PSGallery Registrierung/Scope). | Robustere Bootstrap-Logik in `scripts/ci.ps1` (PSGallery registrieren falls fehlend, NuGet Provider in `CurrentUser` Scope installieren, Versionen pinnen), Caching hinzufügen, Logs verbessern, dann CI erneut laufen lassen. | Niedrig: betrifft nur Tool-Install, keine Produktionsänderung. Wenn PSGallery nicht erreichbar ist, bleibt der Job mit klarer Fehlermeldung stehen. | Lokal `./scripts/ci-local.sh`, anschließend GitHub Actions Run auf `push`/`pull_request`. |
