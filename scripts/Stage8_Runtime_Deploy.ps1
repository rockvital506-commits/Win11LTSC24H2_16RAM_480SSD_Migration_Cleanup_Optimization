<#
.SYNOPSIS
    Оркестратор Stage 8: развёртывание рабочей среды C:\Vitality (ADR-0017).

.DESCRIPTION
    Фазы:
      P0  предусловия: манифест, allow-list, признаки закрытых Stage 6 и Stage 7;
      P1  развёртывание: runtime/bootstrap/Deploy-Runtime.ps1 (идемпотентно);
      P2  верификация: runtime/bootstrap/Assert-RuntimeState.ps1 (только чтение);
      P3  сводный отчёт docs/artifacts/Stage8_preflight.md.

    Скрипт только оркестрирует (AR-501): предметная логика — в домене runtime/.
    Сеть не поднимает (AR-709); удаление чего-либо не выполняет (AR-201).

.PARAMETER RepoRoot
    Корень репозитория.

.PARAMETER ApplyAcl
    Передать в развёртывание применение прав (AR-204, AR-506).

.PARAMETER AcknowledgeProposedComposition
    Подтвердить развёртывание состава со статусом PROPOSED (S8-OPEN-1).

.PARAMETER SkipDeploy
    Не выполнять фазу P1 (только проверки).

.PARAMETER SkipVerify
    Не выполнять фазу P2.

.PARAMETER Audit
    Режим проверки: P1 выполняется в -Audit, изменения не вносятся.

.PARAMETER VerificationReport
    Путь к отчёту (по умолчанию docs/artifacts/Stage8_preflight.md).

.EXAMPLE
    pwsh -File ./scripts/Stage8_Runtime_Deploy.ps1 -Audit
    pwsh -File ./scripts/Stage8_Runtime_Deploy.ps1 -ApplyAcl

.NOTES
    Script-ID  : SCRIPT-STAGE8-001
    Stage      : 8
    Patterns   : PAT-19, PAT-20
    ADR        : ADR-0017
    Rules      : AUTOMATION_RULES.md (AR-201, AR-204, AR-206, AR-301, AR-302, AR-303, AR-306, AR-307, AR-501, AR-506, SC_SSD_LONGEVITY, AR-709)
    Depends    : runtime/**, scripts/common/*
    Author     : AI-агент (Arena.ai)
    Created    : 2026-10-01
    Schema     : 3.0.0
#>

#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),

    [switch]$ApplyAcl,

    [switch]$AcknowledgeProposedComposition,

    [switch]$SkipDeploy,

    [switch]$SkipVerify,

    [switch]$Audit,

    [string]$VerificationReport
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $RepoRoot 'scripts/common/Logging.psm1')      -Force
Import-Module (Join-Path $RepoRoot 'scripts/common/Verification.psm1') -Force
Import-Module (Join-Path $RepoRoot 'scripts/common/Guard.psm1')        -Force

$exit     = Get-ExitCode
$scriptId = 'SCRIPT-STAGE8-001'
$report   = if ($VerificationReport) { $VerificationReport } else { Join-Path $RepoRoot 'docs/artifacts/Stage8_preflight.md' }
$manifestPath = Join-Path $RepoRoot 'runtime/manifests/RuntimeManifest.json'

function Invoke-SubScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [hashtable]$Arguments = @{}
    )
    if (-not (Test-Path -LiteralPath $Path)) { return 99 }
    $global:LASTEXITCODE = 0
    & $Path @Arguments
    $code = $LASTEXITCODE
    if ($null -eq $code) { $code = 0 }
    return [int]$code
}

try {
    Start-LogSession -RepoRoot $RepoRoot -ScriptId $scriptId | Out-Null
    $context = New-VerificationContext -Title 'Stage 8 — рабочая среда C:\Vitality'

    # --- P0: предусловия ---
    Add-VerificationCheck -Context $context -Id 'P0.1' -Check 'Манифест состава' -Expected 'RuntimeManifest.json' `
        -Actual $(if (Test-Path -LiteralPath $manifestPath) { 'существует' } else { 'отсутствует' }) `
        -Status $(if (Test-Path -LiteralPath $manifestPath) { 'PASS' } else { 'FAIL' }) -Note 'ADR-0017'

    $task = & schtasks.exe /query /tn 'System_Immunity_Core' 2>$null
    $taskOk = ($LASTEXITCODE -eq 0)
    Add-VerificationCheck -Context $context -Id 'P0.2' -Check 'Контур Stage 6 активен' -Expected 'задача System_Immunity_Core' `
        -Actual $(if ($taskOk) { 'зарегистрирована' } else { 'не найдена' }) -Status $(if ($taskOk) { 'PASS' } else { 'WARN' }) `
        -Note 'Проверка перед развёртыванием; отсутствие задачи — стоп для приёмки (Assert-ImmunityState.ps1).'

    $wsl = & wsl.exe -l -q 2>$null
    $wslOk = ($LASTEXITCODE -eq 0 -and @($wsl).Count -gt 0)
    Add-VerificationCheck -Context $context -Id 'P0.3' -Check 'Контур Stage 7 поднят' -Expected 'дистрибутив WSL2' `
        -Actual $(if ($wslOk) { 'есть' } else { 'не обнаружен' }) -Status $(if ($wslOk) { 'PASS' } else { 'WARN' }) -Note 'Stage 8 не изменяет DevOps-контур (ADR-0017).'

    if ($Audit) { Write-Log -Level 'AUDIT' -Component $scriptId -Message 'Режим -Audit для всех фаз.' }

    # --- P1: развёртывание ---
    if (-not $SkipDeploy) {
        $deployArgs = @{ RepoRoot = $RepoRoot; VerificationReport = (Join-Path $RepoRoot 'docs/artifacts/Stage8_preflight.md') }
        if ($Audit) { $deployArgs['Audit'] = $true }
        if ($ApplyAcl) { $deployArgs['ApplyAcl'] = $true }
        if ($AcknowledgeProposedComposition) { $deployArgs['AcknowledgeProposedComposition'] = $true }
        Write-Log -Component $scriptId -Message 'P1: развёртывание рабочей среды...'
        $code = Invoke-SubScript -Path (Join-Path $RepoRoot 'runtime/bootstrap/Deploy-Runtime.ps1') -Arguments $deployArgs
        Add-VerificationCheck -Context $context -Id 'P1.1' -Check 'Развёртывание выполнено' -Expected 'код 0' -Actual ('код {0}' -f $code) `
            -Status $(if ($code -eq 0) { 'PASS' } else { 'WARN' }) -Note 'AR-302: результат фазы фиксируется отчётом Stage8_preflight.md.'
    }

    # --- P2: верификация ---
    if (-not $SkipVerify) {
        Write-Log -Component $scriptId -Message 'P2: верификация состояния среды...'
        $code = Invoke-SubScript -Path (Join-Path $RepoRoot 'runtime/bootstrap/Assert-RuntimeState.ps1') `
            -Arguments @{ RepoRoot = $RepoRoot; ExportReport = (Join-Path $RepoRoot 'docs/artifacts/Stage8_runtime.md') }
        Add-VerificationCheck -Context $context -Id 'P2.1' -Check 'Верификация среды' -Expected 'код 0' -Actual ('код {0}' -f $code) `
            -Status $(if ($code -eq 0) { 'PASS' } else { 'FAIL' }) -Note 'Отчёт: docs/artifacts/Stage8_runtime.md.'
    }

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
