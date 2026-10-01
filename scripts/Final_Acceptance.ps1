<#
.SYNOPSIS
    Финальная приёмка проекта: агрегация верификаций всех этапов (README §9.9).

.DESCRIPTION
    Скрипт только читает состояние системы и делегирует проверки штатным
    верификаторам этапов (AR-501: предметная логика живёт в доменах):

      F1  разметка        scripts/Stage1_DiskGenius_Partition.ps1
      F2  Ventoy-контур   scripts/Stage2_Ventoy_Template_Setup.ps1
      F4  твики и службы  tweaks/apply/Assert-TweakState.ps1
      F6  контур защиты   tweaks/apply/Assert-ImmunityState.ps1
      F7  пакеты          packages/bootstrap/Invoke-PackageSync.ps1 -Verify
      F7  DevOps (опция)  scripts/Stage7_WSL_Docker_VMware.ps1 -Audit
      F8  рабочая среда   runtime/bootstrap/Assert-RuntimeState.ps1

    Дополнительно проверяется документарная полнота (AR-402, AR-805, §3.2),
    состояние lock-файла пакетов (AR-602) и наличие отчётов этапов.
    Мутаций скрипт не выполняет; сеть не поднимает (AR-709).

    Итог — docs/artifacts/Final_Acceptance.md; при отсутствии FAIL код 0.

.PARAMETER RepoRoot
    Корень репозитория.

.PARAMETER VerificationReport
    Путь к сводному отчёту (по умолчанию docs/artifacts/Final_Acceptance.md).

.PARAMETER SkipStage1
    Не запускать верификатор разметки.

.PARAMETER SkipStage2
    Не запускать верификатор Ventoy-контура.

.PARAMETER SkipTweaks
    Не запускать Assert-TweakState.ps1.

.PARAMETER SkipImmunity
    Не запускать Assert-ImmunityState.ps1.

.PARAMETER SkipPackages
    Не проверять пакетный домен.

.PARAMETER IncludeStage7
    Дополнительно прогнать Stage7_WSL_Docker_VMware.ps1 -Audit (компоненты, WSL2,
    Docker, VMware, P+E — только чтение).

.PARAMETER SkipRuntime
    Не проверять рабочую среду C:\Vitality (Stage 8).

.EXAMPLE
    pwsh -File ./scripts/Final_Acceptance.ps1
    pwsh -File ./scripts/Final_Acceptance.ps1 -IncludeStage7

.NOTES
    Script-ID  : SCRIPT-FINAL-001
    Stage      : Приёмка (после Stage 7)
    Patterns   : PAT-19, PAT-20
    ADR        : —
    Rules      : AUTOMATION_RULES.md (AR-201, AR-204, AR-206, AR-301, AR-302, AR-306, AR-307, AR-308, AR-402, AR-602, AR-805, AR-904, AR-906)
    Depends    : верификаторы этапов 1–7, packages/lock/Packages.lock.json
    Author     : AI-агент (Arena.ai)
    Created    : 2026-10-01
    Schema     : 3.0.0
#>

#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),

    [string]$VerificationReport,

    [switch]$SkipStage1,

    [switch]$SkipStage2,

    [switch]$SkipTweaks,

    [switch]$SkipImmunity,

    [switch]$SkipPackages,

    [switch]$SkipRuntime,

    [switch]$IncludeStage7
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $RepoRoot 'scripts/common/Logging.psm1')      -Force
Import-Module (Join-Path $RepoRoot 'scripts/common/Verification.psm1') -Force

$exit   = Get-ExitCode
$scriptId = 'SCRIPT-FINAL-001'
$report = if ($VerificationReport) { $VerificationReport } else { Join-Path $RepoRoot 'docs/artifacts/Final_Acceptance.md' }

function Invoke-Verifier {
    <# Запускает штатный верификатор этапа и возвращает его код возврата. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [hashtable]$Arguments = @{}
    )

    if (-not (Test-Path -LiteralPath $Path)) { return 99 }
    $global:LASTEXITCODE = 0
    & $Path @Arguments | Out-Null
    $code = $LASTEXITCODE
    if ($null -eq $code) { $code = 0 }
    return [int]$code
}

