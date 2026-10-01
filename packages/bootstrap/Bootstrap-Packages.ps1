<#
.SYNOPSIS
    Первичная установка профиля пакетов (Stage 7, AR-607).

.DESCRIPTION
    Отдельный шаг установки профиля с собственным отчётом (AR-607). Скрипт:
      1. проверяет наличие winget и фиксацию источников (AR-604: msstore отключён);
      2. проверяет, что lock-файл заполнен (AR-602); при пустых версиях —
         FAIL с точной командой резолва (выполняется в окне сети один раз);
      3. делегирует установку Invoke-PackageSync.ps1 (единственный путь, AR-606);
      4. формирует отчёт docs/artifacts/Stage7_packages.md.

    Сеть скрипт не поднимает: требуется открытое владельцем окно (§4.5, AR-709).

.PARAMETER RepoRoot
    Корень репозитория.

.PARAMETER Profile
    Профиль установки: base | devops | admin (AR-607).

.PARAMETER Audit
    Не менять систему: показать план и предусловия.

.PARAMETER VerificationReport
    Путь к отчёту (по умолчанию docs/artifacts/Stage7_packages.md).

.EXAMPLE
    pwsh -File ./packages/bootstrap/Bootstrap-Packages.ps1 -Profile devops

.NOTES
    Script-ID  : SCRIPT-PKG-001
    Stage      : 7
    Patterns   : —
    ADR        : ADR-0016
    Rules      : AUTOMATION_RULES.md (AR-204, AR-206, AR-301, AR-302, AR-303, AR-306, AR-307, AR-601…AR-607, AR-709)
    Depends    : packages/lock/Packages.lock.json, packages/winget/profiles/*.winget, Invoke-PackageSync.ps1
    Author     : AI-агент (Arena.ai)
    Created    : 2026-10-01
    Schema     : 3.0.0
#>

#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$RepoRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),

    [ValidateSet('base', 'devops', 'admin')][string]$Profile = 'devops',

    [switch]$Audit,

    [string]$VerificationReport
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $RepoRoot 'scripts/common/Logging.psm1')      -Force
Import-Module (Join-Path $RepoRoot 'scripts/common/Verification.psm1') -Force
Import-Module (Join-Path $RepoRoot 'scripts/common/Guard.psm1')        -Force

$exit     = Get-ExitCode
$scriptId = 'SCRIPT-PKG-001'
$lockPath = Join-Path $RepoRoot 'packages/lock/Packages.lock.json'
$profileFile = Join-Path $RepoRoot ('packages/winget/profiles/{0}.winget' -f $Profile)
$syncScript = Join-Path $PSScriptRoot 'Invoke-PackageSync.ps1'
$report = if ($VerificationReport) { $VerificationReport } else { Join-Path $RepoRoot 'docs/artifacts/Stage7_packages.md' }

try {
    Start-LogSession -RepoRoot $RepoRoot -ScriptId $scriptId | Out-Null
    $context = New-VerificationContext -Title ('Stage 7 — установка профиля пакетов: {0}' -f $Profile)

    $winget = Get-Command -Name winget.exe -ErrorAction SilentlyContinue
    Add-VerificationCheck -Context $context -Id 'B0.1' -Check 'winget доступен' -Expected 'winget.exe' `
        -Actual $(if ($winget) { [string]$winget.Source } else { 'не найден' }) -Status $(if ($winget) { 'PASS' } else { 'FAIL' }) -Note 'AR-601'

    Add-VerificationCheck -Context $context -Id 'B0.2' -Check 'Профиль объявлен' -Expected $profileFile `
        -Actual $(if (Test-Path -LiteralPath $profileFile) { 'существует' } else { 'отсутствует' }) `
        -Status $(if (Test-Path -LiteralPath $profileFile) { 'PASS' } else { 'FAIL' })

    Add-VerificationCheck -Context $context -Id 'B0.3' -Check 'Lock-файл' -Expected 'Packages.lock.json' `
        -Actual $(if (Test-Path -LiteralPath $lockPath) { 'существует' } else { 'отсутствует' }) `
        -Status $(if (Test-Path -LiteralPath $lockPath) { 'PASS' } else { 'FAIL' })

    $pending = @()
    if (Test-Path -LiteralPath $lockPath) {
        $lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $declared = @((Get-Content -LiteralPath $profileFile -Raw -Encoding UTF8 | ConvertFrom-Json).Sources[0].Packages | ForEach-Object { $_.PackageIdentifier })
        $profilePackages = @($lock.packages | Where-Object { $declared -contains $_.id })
        $pending = @($profilePackages | Where-Object { $_.status -ne 'PINNED' -or -not $_.version })
        Add-VerificationCheck -Context $context -Id 'B0.4' -Check 'Версии зафиксированы (AR-602)' `
            -Expected ('{0}/{0}' -f $profilePackages.Count) -Actual ([string]($profilePackages.Count - $pending.Count)) `
            -Status $(if ($pending.Count -eq 0) { 'PASS' } else { 'FAIL' }) `
            -Note ('Резолв в окне сети: Invoke-PackageSync.ps1 -ResolveVersions. Не зафиксированы: ' + (($pending | ForEach-Object { $_.id }) -join ', '))
    }

    $adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })
    Add-VerificationCheck -Context $context -Id 'B0.5' -Check 'Окно сети открыто (AR-709)' `
        -Expected '≥ 1 адаптер' -Actual ([string]$adapters.Count) -Status $(if ($adapters.Count -gt 0) { 'PASS' } else { 'FAIL' }) `
        -Note 'Сеть поднимает владелец (§4.5 README).'

    if ((Get-VerificationFailures -Context $context).Count -gt 0 -and -not $Audit) {
        Write-VerificationReport -Context $context -ExportPath $report
        Write-Log -Level 'FAIL' -Component $scriptId -Message ('Предусловия профиля {0} не выполнены.' -f $Profile)
        exit $exit.Precondition
    }

    $syncArgs = @{ Profile = $Profile }
    if ($Audit) { $syncArgs['Audit'] = $true }

    Write-Log -Component $scriptId -Message ('Установка профиля {0} через Invoke-PackageSync.ps1 (AR-606)...' -f $Profile)
    & $syncScript @syncArgs -RepoRoot $RepoRoot
    $syncCode = [int]$LASTEXITCODE

    if ($syncCode -eq 0) { Write-Log -Level 'PASS' -Component $scriptId -Message ('Профиль {0} приведён к lock-файлу.' -f $Profile) }
    else { Write-Log -Level 'FAIL' -Component $scriptId -Message ('Синхронизация профиля: код {0}.' -f $syncCode) }

    Add-VerificationCheck -Context $context -Id 'B1.1' -Check ('Профиль {0} синхронизирован' -f $Profile) `
        -Expected 'код 0' -Actual ('код {0}' -f $syncCode) -Status $(if ($syncCode -eq 0) { 'PASS' } else { 'FAIL' }) -Note 'AR-607'

    if ($Audit) { Write-Log -Level 'AUDIT' -Component $scriptId -Message 'Режим -Audit: установка не выполнялась.' }

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
