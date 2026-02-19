# Bugs & Required Fixes

List derived from documentation, known limitations, and operations. Each item can be turned into a separate issue.

**Implementation status:** Many items below have been addressed in the codebase (see CHANGELOG.md). This document is retained as an audit reference; for current behavior and remaining limitations, see CHANGELOG and README.

---

## Known Limitations / Bugs

### 1. [Bug] Restore and Reset bypass `-WhatIf` for registry and QoS

**Description:** `Restore-UjState` and `Reset-UjBaseline` declare `SupportsShouldProcess = $true`, but registry imports (`reg.exe import`), QoS policy removal, and (in Reset) QoS/registry removal run without any `$PSCmdlet.ShouldProcess(...)` gate.

**Impact:** Operators using `-WhatIf` or `-Confirm` can still have registry and QoS state modified. Safe preview of restore/reset is not possible.

**Fix:** Gate every state-changing step (Import-UjRegistryFile, Remove-UjManagedQosPolicy, Remove-ItemProperty, Remove-Item for Games key, netsh, etc.) with ShouldProcess; ensure helper `Import-UjRegistryFile` either supports WhatIf or is only called when the caller has already confirmed.

---

### 2. [Bug] Power plan restore regex may not match backup output

**Description:** Restore looks for `{[0-9a-fA-F-]+}` in `powerplan.txt`. Backup writes the raw stdout of `powercfg /GetActiveScheme`, which is not guaranteed to contain braces around the GUID. Restore can silently do nothing.

**Impact:** “Restore power plan” can be a no-op with no warning; system stays on current plan.

**Fix:** Normalize backup output (e.g. extract GUID with a pattern that accepts both braced and unbraced forms) or document exact backup format; in restore, accept both forms and warn if no GUID found.

---

### 3. [Bug] GameDVR: `Set-ItemProperty -Type` will throw

**Description:** `Set-UjGameDvrState` uses `Set-ItemProperty -Path $dvr -Name 'AppCaptureEnabled' -Type DWord -Value $value`. `Set-ItemProperty` does not support a `-Type` parameter; this throws at runtime when `-DisableGameDvr` is used (non–DryRun).

**Impact:** Optimization run terminates when GameDVR toggle is requested; partial apply state possible.

**Fix:** Use `-PropertyType DWord` (or the correct parameter name for the PowerShell version in use) or `New-ItemProperty`/`Set-ItemProperty` without `-Type`. Verify on target PowerShell/Windows versions.

---

### 4. [Bug] Baseline reset wipes all NIC advanced properties

**Description:** `Reset-UjBaseline` uses `Reset-NetAdapterAdvancedProperty -DisplayName '*'`, which resets every advanced property on each adapter, not only those touched by this project. Errors are suppressed with `-ErrorAction SilentlyContinue`.

**Impact:** Vendor- or user-specific NIC settings (VLAN, offloads, etc.) can be reverted; partial failures are silent.

**Fix:** Reset only the properties the module actually sets (e.g. same list as in Set-UjNicConfiguration), or document clearly that “Reset” is “all advanced properties” and add a strong confirmation/warning.

---

### 5. [Bug/Operational] `netsh` failures are not detected

**Description:** All `netsh` invocations (URO, Reset-UjBaseline loop) use `try/catch` and discard output. Most `netsh` failures are reported via exit code, not PowerShell exceptions, so failures are usually invisible.

**Impact:** URO and baseline reset can silently not apply or only partially apply; “success” is misleading.

**Fix:** After each `& netsh ...`, check `$LASTEXITCODE` and treat non-zero as failure (warn or throw); optionally capture stderr for diagnostics.

---

## Required Fixes / Improvements

### 6. [Enhancement] DryRun and BackupFolder for ResetDefaults

**Description:** For `-Action ResetDefaults`, `BackupFolder` is not validated (empty allowed), but `New-UjDirectory -Path $BackupFolder` still runs, so ResetDefaults can create/use an invalid path. Also, `-DryRun` is not passed to Backup/Restore, and directory creation happens even when `-DryRun` is set.