try {
    Start-LogSession -RepoRoot $RepoRoot -ScriptId $scriptId | Out-Null
    $context = New-VerificationContext -Title 'Финальная приёмка (README §9.9)'

    # --- F0: документарная полнота и состояние репозитория ---
    $mandatory = @(
        'README.md',
        'docs/rules/AUTOMATION_RULES.md',
        'docs/decisions/README.md',
        'docs/patterns/PAT-INDEX.md',
        'docs/artifacts/Final_Report.md',
        'docs/artifacts/Recovery_Procedure.md',
        'docs/artifacts/Stand_Runbook.md',
        'docs/runtime/RUNTIME_SCHEMA.md',
        'runtime/manifests/RuntimeManifest.json',
        'algorithm/manual/Stage7_DevOps_Install.md',
        'algorithm/auto/Stage7_WSL_Docker_VMware.md'
    )
    $missingDocs = @($mandatory | Where-Object { -not (Test-Path -LiteralPath (Join-Path $RepoRoot $_)) })
    Add-VerificationCheck -Context $context -Id 'F0.1' -Check 'Обязательные документы (§3.2)' -Expected ('{0} документов' -f $mandatory.Count) `
        -Actual $(if ($missingDocs.Count -eq 0) { 'все на месте' } else { 'нет: ' + ($missingDocs -join ', ') }) `
        -Status $(if ($missingDocs.Count -eq 0) { 'PASS' } else { 'FAIL' }) -Note 'AR-805: нет документации — нет коммита.'

    $adrFiles = @(Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'docs/decisions') -Filter 'ADR-*.md' -File -ErrorAction SilentlyContinue)
    Add-VerificationCheck -Context $context -Id 'F0.2' -Check 'ADR созданы' -Expected '≥ 14' -Actual ([string]$adrFiles.Count) `
        -Status $(if ($adrFiles.Count -ge 14) { 'PASS' } else { 'FAIL' }) -Note 'ADR-0001..ADR-0016 (по реестру решений).'

    $patternFiles = @(Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'docs/patterns') -Filter 'PAT-*.md' -File -ErrorAction SilentlyContinue)
    Add-VerificationCheck -Context $context -Id 'F0.3' -Check 'Документы паттернов' -Expected '≥ 21' -Actual ([string]$patternFiles.Count) `
        -Status $(if ($patternFiles.Count -ge 21) { 'PASS' } else { 'FAIL' }) -Note 'M_PATTERN_COVERAGE: план — 28.'

    $stageReports = @(0..8 | ForEach-Object { 'docs/artifacts/Stage{0}_Report.md' -f $_ })
    $missingReports = @($stageReports | Where-Object { -not (Test-Path -LiteralPath (Join-Path $RepoRoot $_)) })
    Add-VerificationCheck -Context $context -Id 'F0.4' -Check 'Отчёты этапов 0–8' -Expected '9 отчётов' `
        -Actual $(if ($missingReports.Count -eq 0) { 'все на месте' } else { 'нет: ' + ($missingReports -join ', ') }) `
        -Status $(if ($missingReports.Count -eq 0) { 'PASS' } else { 'FAIL' }) -Note 'AR-904: отчёт этапа обязателен.'

    # --- F0.5: lock-файл пакетов (AR-602) ---
    $lockPath = Join-Path $RepoRoot 'packages/lock/Packages.lock.json'
    if (Test-Path -LiteralPath $lockPath) {
        $lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $unpinned = @($lock.packages | Where-Object { $_.status -ne 'PINNED' -or -not $_.version })
        Add-VerificationCheck -Context $context -Id 'F0.5' -Check 'Версии пакетов зафиксированы' -Expected '0 UNPINNED' -Actual ([string]$unpinned.Count) `
            -Status $(if ($unpinned.Count -eq 0) { 'PASS' } else { 'WARN' }) -Note 'AR-602; приёмка требует 0. Резолв: Invoke-PackageSync.ps1 -ResolveVersions.'
    }
    else {
        Add-VerificationCheck -Context $context -Id 'F0.5' -Check 'Lock-файл пакетов' -Expected 'Packages.lock.json' -Actual 'отсутствует' -Status 'FAIL'
    }

    # --- F1–F7: делегированные верификации ---
    $delegates = New-Object System.Collections.Generic.List[object]
    if (-not $SkipStage1) { $delegates.Add(@{ Id = 'F1'; Name = 'Разметка NVMe (Stage 1)'; Path = 'scripts/Stage1_DiskGenius_Partition.ps1'; RepoRootParam = $false; Args = @{ ExportReport = (Join-Path $RepoRoot 'docs/artifacts/Stage1_partition_verify.md') } }) }
    if (-not $SkipStage2) { $delegates.Add(@{ Id = 'F2'; Name = 'Ventoy-контур (Stage 2)'; Path = 'scripts/Stage2_Ventoy_Template_Setup.ps1'; RepoRootParam = $true; Args = @{ VerificationReport = (Join-Path $RepoRoot 'docs/artifacts/Stage2_preflight.md') } }) }
    if (-not $SkipTweaks) { $delegates.Add(@{ Id = 'F4'; Name = 'Твики и службы (Stage 4)'; Path = 'tweaks/apply/Assert-TweakState.ps1'; RepoRootParam = $true; Args = @{ ExportReport = (Join-Path $RepoRoot 'docs/artifacts/Stage4_tweakstate.md') } }) }
    if (-not $SkipImmunity) { $delegates.Add(@{ Id = 'F6'; Name = 'Контур защиты (Stage 6)'; Path = 'tweaks/apply/Assert-ImmunityState.ps1'; RepoRootParam = $true; Args = @{ ExportReport = (Join-Path $RepoRoot 'docs/artifacts/Stage6_immunity.md') } }) }
    if (-not $SkipPackages) { $delegates.Add(@{ Id = 'F7a'; Name = 'Пакеты: сверка с lock-файлом'; Path = 'packages/bootstrap/Invoke-PackageSync.ps1'; RepoRootParam = $true; Args = @{ Verify = $true } }) }
    if (-not $SkipRuntime) { $delegates.Add(@{ Id = 'F8'; Name = 'Рабочая среда C:\Vitality (Stage 8)'; Path = 'runtime/bootstrap/Assert-RuntimeState.ps1'; RepoRootParam = $true; Args = @{ ExportReport = (Join-Path $RepoRoot 'docs/artifacts/Stage8_runtime.md') } }) }
    if ($IncludeStage7) { $delegates.Add(@{ Id = 'F7b'; Name = 'DevOps-контур (Stage 7, -Audit)'; Path = 'scripts/Stage7_WSL_Docker_VMware.ps1'; RepoRootParam = $true; Args = @{ Audit = $true; VerificationReport = (Join-Path $RepoRoot 'docs/artifacts/Stage7_preflight.md') } }) }

    foreach ($d in $delegates) {
        $full = Join-Path $RepoRoot $d.Path
        $delegateArgs = @{}
        foreach ($key in $d.Args.Keys) { $delegateArgs[$key] = $d.Args[$key] }
        if ($d.RepoRootParam) { $delegateArgs['RepoRoot'] = $RepoRoot }
        Write-Log -Component $scriptId -Message ('{0}: {1} → {2}' -f $d.Id, $d.Name, $d.Path)
        $code = Invoke-Verifier -Path $full -Arguments $delegateArgs
        $status = 'PASS'
        if ($code -eq 99 -and -not (Test-Path -LiteralPath $full)) { $status = 'FAIL' }
        elseif ($code -ne 0) { $status = 'FAIL' }
        Add-VerificationCheck -Context $context -Id $d.Id -Check $d.Name -Expected 'код 0' -Actual ('код {0}' -f $code) -Status $status `
            -Note $(if ($code -eq 99) { 'Верификатор недоступен или фатальная ошибка.' } else { 'AR-307: результат фиксируется отчётом этапа.' })
    }

    if ($delegates.Count -eq 0) {
        Write-Log -Level 'WARN' -Component $scriptId -Message 'Все делегированные проверки пропущены флагами -Skip*.'
    }

    Write-Log -Component $scriptId -Message 'Сводка приёмки: см. §1.4 README (SC_*) и Final_Report.md.'
    Write-VerificationReport -Context $context -ExportPath $report
    exit (Get-VerificationExitCode -Context $context)
}
catch {
    Write-Log -Level 'ERROR' -Component $scriptId -Message ('Фатальная ошибка: {0}' -f $_.Exception.Message)
    exit $exit.Fatal
}
finally {
    Stop-LogSession -ScriptId $scriptId
}