**Fix:** Validate BackupFolder only when the action uses it; skip `New-UjDirectory` for ResetDefaults or when DryRun is true. Pass DryRun into Backup/Restore and respect it (no writes).

---

### 7. [Enhancement] QoS restore: validate before delete; per-policy error handling

**Description:** Restore calls `Remove-UjManagedQosPolicy` before checking that `qos_ours.xml` exists and is parseable. Any failure during policy recreation is caught by a single outer catch with a generic “import/parse failed” message, after policies are already removed.

**Fix:** Check for and optionally validate `qos_ours.xml` before removing policies. Wrap each `New-NetQosPolicy` in per-item try/catch; on failure log policy name and reason, continue or abort with a clear message (e.g. “QoS policy recreation failed”).

---

### 8. [Enhancement] Registry export/import: signal failure to callers

**Description:** `Export-UjRegistryKey` only writes Verbose on `reg.exe export` failure; callers cannot detect incomplete backups. `Import-UjRegistryFile` returns silently when the file is missing and only warns on import failure.

**Fix:** Have export return a success/failure indicator or throw on non-zero exit; have import warn or fail when file is missing, and escalate (warning + return value or throw) when `reg.exe import` fails.

---

### 9. [Operational] Restore reports “complete” despite silent skips

**Description:** Registry, QoS, NIC, RSC, and power plan steps can skip or fail without stopping the function; “Restore complete” is still printed.

**Fix:** Track which phases ran and whether they failed; at the end emit a summary (e.g. “Restore completed with warnings: registry import failed for …; QoS skipped”) or fail the command when critical phases fail.

---

### 10. [Enhancement] Deprecated wrappers: parameters and common params

**Description:** The script `reset-udp-jitter.ps1` was historically deprecated/removed from the repo; only `optimize-udp-jitter.ps1` remains as the main entry point. The root script declares full parameters and forwards `@PSBoundParameters`; for full parity it should also expose `SkipAdminCheck` so module and script behave identically.

**Fix:** Add `SkipAdminCheck` to the root script's param block and pass it through. No separate reset script in repo.

---

## Critical

### 11. [Bug] Restore: Registry import and QoS removal run without ShouldProcess

**Description:** `Restore-UjState` advertises SupportsShouldProcess but runs `Import-UjRegistryFile` and `Remove-UjManagedQosPolicy` with no ShouldProcess check, so `-WhatIf` does not prevent these changes.

**Fix:** Gate registry import and QoS removal (and any other state changes in restore) with `$PSCmdlet.ShouldProcess(...)`; ensure Import-UjRegistryFile is only invoked when the step is confirmed.

---

### 12. [Bug] Reset: QoS and registry removal bypass ShouldProcess

**Description:** `Reset-UjBaseline` uses ShouldProcess for some steps but removes QoS policies and the “Do not use NLA” registry value without ShouldProcess, so `-WhatIf` can still perform those destructive operations.

**Fix:** Call ShouldProcess before `Remove-UjManagedQosPolicy` and before `Remove-ItemProperty` for the QoS key; skip those steps when WhatIf or Confirm is declined.

---

### 13. [Bug] QoS restore: remove-then-recreate can leave zero policies

**Description:** Restore removes all managed QoS policies, then recreates from backup. If import or any New-NetQosPolicy fails, the outer catch logs “QoS restore skipped (import/parse failed)” and continues; the machine can end up with no QoS_* policies.

**Fix:** Validate backup inventory before removal; use per-policy error handling and a clear message when recreation fails; consider not removing policies until at least one policy is successfully recreated (or document the risk).

---

### 14. [Bug] QoS restore: app-based policies skipped when port branch runs first

**Description:** Restore treats any item with `IPPortMatchCondition` property as port-based. If that property exists but value is invalid, the port branch runs and `continue`s, so the app-based branch is never tried even when `AppPathNameMatchCondition` is present.

**Fix:** Only enter the port branch when port value is valid; otherwise fall through to app-based branch if applicable; avoid unconditional `continue` after a failed parse.

---

### 15. [Bug] Power plan restore: GUID regex may not match backup format

**Description:** Restore uses regex `{[0-9a-fA-F-]+}`; if backup output does not contain braces, restore does nothing and does not warn.

**Fix:** Use a pattern that accepts GUID with or without braces; if no GUID found, emit a warning and do not report “Restore complete” for power plan.

---

### 16. [Bug] Set-UjGameDvrState uses invalid parameter and will throw

**Description:** `Set-ItemProperty` is called with `-Type DWord`; that parameter does not exist and causes a terminating error on the non–DryRun path.

**Fix:** Use the correct parameter (e.g. `-PropertyType`) or a different API that sets DWORD values; add a test that runs without DryRun to cover this path.

---

### 17. [Bug] Reset wipes all NIC advanced properties with wildcard

**Description:** `Reset-NetAdapterAdvancedProperty -DisplayName '*'` resets every advanced property, not only those set by this module; errors are suppressed.

**Fix:** Reset only the properties the module configures, or document and confirm the broad reset; surface failures instead of SilentlyContinue.

---

### 18. [Bug] netsh in Reset-UjBaseline: exit codes never checked

**Description:** All netsh commands in the reset loop are run without checking `$LASTEXITCODE`; try/catch does not catch exit-code failures.

**Fix:** After each `& netsh @netshArgs`, check `$LASTEXITCODE` and warn or fail on non-zero; optionally capture output for diagnostics.

---

## High

### 19. [Bug] DryRun ignored for Backup and Restore

**Description:** The public `-DryRun` switch is not passed to `Backup-UjState` or `Restore-UjState`, and does not prevent directory creation at entry point.

**Fix:** Pass `-DryRun` into Backup/Restore and make both respect it (no writes). Skip `New-UjDirectory` when `-DryRun` is set.

---

### 20. [Bug] Get-UjManagedQosPolicy hides Get-NetQosPolicy failures

**Description:** On catch, the function returns nothing, so “no policies” and “cmdlet failed” look the same; backup/restore cannot tell the difference.

**Fix:** In catch, at least Write-Warning with error details; optionally rethrow or return a distinct result so callers can react (e.g. fail backup if query failed).

---

### 21. [Bug] “Managed” QoS is any policy named QoS_* (no ownership marker)

**Description:** Remove/backup/restore target every policy whose name matches `QoS_*`, including third-party or user-created policies with that prefix.

**Fix:** Document that all QoS_* policies are considered managed; or introduce a stricter naming/metadata contract and only touch those.

---

### 22. [Bug] Port-range policy creation: up to 65,535 policies; only a warning

**Description:** New-UjDscpPolicyByPort creates one policy per port; entry point allows CS2PortStart/End in 1–65535 with no cap. A warning is shown for >100 ports but execution continues.

**Fix:** Add an entry-point or function-level cap (e.g. max range 500) with a clear error, or require an explicit “allow large range” flag; document the risk.

---

### 23. [Bug] Set-UjPowerPlan Ultimate: duplicate-scheme output not used

**Description:** For Ultimate, `powercfg /duplicatescheme $guidUlt` is run but output (new GUID) is discarded; then `powercfg /S $guid` uses the original GUID, which may not be active on systems that require duplication.

**Fix:** Capture the output of `/duplicatescheme`, parse the new GUID, and use it in `powercfg /S` when duplication was used.

---

### 24. [Bug] NIC CSV backup/restore: type loss and empty RegistryValue

**Description:** Export-Csv/Import-Csv round-trip values as strings; non-scalar or enum values can become wrong. Restore treats empty string RegistryValue as valid because `$null -ne $property.RegistryValue` is true for `''`.

**Fix:** For restore, treat empty string RegistryValue as invalid (e.g. require non-empty or explicit “clear” sentinel). Document CSV limitations for complex property values.

---

### 25. [Bug] RSC restore: single enable/disable (IPv4/IPv6 state lost)

**Description:** Restore combines IPv4Enabled and IPv6Enabled into one flag and calls Enable or Disable without protocol; mixed state (e.g. IPv4 on, IPv6 off) is lost.

**Fix:** Use protocol-specific enable/disable where the API allows, or document that restore only applies a single RSC on/off state.

---

### 26. [Bug] NIC tuning: DisplayName match is locale/driver fragile; silent no-op

**Description:** Support is determined by exact DisplayName match. On localized or different-driver systems the match fails and the function returns with no warning, so tuning can be partially or fully skipped without feedback.

**Fix:** Prefer RegistryKeyword where stable; when using DisplayName, log (Verbose or Warning) when a requested property is not found so operators know what was skipped.

---

### 27. [Bug] Entry point: no StrictMode/ErrorActionPreference; partial apply on non-terminating errors

**Description:** The public function does not set Set-StrictMode or $ErrorActionPreference = 'Stop'. Non-terminating errors from downstream cmdlets can be ignored and the apply flow can continue in a partially failed state.

**Fix:** Set StrictMode and ErrorActionPreference at module or function scope (or document that callers must); use -ErrorAction Stop on critical cmdlet calls so failures are visible.

---

### 28. [Bug] External commands: LASTEXITCODE not checked (reg, powercfg, netsh)

**Description:** Several places run reg.exe, powercfg, or netsh and only use try/catch; exit-code failures are not detected.

**Fix:** After every external command, check `$LASTEXITCODE` and treat non-zero as failure (warn or throw); apply to Export-UjRegistryKey, Import-UjRegistryFile, Set-UjPowerPlan, Set-UjUroState, Reset-UjBaseline netsh loop, and power plan restore.

---

## Quick reference: common failure causes

| Symptom | Typical cause | Fix / see |
|--------|----------------|-----------|
| “Restore complete” but registry/MMCSS unchanged | Missing .reg files or reg.exe import failed | Check backup folder for SystemProfile.reg, AFD_Parameters.reg; run with -Verbose; ensure LASTEXITCODE checked after reg import |
| QoS policies gone after restore | Remove ran, then recreate failed (import/parse or New-NetQosPolicy) | Validate qos_ours.xml before remove; add per-policy error handling; see §§ 7, 13 |
| -WhatIf still changes registry/QoS | Restore/Reset do not gate import/removal with ShouldProcess | § 1, 11, 12 |
| Run crashes when -DisableGameDvr | Set-ItemProperty -Type DWord invalid | § 3, 16 |
| Power plan not restored | GUID in powerplan.txt without braces; regex does not match | § 2, 15 |
| netsh / URO “succeeded” but nothing changed | Exit code not checked; try/catch does not catch exit-code failure | § 5, 18, 28 |
| Backup “succeeded” but .reg files empty/missing | reg.exe export failed; only Verbose written | § 8, 28 |
| NIC tuning “applied” but no change | DisplayName mismatch (locale/driver); silent return | § 26 |
| ResetDefaults changed more than expected | Reset-NetAdapterAdvancedProperty -DisplayName '*' | § 4, 17 |
| Large port range (e.g. 1–65535) | No cap at entry; one policy per port | § 22 |
| Deprecated script fails with named params | Empty param(); only $args forwarded | § 10 |

---

## Using this list for issues

- **Labels:** Use `bug`, `enhancement`, `documentation`, `operational` as appropriate.
- **Title:** Use the `[Bug]` / `[Enhancement]` prefix or a corresponding label.
- **Body:** Copy the relevant section (description, impact, fix) into the issue.
- The **quick reference** table can be linked from the README or a “Troubleshooting” doc and reused in a meta-issue for common problems.
